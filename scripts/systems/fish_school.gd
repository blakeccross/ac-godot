class_name FishSchool
extends RefCounted

## The field's live fish shadows. Behavioral analog of `GYOEI_ACTOR`, which holds
## `aGYO_MAX_GYOEI` controllers and tracks `aGYO_EXIST_MAX` slots. A `RefCounted` owned by
## the world scene alongside `WorldGrid`, not an autoload.
##
## Spawning is ours, not the original's: `ac_set_ovl_gyoei` streams shadows in per acre from
## the `gyoei_term` tables. We pick from `FishCatalog` (month and hour only) and place into
## whichever `WaterBodies.Body` is near the player, capped by that body's size ceiling so a
## garden pond does not produce an XL.

## `aGYO_MAX_GYOEI`: two shadows on screen at once, ever.
const MAX_SHADOWS := 2
## `aGYO_EXIST_MAX`: slots the original keeps tracked. Ours is the respawn budget.
const EXIST_MAX := 4
## Shadows only exist near the player; `aGYO_cull_check` drops them past 600 GX.
const CULL_DISTANCE := 600.0 * FishSize.GX
## Spawn just inside the cull radius so a shadow does not pop in under the player's nose.
const SPAWN_MIN := 3.0
const SPAWN_MAX := CULL_DISTANCE * 0.8
## Gap between spawn attempts, so an empty pond is not retried every frame.
const SPAWN_INTERVAL := 1.4
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
	## `wall_flag`: the puff already turned off one bank.
	var wall_turned: bool = false

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
var _spawn_timer: float = 0.0
var _tool_swing: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _steps := FrameStepper.new()

## How long a swung tool keeps scaring fish. Long enough to span the swing animation.
const TOOL_SWING_SECONDS := 0.2


func configure(grid: WorldGrid, water_surface_y: float = 0.0, layout: WorldData = null) -> void:
	_grid = grid
	_layout = layout
	bodies = WaterBodies.find(grid, layout)
	surface_y = water_surface_y
	shadows.clear()
	puffs.clear()
	_spawn_timer = 0.0


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
	_cull(sense)
	var kept: Array[FishShadow] = []
	for shadow: FishShadow in shadows:
		if shadow.puffed:
			_add_puff(shadow)
			shadow.puffed = false
		if not shadow.finished:
			kept.append(shadow)
	shadows = kept
	_tick_spawn(delta, sense)


## `aGYO_cull_check`: a shadow off screen, more than 600 GX from the player and in another
## acre is destroyed — no puff — which frees its slot for water near the player. One that
## has the bobber is left alone: it is on screen next to the player by construction.
func _cull(sense: FishShadow.Sense) -> void:
	if _grid == null or not sense.has_player():
		return
	var player_acre: Vector2i = BugHabitats.acre_of_world_pos(_grid, sense.player_position)
	for shadow: FishShadow in shadows:
		if shadow.finished or shadow.is_engaged():
			continue
		var dist: float = Vector2(
			shadow.position.x - sense.player_position.x, shadow.position.z - sense.player_position.z
		).length()
		if dist > CULL_DISTANCE and BugHabitats.acre_of_world_pos(_grid, shadow.position) != player_acre:
			shadow.finished = true


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
		if blocked and not puff.wall_turned:
			## `aGYO_KAGE_Wall_Check`: a quarter turn off the bank, once, and no slowing that tick.
			puff.wall_turned = true
			var left: float = puff.yaw + PI * 0.5
			var probe: Vector3 = puff.position + Vector3(sin(left), 0.0, cos(left)) * FishSize.GX * 4.0
			puff.yaw = wrapf(left if puff.body.contains(_grid.world_to_cell(probe)) else puff.yaw - PI * 0.5, -PI, PI)
			continue
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


func _tick_spawn(delta: float, sense: FishShadow.Sense) -> void:
	if not auto_spawn or bodies.is_empty() or shadows.size() >= MAX_SHADOWS or not sense.has_player():
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = SPAWN_INTERVAL
	var cell: Vector2i = _pick_cell(sense.player_position)
	if cell.x < 0:
		return
	var body: WaterBodies.Body = WaterBodies.body_at(bodies, cell)
	if body == null:
		return
	## `aSOG_gyoei_make_range_data` + `aSOG_gyoei_get_idx`.
	var weighted: Array = FishSpawnScheduler.build_pool(body.kind, Weather.is_raining())
	var fish: FishData = FishSpawnScheduler.decide(
		weighted, WaterBodies.size_ceiling(body), _rng
	)
	if fish == null:
		return
	spawn(fish, body, _grid.cell_to_world(cell))


## A water cell in the band around the player where a shadow is worth having.
func _pick_cell(player_position: Vector3) -> Vector2i:
	if _grid == null:
		return Vector2i(-1, -1)
	var candidates: Array[Vector2i] = []
	for body: WaterBodies.Body in bodies:
		for cell: Vector2i in body.cells:
			var world: Vector3 = _grid.cell_to_world(cell)
			var dist: float = Vector2(
				world.x - player_position.x, world.z - player_position.z
			).length()
			if dist >= SPAWN_MIN and dist <= SPAWN_MAX and not _occupied(cell):
				candidates.append(cell)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _occupied(cell: Vector2i) -> bool:
	if _grid == null:
		return false
	for shadow: FishShadow in shadows:
		if _grid.world_to_cell(shadow.position) == cell:
			return true
	return false
