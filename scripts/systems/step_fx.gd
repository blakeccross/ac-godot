class_name StepFx
extends RefCounted

## Effect routers the player fires on foot plants, skids and tumbles — the decomp's
## `eWalk_Asimoto_init`, `eDashAsimoto_ct`, `eTurnAsimoto_init`, `eTumble_CallEffect`,
## `eHanatiri_ct`, which pick `FieldFx` / `TreeFx` particles by the unit attribute,
## season and weather. Positions are world metres; offsets below are GX.

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
static var _world: Node


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


static func _bind(bg: Array) -> Node:
	_data = bg[0] as WorldData if bg.size() == 2 else null
	_grid = bg[1] as WorldGrid if bg.size() == 2 else null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	_world = tree.get_first_node_in_group("world") if tree != null else null
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


static func _fx(host: Node, k: FieldFx.Kind, pos: Vector3, yaw: float, a0: int, a1: int) -> void:
	FieldFx.spawn(host, k, pos, yaw, a0, a1, _ground_sampler())


static func _ahead(pos: Vector3, yaw: float, gx: float) -> Vector3:
	return pos + Vector3(sin(yaw), 0.0, cos(yaw)) * gx * GX


static func _bush(host: Node, pos: Vector3, count: int, arg1: int, snow: bool) -> void:
	for _i: int in count:
		TreeFx.bush_leaf(host, pos, arg1)
	if snow:
		for _i: int in count:
			TreeFx.bush_snow(host, pos)


## `eWalk_Asimoto_init` — walk and run foot plants: only bushes react.
static func walk_step(bg: Array, pos: Vector3, yaw: float, attr: int) -> void:
	var host := _bind(bg)
	if host == null or attr != ATTR_BUSH:
		return
	var at := _ahead(pos, yaw, 10.0)
	## `do { … } while (count-- != 0)` with count 1 → two leaves.
	var winter: bool = not Weather.is_raining() and Clock.season() == Clock.Season.WINTER
	_bush(host, at, 2, 0, winter)


## `eDashAsimoto_ct` — dash foot plants.
static func dash_step(bg: Array, pos: Vector3, yaw: float, attr: int) -> void:
	var host := _bind(bg)
	if host == null:
		return
	var flower: int = flower_index(pos)
	if flower >= 0:
		for _i: int in 2:
			_fx(host, FieldFx.Kind.PETAL, pos, 0.0, flower, 0)
	var bush_at := _ahead(pos, yaw, 10.0)
	if Weather.is_raining():
		match attr:
			ATTR_BUSH:
				_bush(host, bush_at, 3, 1, false)
			ATTR_FLOOR:
				pass
			ATTR_WAVE:
				_fx(host, FieldFx.Kind.SIBUKI, pos, yaw, attr, 1)
			_:
				_fx(host, FieldFx.Kind.SIBUKI, pos, yaw, attr, 0)
		return
	var winter: bool = Clock.season() == Clock.Season.WINTER
	if winter and is_grass(attr):
		_fx(host, FieldFx.Kind.YUKIHANE, pos, yaw, attr, 0)
		return
	match attr:
		ATTR_BUSH:
			_bush(host, bush_at, 3, 1, winter)
		ATTR_FLOOR:
			pass
		ATTR_SAND:
			_fx(host, FieldFx.Kind.SAND, pos, yaw, attr, 0)
		ATTR_WAVE:
			_fx(host, FieldFx.Kind.SIBUKI, pos, yaw, attr, 1)
		_:
			_fx(host, FieldFx.Kind.DUST, pos, yaw, attr, 8)


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
		_fx(host, FieldFx.Kind.SAND, _ahead(pos, yaw, 5.0), yaw, 2, 0)
	elif attr == ATTR_WAVE or (winter and is_grass(attr)):
		p = _ahead(pos, yaw, 5.0) + Vector3(0.0, 5.0 * GX, 0.0)
		var k := FieldFx.Kind.MIZUTAMA if attr == ATTR_WAVE else FieldFx.Kind.YUKIDAMA
		for i: int in 5:
			_fx(host, k, p, yaw, attr, drop_set | i)
	elif attr != ATTR_FLOOR:
		if Weather.is_raining():
			p = _ahead(pos, yaw, 5.0) + Vector3(0.0, 5.0 * GX, 0.0)
			for i: int in 5:
				_fx(host, FieldFx.Kind.MIZUTAMA, p, yaw, attr, drop_set | i)
		else:
			_fx(host, FieldFx.Kind.TUMBLE_DUST, pos, yaw, attr, 5 if arg1 == 0 else 6)
			_fx(host, FieldFx.Kind.DUST, pos, yaw, attr, 1 if arg1 == 0 else 2)
	## `eTurn_Hanabira_Make`: three petals 30 GX ahead when skidding over a flower.
	var flower: int = flower_index(pos)
	if flower >= 0:
		var petal_at := _ahead(pos, yaw, 30.0)
		for _i: int in 3:
			_fx(host, FieldFx.Kind.PETAL, petal_at, 0.0, flower, 4)


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
					_fx(host, FieldFx.Kind.YUKIDAMA, p, yaw, attr, i)
			else:
				_fx(host, FieldFx.Kind.YUKIHANE, pos, yaw, attr, arg1)
		elif arg1 == 1:
			if not rain:
				_tumble_dust_fan(host, pos, yaw, attr)
			else:
				var wp := pos + Vector3(0.0, 5.0 * GX, 0.0)
				for i: int in range(9, -1, -1):
					_fx(host, FieldFx.Kind.MIZUTAMA, wp, yaw, attr, i)
	elif attr == ATTR_BUSH:
		_bush(host, _ahead(pos, yaw, 15.0), 3 if arg1 == 0 else 7, 1 if arg1 == 0 else 2, winter)
	elif attr == ATTR_SAND:
		if arg1 == 1:
			var sand_yaw: float = yaw - deg_to_rad(74.0)
			var base := pos + Vector3(0.0, 10.0 * GX, 0.0)
			for _i: int in 5:
				_fx(host, FieldFx.Kind.SAND, _ahead(base, sand_yaw, 20.0), sand_yaw, 1, 0)
				sand_yaw += deg_to_rad(37.0)
	elif attr == ATTR_WAVE:
		var wave_p := pos + Vector3(0.0, 5.0 * GX, 0.0)
		for i: int in range(9, -1, -1):
			_fx(host, FieldFx.Kind.MIZUTAMA, wave_p, yaw, attr, i)
	var flower: int = flower_index(pos)
	if flower >= 0:
		for _i: int in 3:
			_fx(host, FieldFx.Kind.PETAL, pos, 0.0, flower, 1)


static func _tumble_dust_fan(host: Node, pos: Vector3, yaw: float, attr: int) -> void:
	var dust_yaw: float = yaw - deg_to_rad(74.0)
	var p := _ahead(pos, yaw, 15.0) + Vector3(0.0, 10.0 * GX, 0.0)
	for i: int in 5:
		_fx(host, FieldFx.Kind.TUMBLE_DUST, p, dust_yaw, attr, i)
		dust_yaw += deg_to_rad(37.0)


## `eHanatiri_ct` — a flower trampled by a dash: 5 bloom petals + 4 leaf bits.
static func hanatiri(bg: Array, pos: Vector3, flower: int) -> void:
	var host := _bind(bg)
	if host == null:
		return
	if flower >= 0 and flower <= 8:
		for _i: int in 5:
			_fx(host, FieldFx.Kind.PETAL, pos, 0.0, flower, 5)
	for _i: int in 4:
		_fx(host, FieldFx.Kind.PETAL, pos, 0.0, 9, 5)


## `eTurnFootPrint` at the right foot when a skid settles.
static func turn_footprint(bg: Array, pos: Vector3, yaw: float, attr: int) -> void:
	var host := _bind(bg)
	if host == null:
		return
	FieldFx.spawn(host, FieldFx.Kind.TURN_PRINT, pos, yaw, attr, 0, _ground_sampler(), _slope(pos))


## `eTumbleBodyPrint` at tumble frame 17.
static func body_print(bg: Array, pos: Vector3, yaw: float, attr: int) -> void:
	var host := _bind(bg)
	if host == null:
		return
	var at := _ahead(pos, yaw, 7.0)
	FieldFx.spawn(host, FieldFx.Kind.BODY_PRINT, pos, yaw, attr, 0, _ground_sampler(), _slope(at))
