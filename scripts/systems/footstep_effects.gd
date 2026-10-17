class_name FootstepEffects
extends RefCounted

## Effect routers the player fires on foot plants, skids and tumbles — the decomp's
## `eWalk_Asimoto_init`, `eDashAsimoto_ct`, `eTurnAsimoto_init`, `eTumble_CallEffect`,
## `eHanatiri_ct`, which pick `FieldEffects` / `TreeEffects` particles by the unit attribute,
## season and weather — and those its tools fire: the shovel (`eDig_Hole_init`,
## `eDig_Scoop_init`), the axe (`eSwing_Axe_init`), the net in water (`eSwing_Net_init`) and
## the bobber (`eTM_CallEffect`). Positions are world metres; offsets below are GX.

## `mCoBG_ATTRIBUTE_*`.
const ATTR_GRASS0 := 0
const ATTR_GRASS3 := 3
const ATTR_FLOOR := 8
const ATTR_BUSH := 9
const ATTR_WAVE := 11
const ATTR_SAND := 22
const GX := FieldCatalog.GX_TO_METERS

static var _grid: WorldGrid
static var _data: WorldData
static var _world: World


static func is_grass(attr: int) -> bool:
	return attr >= ATTR_GRASS0 and attr <= ATTR_GRASS3


static func hole_at(pos: Vector3) -> bool:
	if _grid == null:
		return false
	var cell: Vector2i = _grid.world_to_cell(pos)
	if not _grid.is_in_bounds(cell):
		return false
	return String(_grid.occupant_at(cell)).begins_with("hole")


## `IS_ITEM_GROWN_FLOWER` on the unit under `pos` → 0..8 (`item − FLOWER_PANSIES0`: pansy,
## cosmos, tulip × 3 colours), −1 when there is none.
static func flower_index(pos: Vector3) -> int:
	if _grid == null or _world == null:
		return -1
	var cell: Vector2i = _grid.world_to_cell(pos)
	if not _grid.is_in_bounds(cell):
		return -1
	var host: Node3D = PlantGrowth.host_at(_world, _grid.occupant_at(cell))
	if host == null:
		return -1
	return flower_index_for_visual(StringName(str(host.get("visual_id"))))


static func flower_index_for_visual(visual: StringName) -> int:
	var id := String(visual)
	for pair: Array in [["FLOWER_PANSIES", 0], ["FLOWER_COSMOS", 3], ["FLOWER_TULIP", 6]]:
		var prefix: String = pair[0]
		if id.begins_with(prefix) and id.length() == prefix.length() + 1:
			return int(pair[1]) + clampi(int(id.substr(prefix.length())), 0, 2)
	return -1


## `[layout, grid]` of the world `ctx` is in, the way the player passes it.
static func bg_of(ctx: InteractionContext) -> Array:
	var world: Node = ctx.world if ctx != null else null
	if world == null:
		return []
	var data: Variant = world.get("layout")
	var grid: Variant = world.get("grid")
	return [data, grid] if data is WorldData and grid is WorldGrid else []


## `mCoBG_Wpos2Attribute` at `pos`, or -1 off the field.
static func attr_at(bg: Array, pos: Vector3) -> int:
	if bg.size() != 2:
		return -1
	return FieldCollision.unit_attr_at(bg[0] as WorldData, bg[1] as WorldGrid, pos)


static func _bind(bg: Array) -> Node:
	_data = bg[0] as WorldData if bg.size() == 2 else null
	_grid = bg[1] as WorldGrid if bg.size() == 2 else null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	_world = World.find(tree)
	if _world == null:
		return null
	var effects: Node = _world.get_node_or_null("Effects")
	return effects if effects != null else _world


static func _ground_sampler() -> Callable:
	var data := _data
	var grid := _grid
	if data == null or grid == null:
		return Callable()
	return func(p: Vector3) -> float: return FieldCollision.ground_y_at(data, grid, p)


static func _slope(pos: Vector3) -> Basis:
	if _data == null or _grid == null:
		return Basis.IDENTITY
	var xf: Transform3D = FootprintMarks.mark_transform(_data, _grid, pos, 0.0)
	return xf.basis.orthonormalized() if xf.basis.determinant() != 0.0 else Basis.IDENTITY


static func _fx(host: Node, k: FieldEffects.Kind, pos: Vector3, yaw: float, a0: int, a1: int) -> void:
	FieldEffects.spawn(host, k, pos, yaw, a0, a1, _ground_sampler())


static func _ahead(pos: Vector3, yaw: float, gx: float) -> Vector3:
	return pos + Vector3(sin(yaw), 0.0, cos(yaw)) * gx * GX


static func _bush(host: Node, pos: Vector3, count: int, arg1: int, snow: bool) -> void:
	for _i: int in count:
		TreeEffects.bush_leaf(host, pos, arg1)
	if snow:
		for _i: int in count:
			TreeEffects.bush_snow(host, pos)


## `eWalk_Asimoto_init` — walk and run foot plants: only bushes react.
static func walk_step(bg: Array, pos: Vector3, yaw: float, attr: int) -> void:
	var host := _bind(bg)
	if host == null or attr != ATTR_BUSH:
		return
	var at := _ahead(pos, yaw, 10.0)
	## `do { … } while (count-- != 0)` with count 1 → two leaves.
	var winter: bool = not Weather.is_raining() and Clock.season() == Clock.Season.WINTER
	_bush(host, at, 2, 0, winter)


## `eSwing_Net_init` arg1 0 at `Player_actor_SetEffect_Swing_net`: 50 GX ahead, two petals
## off a flower there, and through a bush (net low enough) five leaves, four snow puffs in
## winter.
static func swing_net(bg: Array, pos: Vector3, yaw: float) -> void:
	var host := _bind(bg)
	if host == null:
		return
	var at := _ahead(pos, yaw, 50.0)
	var flower: int = flower_index(at)
	if flower >= 0:
		for _i: int in 2:
			_fx(host, FieldEffects.Kind.PETAL, at, 0.0, flower, 2)
	if _data == null or _grid == null or FieldCollision.unit_attr_at(_data, _grid, at) != ATTR_BUSH:
		return
	var ground: float = FieldCollision.ground_y_at(_data, _grid, at)
	if FieldCollision.has_floor(ground) and pos.y >= ground + 10.0 * GX:
		return
	for _i: int in 5:
		TreeEffects.bush_leaf(host, at, 3)
	if Clock.season() == Clock.Season.WINTER:
		for _i: int in 4:
			TreeEffects.bush_snow(host, at)


## `eSwing_Net_init` arg1 1 on water: eight drops thrown out in a ring from 13 GX behind the
## net (`MIZUTAMA`, speed set 5); true when it was water. `at` is the net head on the surface.
static func net_splash(bg: Array, at: Vector3, yaw: float) -> bool:
	var host := _bind(bg)
	if host == null or _data == null or _grid == null:
		return false
	var attr: int = FieldCollision.unit_attr_at(_data, _grid, at)
	if not (FieldCatalog.is_water_attr(attr) or attr == ATTR_WAVE):
		return false
	var drop := at + Vector3(sin(yaw), 0.0, cos(yaw)) * -13.0 * GX + Vector3(0.0, 5.0 * GX, 0.0)
	for i: int in 8:
		var a: float = deg_to_rad(45.0 * i + randf_range(-40.0, 40.0))
		_fx(host, FieldEffects.Kind.MIZUTAMA, drop, a, attr, 0x5000)
	## The splash itself and a ring where it went in, then `eSwing_Net_call_stick_effect`:
	## three rings stepping a sixth of the way back toward the player each, smaller each time.
	_fx(host, FieldEffects.Kind.AMI_MIZU, at, yaw, 0, 0)
	var surface := Vector3(drop.x, at.y, drop.z)
	FieldEffects.spawn(host, FieldEffects.Kind.HAMON, surface, 0.0, 0, 0)
	var player: Node3D = Player.find(host.get_tree()) if host.is_inside_tree() else null
	if player != null:
		var step: Vector3 = (player.global_position - surface) / 6.0
		for n: int in 3:
			surface += Vector3(step.x, 0.0, step.z)
			FieldEffects.spawn(host, FieldEffects.Kind.HAMON, surface, 0.0, n + 1, 0)
	return true


## `eDig_Hole_init`: a clod at the midpoint of the hole and the point 30 GX ahead of the
## player (arg1 0–2 digging, 3–5 filling); in the surf it also flicks up two drops.
static func dig_hole(bg: Array, hole: Vector3, player: Vector3, yaw: float, attr: int, arg1: int) -> void:
	var host := _bind(bg)
	if host == null:
		return
	var at := _scoop_point(hole, player, yaw)
	_fx(host, FieldEffects.Kind.DIG_CLOD, at, yaw, attr, arg1)
	if attr == ATTR_WAVE:
		var drop_arg: int = 0x4000 | ((arg1 << 1) if arg1 <= 2 else (5 << 1))
		var heading: float = yaw
		for _i: int in 2:
			heading += deg_to_rad(randf_range(-75.0, 75.0) if arg1 > 2 else randf_range(-45.0, 45.0))
			var p := at + Vector3(randf_range(-10.0, 10.0), 10.0, randf_range(-10.0, 10.0)) * GX
			_fx(host, FieldEffects.Kind.MIZUTAMA, p, heading, attr, drop_arg)


## `eDig_Scoop_init`: what the shovel throws as the scoop comes up. arg1 0 (a hole dug)
## throws six clots of dirt, 3 (dug something up) three; 2 (a hole filled) depends on the
## ground: sand kicks on sand, snow on winter grass, drops in the rain or surf (and a
## splash in the surf), dust otherwise.
static func dig_scoop(bg: Array, hole: Vector3, player: Vector3, yaw: float, attr: int, arg1: int) -> void:
	var host := _bind(bg)
	if host == null:
		return
	var at := _scoop_point(hole, player, yaw)
	match arg1:
		0, 3:
			at.y += 10.0 * GX
			for i: int in range(0 if arg1 == 0 else 3, 6):
				_fx(host, FieldEffects.Kind.DIG_MUD, at, yaw, attr, i)
		2:
			at.y += 5.0 * GX
			var winter: bool = Clock.season() == Clock.Season.WINTER
			if winter and is_grass(attr):
				for i: int in range(2, 6):
					_fx(host, FieldEffects.Kind.YUKIDAMA, at, yaw, attr, 0x3000 | i)
			elif attr == ATTR_SAND:
				var a: float = yaw - PI * 0.25
				for _i: int in 3:
					_fx(host, FieldEffects.Kind.SAND, at + Vector3(sin(a), 0.0, cos(a)) * 15.0 * GX, a, 3, 0)
					a += PI * 0.25
			elif Weather.is_raining() or attr == ATTR_WAVE:
				for i: int in range(2, 6):
					_fx(host, FieldEffects.Kind.MIZUTAMA, at, yaw, attr, 0x3000 | i)
				if attr == ATTR_WAVE:
					_fx(host, FieldEffects.Kind.AMI_MIZU, at, yaw, 1, 0)
			else:
				var a: float = yaw - PI * 0.25
				for i: int in 3:
					_fx(host, FieldEffects.Kind.TUMBLE_DUST, at, a, attr, i)
					a += PI * 0.25


## `Player_actor_SetEffectHit_Dig_scoop`: clods at dig frames 14, 15 and 16 and the dirt at
## 22 (`get` is digging something up: `GET_SCOOP`, three clots). `HoleUse` runs on frame
## 15, so the clods are laid out from there.
static func dig_sequence(bg: Array, hole: Vector3, player: Node3D, attr: int, get: bool) -> void:
	var host := _bind(bg)
	if host == null or player == null or not host.is_inside_tree():
		return
	var tree: SceneTree = host.get_tree()
	var yaw: float = player.call("facing_yaw") if player.has_method("facing_yaw") else player.rotation.y
	var from: Vector3 = player.global_position
	dig_hole(bg, hole, from, yaw, attr, 0)
	for step: Array in [[1.0, 1], [2.0, 2], [8.0, -1]]:
		tree.create_timer(float(step[0]) / DecompTime.FRAME_HZ).timeout.connect(func() -> void:
			if int(step[1]) >= 0:
				dig_hole(bg, hole, from, yaw, attr, int(step[1]))
			else:
				dig_scoop(bg, hole, from, yaw, attr, 3 if get else 0))


## `eDig_*_init`: the midpoint of the target unit and the point 30 GX ahead of the player.
static func _scoop_point(hole: Vector3, player: Vector3, yaw: float) -> Vector3:
	var ahead := _ahead(player, yaw, 30.0)
	return Vector3((hole.x + ahead.x) * 0.5, hole.y, (hole.z + ahead.z) * 0.5)


## `Player_actor_SetEffectStart_axe_common` at frame 12 of every axe swing
## (`eSwing_Axe_init` arg1 1): standing in a bush throws five leaves (and five snow puffs in
## winter), and a grown flower underfoot loses two petals.
static func axe_start(bg: Array, player: Vector3, yaw: float) -> void:
	var host := _bind(bg)
	if host == null:
		return
	if attr_at(bg, player) == ATTR_BUSH:
		_bush(host, player, 5, 1, Clock.season() == Clock.Season.WINTER)
	_axe_petals(host, player)


## `Player_actor_SetEffectHit_Reflect_axe` at frame 15 (arg1 2): two impact stars off the
## axe head as it bounces, and petals off a flower there.
static func axe_bounce(bg: Array, player: Vector3, yaw: float) -> void:
	var host := _bind(bg)
	if host == null:
		return
	var at: Vector3 = player + FieldEffects.rot_y(Vector3(-7.0, 20.0, 24.0), yaw) * GX
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i: int in 2:
		ImpactStar.spawn(host, at, yaw + deg_to_rad(22.5), i, rng)
	_axe_petals(host, at)


## `eSwing_Axe_Hanabira_Make`: two petals (arg1 3) off a grown flower on the unit at `pos`.
static func _axe_petals(host: Node, pos: Vector3) -> void:
	var flower: int = flower_index(pos)
	if flower < 0:
		return
	for _i: int in 2:
		_fx(host, FieldEffects.Kind.PETAL, pos, 0.0, flower, 3)


## `eSwing_Axe_init` arg1 0 on a tree hit: four wood chips from the axe head (the player
## +(−7, 20, 24) GX, turned by the facing).
static func axe_chips(bg: Array, player: Vector3, yaw: float) -> void:
	var host := _bind(bg)
	if host == null:
		return
	var at: Vector3 = player + FieldEffects.rot_y(Vector3(-7.0, 20.0, 24.0), yaw) * GX
	for _i: int in 4:
		_fx(host, FieldEffects.Kind.KIKUZU, at, yaw, 0, 0)


## `eTM_CallEffect` / `eTM_mv`: what the bobber does to the water at `at` (on the surface).
## 0 a bite (ring + small splash, a second ring 15 ticks on), 3 the cast landing (ring +
## `ef_turi_hane02`), 1 / 4–8 the line coming out with nothing or a fish of a size class
## (rings and a splash by size, and 2–4 drops over the next ten ticks).
static func bobber_splash(at: Vector3, arg: int) -> void:
	var host := _bind([])
	if host == null:
		return
	var flow: float = flow_yaw(at)
	var lifted := at + Vector3(0.0, 3.0, 5.0) * GX
	match arg:
		0, 2:
			FieldEffects.spawn(host, FieldEffects.Kind.HAMON, at, flow, 0, 0)
			if arg == 0:
				FieldParticle.spawn(host, FieldEffects.Kind.TURI_HANE, lifted, 0.0, 0, 0)
			if host.is_inside_tree():
				host.get_tree().create_timer(15.0 / 60.0).timeout.connect(func() -> void:
					if is_instance_valid(host):
						FieldEffects.spawn(host, FieldEffects.Kind.HAMON, at, flow, 2, 0))
		3:
			FieldEffects.spawn(host, FieldEffects.Kind.HAMON, at, flow, 0, 0)
			FieldParticle.spawn(host, FieldEffects.Kind.TURI_HANE, lifted, 0.0, 0, 1)
		1, 4, 5, 6, 7, 8:
			if arg == 1:
				FieldEffects.spawn(host, FieldEffects.Kind.HAMON, at, flow, 1, 0)
			else:
				var size: int = arg - 4
				FieldEffects.spawn(host, FieldEffects.Kind.HAMON, at, flow, [1, 0, 0, 1, 2][size], 0)
				FieldParticle.spawn(host, FieldEffects.Kind.TURI_HANE, at, 0.0, size, 0)
			var drops: int = 3 if arg == 4 else (2 if arg == 7 or arg == 8 else 4)
			for i: int in drops:
				_suiteki_later(host, at, i, drops, randi_range(0, 4) * 2.0 / 60.0)


## A drop that leaves `at` after `delay` seconds and rings the water where it falls back.
static func _suiteki_later(host: Node, at: Vector3, index: int, of: int, delay: float) -> void:
	if not host.is_inside_tree():
		return
	var tree: SceneTree = host.get_tree()
	tree.create_timer(delay).timeout.connect(func() -> void:
		if not is_instance_valid(host):
			return
		var drop: FieldParticle = FieldParticle.spawn(host, FieldEffects.Kind.TURI_SUITEKI, at, 0.0, index, of)
		tree.create_timer(FieldParticle.suiteki_flight()).timeout.connect(func() -> void:
			if is_instance_valid(host) and is_instance_valid(drop):
				var fell: Vector3 = drop.global_position + drop.landed_offset()
				FieldEffects.spawn(host, FieldEffects.Kind.HAMON, Vector3(fell.x, at.y, fell.z), 0.0, 3, 0)))


## `setup_main_Rotate_umbrella` → `ef_kasamizu`: 24 ticks of spray off the twirled canopy
## (drops only fly while it rains).
static func umbrella_spray(pos: Vector3, yaw: float) -> FieldEffects:
	var host := _bind([])
	if host == null:
		return null
	return FieldEffects.spawn(host, FieldEffects.Kind.KASAMIZU, pos, yaw)


## `ef_turi_hamon`: a ring on the water at `at` (y on the surface), drifting along the
## river's flow (`mCoBG_GetWaterFlow`; still water gives angle 0, as on the disc).
static func ripple(at: Vector3, arg: int) -> FieldEffects:
	var host := _bind([])
	if host == null:
		return null
	return FieldEffects.spawn(host, FieldEffects.Kind.HAMON, at, flow_yaw(at), arg, 0)


## The flow direction of the water body under `at`, or 0 for still water.
static func flow_yaw(at: Vector3) -> float:
	if _world == null or _world.grid == null or _world.fish == null:
		return 0.0
	var cell: Vector2i = _world.grid.world_to_cell(at)
	for body: WaterBodies.Body in _world.fish.bodies:
		if body.flows and body.contains(cell):
			return body.flow_yaw
	return 0.0


## `eDashAsimoto_ct` — dash foot plants.
static func dash_step(bg: Array, pos: Vector3, yaw: float, attr: int) -> void:
	var host := _bind(bg)
	if host == null:
		return
	var flower: int = flower_index(pos)
	if flower >= 0:
		for _i: int in 2:
			_fx(host, FieldEffects.Kind.PETAL, pos, 0.0, flower, 0)
	var bush_at := _ahead(pos, yaw, 10.0)
	if Weather.is_raining():
		match attr:
			ATTR_BUSH:
				_bush(host, bush_at, 3, 1, false)
			ATTR_FLOOR:
				pass
			ATTR_WAVE:
				_fx(host, FieldEffects.Kind.SIBUKI, pos, yaw, attr, 1)
			_:
				_fx(host, FieldEffects.Kind.SIBUKI, pos, yaw, attr, 0)
		return
	var winter: bool = Clock.season() == Clock.Season.WINTER
	if winter and is_grass(attr):
		_fx(host, FieldEffects.Kind.YUKIHANE, pos, yaw, attr, 0)
		return
	match attr:
		ATTR_BUSH:
			_bush(host, bush_at, 3, 1, winter)
		ATTR_FLOOR:
			pass
		ATTR_SAND:
			_fx(host, FieldEffects.Kind.SAND, pos, yaw, attr, 0)
		ATTR_WAVE:
			_fx(host, FieldEffects.Kind.SIBUKI, pos, yaw, attr, 1)
		_:
			_fx(host, FieldEffects.Kind.DUST, pos, yaw, attr, 8)


## `eTurnAsimoto_init` — the dash skid (`arg1` 0 at the start).
static func turn(bg: Array, pos: Vector3, yaw: float, attr: int, arg1: int = 0) -> void:
	var host := _bind(bg)
	if host == null:
		return
	var winter: bool = Clock.season() == Clock.Season.WINTER
	var drop_set: int = 0x1000 if arg1 == 0 else 0x2000
	var p := pos
	if attr == ATTR_BUSH:
		_bush(host, pos, 4, 1, winter)
	elif attr == ATTR_SAND:
		_fx(host, FieldEffects.Kind.SAND, _ahead(pos, yaw, 5.0), yaw, 2, 0)
	elif attr == ATTR_WAVE or (winter and is_grass(attr)):
		p = _ahead(pos, yaw, 5.0) + Vector3(0.0, 5.0 * GX, 0.0)
		var k := FieldEffects.Kind.MIZUTAMA if attr == ATTR_WAVE else FieldEffects.Kind.YUKIDAMA
		for i: int in 5:
			_fx(host, k, p, yaw, attr, drop_set | i)
	elif attr != ATTR_FLOOR:
		if Weather.is_raining():
			p = _ahead(pos, yaw, 5.0) + Vector3(0.0, 5.0 * GX, 0.0)
			for i: int in 5:
				_fx(host, FieldEffects.Kind.MIZUTAMA, p, yaw, attr, drop_set | i)
		else:
			_fx(host, FieldEffects.Kind.TUMBLE_DUST, pos, yaw, attr, 5 if arg1 == 0 else 6)
			_fx(host, FieldEffects.Kind.DUST, pos, yaw, attr, 1 if arg1 == 0 else 2)
	## `eTurn_Hanabira_Make`: three petals 30 GX ahead when skidding over a flower.
	var flower: int = flower_index(pos)
	if flower >= 0:
		var petal_at := _ahead(pos, yaw, 30.0)
		for _i: int in 3:
			_fx(host, FieldEffects.Kind.PETAL, petal_at, 0.0, flower, 4)


## `eTumble_CallEffect` + `eTumble_Hanabira_Make` — `arg1` 0 at the trip, 1 on landing.
static func tumble(bg: Array, pos: Vector3, yaw: float, attr: int, arg1: int) -> void:
	var host := _bind(bg)
	if host == null:
		return
	var winter: bool = Clock.season() == Clock.Season.WINTER
	var rain: bool = Weather.is_raining()
	if is_grass(attr) or not attr in [ATTR_FLOOR, ATTR_BUSH, ATTR_SAND, ATTR_WAVE]:
		if is_grass(attr) and winter:
			if arg1 == 1:
				var p := _ahead(pos, yaw, 7.0) + Vector3(0.0, 5.0 * GX, 0.0)
				for i: int in range(9, -1, -1):
					_fx(host, FieldEffects.Kind.YUKIDAMA, p, yaw, attr, i)
			else:
				_fx(host, FieldEffects.Kind.YUKIHANE, pos, yaw, attr, arg1)
		elif arg1 == 1:
			if not rain:
				_tumble_dust_fan(host, pos, yaw, attr)
			else:
				var wp := pos + Vector3(0.0, 5.0 * GX, 0.0)
				for i: int in range(9, -1, -1):
					_fx(host, FieldEffects.Kind.MIZUTAMA, wp, yaw, attr, i)
	elif attr == ATTR_BUSH:
		_bush(host, _ahead(pos, yaw, 15.0), 3 if arg1 == 0 else 7, 1 if arg1 == 0 else 2, winter)
	elif attr == ATTR_SAND:
		if arg1 == 1:
			var sand_yaw: float = yaw - deg_to_rad(74.0)
			var base := pos + Vector3(0.0, 10.0 * GX, 0.0)
			for _i: int in 5:
				_fx(host, FieldEffects.Kind.SAND, _ahead(base, sand_yaw, 20.0), sand_yaw, 1, 0)
				sand_yaw += deg_to_rad(37.0)
	elif attr == ATTR_WAVE:
		var wave_p := pos + Vector3(0.0, 5.0 * GX, 0.0)
		for i: int in range(9, -1, -1):
			_fx(host, FieldEffects.Kind.MIZUTAMA, wave_p, yaw, attr, i)
	var flower: int = flower_index(pos)
	if flower >= 0:
		for _i: int in 3:
			_fx(host, FieldEffects.Kind.PETAL, pos, 0.0, flower, 1)


static func _tumble_dust_fan(host: Node, pos: Vector3, yaw: float, attr: int) -> void:
	var dust_yaw: float = yaw - deg_to_rad(74.0)
	var p := _ahead(pos, yaw, 15.0) + Vector3(0.0, 10.0 * GX, 0.0)
	for i: int in 5:
		_fx(host, FieldEffects.Kind.TUMBLE_DUST, p, dust_yaw, attr, i)
		dust_yaw += deg_to_rad(37.0)


## `eHanatiri_ct` — a flower trampled by a dash: 5 bloom petals + 4 leaf bits.
static func hanatiri(bg: Array, pos: Vector3, flower: int) -> void:
	var host := _bind(bg)
	if host == null:
		return
	if flower >= 0 and flower <= 8:
		for _i: int in 5:
			_fx(host, FieldEffects.Kind.PETAL, pos, 0.0, flower, 5)
	for _i: int in 4:
		_fx(host, FieldEffects.Kind.PETAL, pos, 0.0, 9, 5)


## `eTurnFootPrint` at the right foot when a skid settles.
static func turn_footprint(bg: Array, pos: Vector3, yaw: float, attr: int) -> void:
	var host := _bind(bg)
	if host == null:
		return
	FieldEffects.spawn(host, FieldEffects.Kind.TURN_PRINT, pos, yaw, attr, 0, _ground_sampler(), _slope(pos))


## `eTumbleBodyPrint` at tumble frame 17.
static func body_print(bg: Array, pos: Vector3, yaw: float, attr: int) -> void:
	var host := _bind(bg)
	if host == null:
		return
	var at := _ahead(pos, yaw, 7.0)
	FieldEffects.spawn(host, FieldEffects.Kind.BODY_PRINT, pos, yaw, attr, 0, _ground_sampler(), _slope(at))
