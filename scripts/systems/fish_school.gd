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


class Puff:
	## `GYO_KAGE_ACTOR`: the fading shadow a scared fish leaves behind.
	var position: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var size: FishData.SizeClass = FishData.SizeClass.S
	var age: float = 0.0
	var speed: float = 0.0

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
var _spawn_timer: float = 0.0
var _tool_swing: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## How long a swung tool keeps scaring fish. Long enough to span the swing animation.
const TOOL_SWING_SECONDS := 0.2


func configure(grid: WorldGrid, water_surface_y: float = 0.0) -> void:
	_grid = grid
	bodies = WaterBodies.find(grid)
	surface_y = water_surface_y
	shadows.clear()
	puffs.clear()
	_spawn_timer = 0.0


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


func tick(delta: float, sense: FishShadow.Sense) -> void:
	if _tool_swing > 0.0:
		sense.player_swung_tool = true
	_tool_swing = maxf(_tool_swing - delta, 0.0)
	for shadow: FishShadow in shadows:
		shadow.tick(delta, sense)
	var kept: Array[FishShadow] = []
	for shadow: FishShadow in shadows:
		if shadow.puffed:
			_add_puff(shadow)
			shadow.puffed = false
		if not shadow.finished:
			kept.append(shadow)
	shadows = kept
	_tick_puffs(delta)
	_tick_spawn(delta, sense)


## Spawn one shadow immediately. Returns it so tests can drive a known fish.
func spawn(fish: FishData, body: WaterBodies.Body, at: Vector3) -> FishShadow:
	if fish == null or shadows.size() >= MAX_SHADOWS:
		return null
	var shadow: FishShadow = FishShadow.create(fish, body, at, _rng)
	shadow.position.y = surface_y - FishSize.depth()
	if _grid != null:
		shadow.cell_lookup = _grid.world_to_cell
	shadows.append(shadow)
	return shadow


func clear() -> void:
	shadows.clear()
	puffs.clear()


func _tick_puffs(delta: float) -> void:
	var kept: Array[Puff] = []
	for puff: Puff in puffs:
		puff.age += delta
		## `chase_f(&speed, 0.0f, 0.02f)`: the puff coasts to a stop as it fades.
		puff.speed = move_toward(
			puff.speed, 0.0, FishSize.gx_per_frame_to_mps(FishSize.ESCAPE_DECAY_GX) * FishSize.GAME_FPS * delta
		)
		puff.position += Vector3(sin(puff.yaw), 0.0, cos(puff.yaw)) * puff.speed * delta
		if not puff.done():
			kept.append(puff)
	puffs = kept


func _add_puff(shadow: FishShadow) -> void:
	var puff := Puff.new()
	puff.position = shadow.position
	puff.yaw = shadow.yaw
	puff.size = shadow.size
	puff.speed = FishSize.escape_speed()
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
	var pool: Array[FishData] = FishCatalog.available_now(body.kind)
	if pool.is_empty():
		return
	var allowed: Array[FishData] = _fits(pool, WaterBodies.size_ceiling(body))
	if allowed.is_empty():
		return
	spawn(FishCatalog.roll(allowed), body, _grid.cell_to_world(cell))


## A water cell in the band around the player where a shadow is worth having.
func _pick_cell(player_position: Vector3) -> Vector2i:
	if _grid == null:
		return Vector2i(-1, -1)
	var candidates: Array[Vector2i] = []
	for body: WaterBodies.Body in bodies:
		for cell: Vector2i in body.cells:
			var dist: float = _grid.cell_to_world(cell).distance_to(player_position)
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


static func _fits(pool: Array[FishData], ceiling: FishData.SizeClass) -> Array[FishData]:
	var out: Array[FishData] = []
	for fish: FishData in pool:
		if int(fish.size_class) <= int(ceiling):
			out.append(fish)
	return out
