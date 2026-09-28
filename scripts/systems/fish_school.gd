class_name FishSchool
extends RefCounted

## The field's live fish shadows. Behavioral analog of `GYOEI_ACTOR`, which holds
## `aGYO_MAX_GYOEI` controllers and tracks `aGYO_EXIST_MAX` slots. A `RefCounted` owned by
## the world scene alongside `WorldGrid`, not an autoload.
##
## Spawning follows `aSOG_gyoei_set`: one attempt each time the player enters an acre,
## skipped if that acre already has a live shadow. `FishSpawnScheduler` picks the species
## from the acre's block kind, half-month term and hour, and a unit inside the acre for it.
## Shadows are dropped once they are more than 600 GX away in another acre
## (`aGYO_cull_check`), which is what lets an acre restock when the player comes back.

## `aGYO_MAX_GYOEI`: two shadows on screen at once, ever.
const MAX_SHADOWS := 2
## `aGYO_EXIST_MAX`: slots the original keeps tracked.
const EXIST_MAX := 4
## `aGYO_cull_check` drops a shadow past 600 GX once it is in another acre.
const CULL_DISTANCE := 600.0 * FishSize.GX
## `mCoBG_ATTRIBUTE_WATER`, `_RIVER_NE` and `_SEA`: the water unit attributes.
const ATTR_WATER := 12
const ATTR_RIVER_NE := 21
const ATTR_SEA := 24


class Puff:
	## `GYO_KAGE_ACTOR`: the fading shadow a scared fish leaves behind. `aGTT_kage_make_actor`
	## spawns it with a zero rotation, so it always darts off along +Z at 2.0 GX a frame
	## whichever way the fish was facing, easing off by 0.02 a tick.
	var position: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var size: FishData.SizeClass = FishData.SizeClass.S
	var age: float = 0.0
	## GX per 30 fps frame, like `FishShadow.speed`.
	var speed: float = 0.0
	var body: WaterBodies.Body = null

	func alpha() -> float:
		return FishSize.puff_alpha(age)

	func done() -> bool:
		return age >= FishSize.puff_seconds()


var shadows: Array[FishShadow] = []
var puffs: Array[Puff] = []
var bodies: Array[WaterBodies.Body] = []
var surface_y: float = 0.0
## Tests drive a chosen fish through `spawn`; gameplay leaves the school stocking itself.
var auto_spawn: bool = true

var _grid: WorldGrid = null
var _layout: WorldData = null
var _spawned_acre: Vector2i = NO_ACRE
var _tool_swing: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _steps := FrameStepper.new()

## How long a swung tool keeps scaring fish. Long enough to span the swing animation.
const TOOL_SWING_SECONDS := 0.2
const NO_ACRE := Vector2i(-999, -999)


func configure(grid: WorldGrid, water_surface_y: float = 0.0, layout: WorldData = null) -> void:
	_grid = grid
	_layout = layout
	bodies = WaterBodies.find(grid, layout)
	surface_y = water_surface_y
	shadows.clear()
	puffs.clear()
	_spawned_acre = NO_ACRE


## Catalog water is a heightfield (`mCoBG_GetWaterHeight`). Fallback is the flat placeholder
## plane used by authored test towns without unit tables.
func surface_at(pos: Vector3) -> float:
	if _layout != null and _grid != null:
		var cell: Vector2i = _grid.world_to_cell(pos)
		var y: float = FieldCollision.height_at(_layout, cell, false)
		if FieldCollision.has_floor(y):
			return y
	return surface_y


func seed_rng(value: int) -> void:
	_rng.seed = value


func has_water() -> bool:
	return not bodies.is_empty()


func shadow_count() -> int:
	return shadows.size()


## The shadow that currently has the bobber, if any.
func hooked_shadow() -> FishShadow:
	for shadow: FishShadow in shadows:
		if shadow.is_hooked():
			return shadow
	return null


## The player swung an axe, net or shovel. Fish inside `SCARE_TOOL_GX` bolt.
func notify_tool_swing() -> void:
	_tool_swing = TOOL_SWING_SECONDS


## Advance every shadow and puff by whole mover ticks. Each tick runs the shadows in turn
## the way `aGYO_actor_move` walks its controllers, so `bite_check` sees any shadow that
## engaged the bobber earlier in the same tick.
func tick(delta: float, sense: FishShadow.Sense) -> void:
	if _tool_swing > 0.0:
		sense.player_swung_tool = true
	_tool_swing = maxf(_tool_swing - delta, 0.0)
	for shadow: FishShadow in shadows:
		shadow.nibbled = false
		shadow.bit = false
	var splashed: bool = sense.bobber_splashed
	_steps.add(delta)
	while _steps.next():
		for shadow: FishShadow in shadows:
			if shadow.finished:
				continue
			sense.bobber_taken = _bobber_taken()
			var nibbled: bool = shadow.nibbled
			var bit: bool = shadow.bit
			shadow.step(sense)
			## A batch of ticks must not lose a one-tick event to the tick after it.
			shadow.nibbled = shadow.nibbled or nibbled
			shadow.bit = shadow.bit or bit
		## `hit_water_flag` is cleared by the bobber's next tick.
		sense.bobber_splashed = false
		_tick_puffs()
	sense.bobber_splashed = splashed
	var kept: Array[FishShadow] = []
	for shadow: FishShadow in shadows:
		if shadow.puffed:
			_add_puff(shadow)
			shadow.puffed = false
		if not shadow.finished:
			kept.append(shadow)
	shadows = kept
	_cull_distant(sense)
	_tick_spawn(sense)


## `bite_check`: any shadow closing on or holding the bobber claims it for all of them.
func _bobber_taken() -> bool:
	for shadow: FishShadow in shadows:
		if not shadow.finished and shadow.is_engaged():
			return true
	return false


## `mCoBG_GetWaterFlow` at a point, as a planar (x, z) vector. Unit attributes when the
## field has them; otherwise the body's own axis, and still water for a pond.
func water_flow(pos: Vector3) -> Vector2:
	if _layout != null and _grid != null:
		var attr: int = FieldCollision.unit_attr_at(_layout, _grid, pos)
		if attr >= 0:
			return flow_for_attr(attr)
	if _grid != null:
		var body: WaterBodies.Body = WaterBodies.body_at(bodies, _grid.world_to_cell(pos))
		if body != null and body.flows:
			return Vector2(sin(body.flow_yaw), cos(body.flow_yaw)) * 0.5
	return Vector2.ZERO


## `mCoBG_GetWaterFlow`'s `flow_data[]`, indexed from `mCoBG_ATTRIBUTE_WATER` (12). The
## sea has its own fixed flow; anything that is not water has none.
static func flow_for_attr(attr: int) -> Vector2:
	if attr == ATTR_SEA:
		return Vector2(0.0, -1.0)
	if attr < ATTR_WATER or attr > ATTR_RIVER_NE:
		return Vector2.ZERO
	var d: float = 0.35355338
	var table: Array[Vector2] = [
		Vector2(0.0, 0.0),  ## still water
		Vector2(0.0, 0.0),  ## waterfall: straight down, nothing across
		Vector2(0.0, -0.5), Vector2(-d, -d), Vector2(-0.5, 0.0), Vector2(-d, d),
		Vector2(0.0, 0.5), Vector2(d, d), Vector2(0.5, 0.0), Vector2(d, -d),
	]
	return table[attr - ATTR_WATER]


## Whether a point is on water, for the bobber's drift. True when there is no grid to ask.
func is_water(pos: Vector3) -> bool:
	if _grid == null:
		return true
	return _grid.terrain_at(_grid.world_to_cell(pos)) == WorldGrid.Terrain.WATER


## Spawn one shadow immediately. Returns it so tests can drive a known fish.
func spawn(fish: FishData, body: WaterBodies.Body, at: Vector3) -> FishShadow:
	if fish == null or shadows.size() >= MAX_SHADOWS:
		return null
	var shadow: FishShadow = FishShadow.create(fish, body, at, _rng)
	shadow.position.y = surface_at(at) - FishSize.depth()
	if _grid != null:
		shadow.cell_lookup = _grid.world_to_cell
		shadow.flow_lookup = water_flow
		## `aGTT_actor_init` read the flow before we could hand it the lookup.
		shadow._set_angle(shadow._upstream_yaw())
	shadows.append(shadow)
	return shadow


func clear() -> void:
	shadows.clear()
	puffs.clear()
	_spawned_acre = NO_ACRE


## One tick of every `GYO_KAGE` puff: `Actor_position_moveF`, the one wall turn, and
## `chase_f(&speed, 0.0f, 0.02f)` while `delete_timer` runs down.
func _tick_puffs() -> void:
	var kept: Array[Puff] = []
	for puff: Puff in puffs:
		puff.age += DecompTime.TICK_SEC
		var step_gx: float = puff.speed * FishShadow.MOVE_PER_TICK
		var next: Vector3 = puff.position + Vector3(sin(puff.yaw), 0.0, cos(puff.yaw)) * step_gx * FishSize.GX
		var blocked: bool = puff.body != null and _grid != null and not puff.body.contains(_grid.world_to_cell(next))
		if not blocked:
			puff.position = next
		if puff.done():
			continue
		kept.append(puff)
		if blocked:
			## `aGYO_KAGE_Wall_Check`: a quarter turn off the bank on every tick it runs into
			## one, toward the side that is still water. The `wall_flag == FALSE` guard after
			## it can never pass (the check has just set the flag), so it slows regardless.
			var left: float = puff.yaw + PI * 0.5
			var probe: Vector3 = puff.position + Vector3(sin(left), 0.0, cos(left)) * FishSize.GX * 4.0
			puff.yaw = wrapf(left if puff.body.contains(_grid.world_to_cell(probe)) else puff.yaw - PI * 0.5, -PI, PI)
		puff.speed = move_toward(puff.speed, 0.0, FishSize.ESCAPE_DECAY_GX)
	puffs = kept


func _add_puff(shadow: FishShadow) -> void:
	var puff := Puff.new()
	puff.position = shadow.position
	puff.yaw = 0.0
	puff.size = shadow.size
	puff.speed = FishSize.ESCAPE_SPEED_GX
	puff.body = shadow.body
	puffs.append(puff)


## `aSetMgr` runs `aSOG_gyoei_set` on each acre transition, not on a timer. Like
## `BugField`, the acre the player starts in counts as entered.
func _tick_spawn(sense: FishShadow.Sense) -> void:
	if not auto_spawn or _grid == null or bodies.is_empty() or not sense.has_player():
		return
	var acre: Vector2i = acre_of(sense.player_position)
	if acre == _spawned_acre:
		return
	_spawned_acre = acre
	try_spawn_in_acre(acre)


## `aSOG_gyoei_set` for one acre. Returns the new shadow, or null.
func try_spawn_in_acre(acre: Vector2i, tourney: int = -1) -> FishShadow:
	if _grid == null:
		return null
	## `aSOG_gyoei_block_check` / `aGYO_chk_live_gyoei`.
	if acre_has_fish(acre):
		return null
	var units: Array = acre_units(acre)
	var kind: int = block_kind(acre, units)
	if (
		(kind & FishSpawnScheduler.KIND_MARINE) == 0
		and (kind & FishSpawnScheduler.KIND_RIVER) == 0
		and not _has_fresh_water(units)
	):
		return null
	var pick: Dictionary = FishSpawnScheduler.decide(kind, units, Weather.is_raining(), _rng, tourney)
	if pick.is_empty():
		return null
	var unit: Vector2i = pick["unit"]
	var cell: Vector2i = _acre_origin(acre) + unit
	var type_index: int = int(pick["type_index"])
	var south_attr: int = int(_unit_row(units, unit + Vector2i(0, 1)).get("a", -1))
	var offset: Vector2 = FishSpawnScheduler.spawn_offset(
		type_index, FishSpawnScheduler.is_water_attr(south_attr)
	)
	var at: Vector3 = _grid.cell_corner(cell) + Vector3(offset.x, 0.0, offset.y) * _grid.cell_size
	var body: WaterBodies.Body = WaterBodies.body_at(bodies, _grid.world_to_cell(at))
	if body == null:
		body = WaterBodies.body_at(bodies, cell)
	if body == null:
		return null
	## `aGYO_make_gyoei`: no free controller, no fish.
	return spawn(pick["fish"], body, at)


## The block an actor stands in (`mFI_Wpos2BlockNum`).
func acre_of(world: Vector3) -> Vector2i:
	if _grid == null:
		return NO_ACRE
	return VillagerWalk.block_from_cell(_grid.world_to_cell(world))


func acre_has_fish(acre: Vector2i) -> bool:
	for shadow: FishShadow in shadows:
		if not shadow.finished and acre_of(shadow.position) == acre:
			return true
	return false


## `mFI_BkNum2BlockKind`, or a stand-in from the water in the acre when the layout carries
## no block types.
func block_kind(acre: Vector2i, units: Array = []) -> int:
	if _layout != null and _layout.acre_types.size() == TownFieldGenerator.BLOCK_TOTAL:
		if acre.x < 0 or acre.x >= TownFieldGenerator.BLOCK_X or acre.y < 0 or acre.y >= TownFieldGenerator.BLOCK_Z:
			return 0
		return FishSpawnScheduler.block_kind_for_type(
			int(_layout.acre_types[acre.y * TownFieldGenerator.BLOCK_X + acre.x])
		)
	var rows: Array = units if not units.is_empty() else acre_units(acre)
	var kind: int = 0
	var origin: Vector2i = _acre_origin(acre)
	for uz: int in FishSpawnScheduler.UT:
		for ux: int in FishSpawnScheduler.UT:
			var body: WaterBodies.Body = WaterBodies.body_at(bodies, origin + Vector2i(ux, uz))
			if body != null:
				kind |= FishSpawnScheduler.block_kind_for_water(body.kind)
	if (kind & FishSpawnScheduler.KIND_MARINE) != 0:
		return FishSpawnScheduler.KIND_MARINE
	return kind


## The acre's 16×16 unit rows, `{"a": attr, "y": centre height in GX}`. From the unit
## catalog when the layout has one; otherwise water cells stand in as `WATER` (river / pond)
## or deep `SEA` (ocean bodies).
func acre_units(acre: Vector2i) -> Array:
	var rows: Array = []
	var origin: Vector2i = _acre_origin(acre)
	for uz: int in FishSpawnScheduler.UT:
		for ux: int in FishSpawnScheduler.UT:
			rows.append(_unit_at(origin + Vector2i(ux, uz)))
	return rows


func _unit_at(cell: Vector2i) -> Dictionary:
	if _layout != null:
		var attr: int = FieldCollision.unit_attr_at_cell(_layout, cell)
		if attr >= 0:
			## Back to the original's frame, where land (`LAND_COUNTS`) sits at 40 GX and the
			## sea surface at 20 GX, so a sea unit is deep enough only at count 0.
			var y: float = FieldCollision.height_at(_layout, cell, false)
			var gx: float = 0.0
			if FieldCollision.has_floor(y):
				gx = y / FishSize.GX + float(FieldCatalog.LAND_COUNTS) * 10.0
			return {"a": attr, "y": gx}
	if _grid == null or not _grid.is_in_bounds(cell) or _grid.terrain_at(cell) != WorldGrid.Terrain.WATER:
		return {"a": 0, "y": 0.0}
	var body: WaterBodies.Body = WaterBodies.body_at(bodies, cell)
	if body != null and body.kind == WaterBodies.Kind.OCEAN:
		return {"a": FishSpawnScheduler.ATTR_SEA, "y": 0.0}
	return {"a": FishSpawnScheduler.ATTR_WATER, "y": 0.0}


func _unit_row(units: Array, unit: Vector2i) -> Dictionary:
	if unit.x < 0 or unit.y < 0 or unit.x >= FishSpawnScheduler.UT or unit.y >= FishSpawnScheduler.UT:
		return {}
	return units[unit.y * FishSpawnScheduler.UT + unit.x]


func _acre_origin(acre: Vector2i) -> Vector2i:
	return Vector2i((acre.x - 1) * WorldGenerator.UT, (acre.y - 1) * WorldGenerator.UT)


## `aSOG_gyoei_check_water_unit_in_block`: river / pond water, not sea.
func _has_fresh_water(units: Array) -> bool:
	for row: Dictionary in units:
		if FishSpawnScheduler.is_fresh_water_attr(int(row.get("a", -1))):
			return true
	return false


## `aGYO_cull_check`: gone once more than 600 GX from the player and in another acre.
func _cull_distant(sense: FishShadow.Sense) -> void:
	if _grid == null or not sense.has_player():
		return
	var player_acre: Vector2i = acre_of(sense.player_position)
	var kept: Array[FishShadow] = []
	for shadow: FishShadow in shadows:
		var dist: float = Vector2(
			shadow.position.x - sense.player_position.x, shadow.position.z - sense.player_position.z
		).length()
		if not shadow.is_hooked() and dist > CULL_DISTANCE and acre_of(shadow.position) != player_acre:
			continue
		kept.append(shadow)
	shadows = kept
