class_name VillagerWalk
extends RefCounted

## Field roam goals from looks + time (`mNpcW` kinds), not waypoint graphs.
## Concurrent off-home walkers match `mNpcW_GET_WALK_NUM` (max `mNpcW_MAX`).
## In-acre wait/walk/run follows `aNPC_think_wander_decide_next`.

const GOAL_SHRINE := &"shrine"
const GOAL_HOME := &"home"
const GOAL_ALONE := &"alone"
const GOAL_MY_HOME := &"my_home"

const ACT_WAIT := &"wait"
const ACT_WALK := &"walk"
const ACT_RUN := &"run"

## `mNpcW_MAX` = `ANIMAL_NUM_MAX / 3`.
const MAX_WALKERS := 5
## Default alone acre D-3 (`mNpcW_GetAloneBlock`).
const ALONE_DEFAULT := Vector2i(3, 4)
## Out-of-range fallback C-4.
const FALLBACK_BLOCK := Vector2i(4, 3)
const FG_X0 := 1
const FG_X1 := 5
const FG_Z0 := 1
const FG_Z1 := 6
## `movement.range_radius` 280 GX → meters (40 GX = 2 m).
const RANGE_RADIUS := 14.0
## Skip wander picks that land on the current cell.
const MIN_STEP := 1.6
## `aNPC_check_arrive_destination` compares dist² to 72 GX → √72 GX ≈ 0.42 m.
const WANDER_ARRIVE := 0.45
## `aNPC_think_wander_move_next` retries a rim dest this many times.
const WANDER_TRIES := 5
## `aNPC_avoid_wall` looks 2 units ahead (`2 * mFI_UT_WORLDSIZE`).
const AVOID_METERS := 4.0
## One wait clip, then `decide_next` again.
const WAIT_SECONDS := 2.0
const _BLOCK_STAND: Array[StringName] = [&"tree", &"rock", &"house", &"shop", &"building"]

static var _walkers: Dictionary = {}
## Cells that block standing (houses, trees, rocks). Rebuilt when layout changes.
static var _blocked_data_id: int = 0
static var _blocked_sig: int = 0
static var _blocked_cells: Dictionary = {}


static func reset() -> void:
	_walkers.clear()
	_clear_blocked_cache()


static func _clear_blocked_cache() -> void:
	_blocked_data_id = 0
	_blocked_sig = 0
	_blocked_cells.clear()


static func walker_cap(field_count: int) -> int:
	## `mNpcW_GET_WALK_NUM` is `n / 3`. Keep at least one so a lone test villager still roams.
	if field_count <= 0:
		return 0
	return clampi(maxi(1, field_count / 3), 1, MAX_WALKERS)


static func claim(villager_id: StringName, want_town: bool, field_count: int) -> bool:
	if villager_id == &"":
		return false
	if not want_town:
		_walkers.erase(villager_id)
		return false
	if _walkers.has(villager_id):
		return true
	if _walkers.size() >= walker_cap(field_count):
		return false
	_walkers[villager_id] = true
	return true


static func release(villager_id: StringName) -> void:
	_walkers.erase(villager_id)


static func is_claimed(villager_id: StringName) -> bool:
	return _walkers.has(villager_id)


static func can_town_walk(looks: VillagerPersonality.Looks, now_sec: int) -> bool:
	return not goal_kinds(looks, now_sec).is_empty()


static func goal_kinds(looks: VillagerPersonality.Looks, now_sec: int) -> Array[StringName]:
	var sec: int = posmod(now_sec, 86400)
	var table: Array = _table_for(looks)
	for slot: Variant in table:
		var row: Dictionary = slot
		if int(row.get("end", 86400)) > sec:
			return _kinds_from(row.get("kinds", []))
	if table.is_empty():
		return []
	return _kinds_from((table[table.size() - 1] as Dictionary).get("kinds", []))


static func pick_kind(
	looks: VillagerPersonality.Looks, now_sec: int, rng: RandomNumberGenerator = null
) -> StringName:
	var kinds: Array[StringName] = goal_kinds(looks, now_sec)
	if kinds.is_empty():
		return GOAL_MY_HOME
	var idx: int = _rand_i(rng, kinds.size())
	return kinds[idx]


static func block_from_cell(cell: Vector2i) -> Vector2i:
	var bx: int = int(cell.x / WorldGenerator.UT) + 1
	var bz: int = int(cell.y / WorldGenerator.UT) + 1
	return Vector2i(bx, bz)


static func is_fg_block(block: Vector2i) -> bool:
	return block.x >= FG_X0 and block.x <= FG_X1 and block.y >= FG_Z0 and block.y <= FG_Z1


static func has_town_acres(data: WorldData) -> bool:
	return data != null and data.acre_types.size() == TownFieldGenerator.BLOCK_TOTAL


static func shrine_block(data: WorldData) -> Vector2i:
	if data == null:
		return FALLBACK_BLOCK
	for b: BuildingPlacement in data.buildings:
		if b != null and b.id == &"wishing_well":
			var block: Vector2i = block_from_cell(b.cell)
			if is_fg_block(block):
				return block
	return FALLBACK_BLOCK


static func house_blocks(data: WorldData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if data == null:
		return out
	for b: BuildingPlacement in data.buildings:
		if b == null or not String(b.id).begins_with("npc_house_"):
			continue
		var block: Vector2i = block_from_cell(b.cell)
		if is_fg_block(block) and not out.has(block):
			out.append(block)
	return out


static func resolve_block(
	kind: StringName,
	home_block: Vector2i,
	shrine: Vector2i,
	homes: Array[Vector2i],
	occupied: Array[Vector2i],
	rng: RandomNumberGenerator = null
) -> Vector2i:
	var block: Vector2i = FALLBACK_BLOCK
	match kind:
		GOAL_SHRINE:
			block = shrine if is_fg_block(shrine) else FALLBACK_BLOCK
		GOAL_HOME:
			block = _other_home(home_block, homes, rng)
		GOAL_ALONE:
			block = _alone_block(occupied, rng)
		GOAL_MY_HOME:
			block = home_block if is_fg_block(home_block) else FALLBACK_BLOCK
		_:
			block = FALLBACK_BLOCK
	if not is_fg_block(block):
		return FALLBACK_BLOCK
	return block


static func stand_in_block(
	data: WorldData,
	block: Vector2i,
	rng: RandomNumberGenerator = null
) -> Vector3:
	if data == null:
		return Vector3.ZERO
	var cells: Array[Vector2i] = _walkable_cells(data, block)
	if cells.is_empty():
		return block_center(data, block)
	var cell: Vector2i = cells[_rand_i(rng, cells.size())]
	return data.cell_to_world(cell)


static func block_center(data: WorldData, block: Vector2i) -> Vector3:
	if data == null:
		return Vector3.ZERO
	if has_town_acres(data) and is_fg_block(block):
		return data.cell_to_world(_origin_cell(data, block) + Vector2i(8, 8))
	return data.cell_to_world(Vector2i(data.columns / 2, data.rows / 2))


static func is_in_block(data: WorldData, block: Vector2i, world_pos: Vector3) -> bool:
	if data == null:
		return true
	var cell := Vector2i(
		int(floor((world_pos.x - data.origin().x) / data.cell_size)),
		int(floor((world_pos.z - data.origin().z) / data.cell_size))
	)
	return block_from_cell(cell) == block


static func is_standable(data: WorldData, cell: Vector2i) -> bool:
	if data == null or not data.is_in_bounds(cell):
		return false
	if not _walkable_terrain(data.terrain_at(cell)):
		return false
	return not _is_blocked_cell(data, cell)


static func wander_in_block(
	data: WorldData,
	block: Vector2i,
	from: Vector3,
	rng: RandomNumberGenerator = null,
	grid: WorldGrid = null
) -> Vector3:
	## Rim dest around the acre center (`center + sin/cos * range_radius`).
	## Keep the world point — do not snap to a cell center. Decomp stores the
	## float dest and only checks the unit under it (EMPTY/ITEM1/FTR + CheckNpc).
	## With a grid, skip rim points across a cliff/water wall so they do not charge it.
	if data == null:
		return from
	var center: Vector3 = block_center(data, block)
	for _try: int in WANDER_TRIES:
		var angle: float = _rand_f(rng) * TAU
		var stand := Vector3(
			center.x + sin(angle) * RANGE_RADIUS,
			center.y,
			center.z + cos(angle) * RANGE_RADIUS
		)
		if not _dest_ok(data, block, from, stand, grid):
			continue
		return stand
	var far: Array[Vector3] = []
	for cell: Vector2i in _walkable_cells(data, block):
		var stand: Vector3 = data.cell_to_world(cell)
		if not _dest_ok(data, block, from, stand, grid):
			continue
		far.append(stand)
	if not far.is_empty():
		return far[_rand_i(rng, far.size())]
	return stand_in_block(data, block, rng)


static func snap_standable(data: WorldData, world_pos: Vector3) -> Vector3:
	if data == null:
		return world_pos
	return _snap_walkable(data, world_pos)


static func avoid_around(
	data: WorldData,
	from: Vector3,
	facing: float,
	block: Vector2i,
	grid: WorldGrid = null
) -> Vector3:
	## `aNPC_avoid_wall`: try 2 units at 22.5° / 45° / 90°, then 180°.
	var offsets: Array[float] = [
		deg_to_rad(22.5),
		deg_to_rad(-22.5),
		deg_to_rad(45.0),
		deg_to_rad(-45.0),
		deg_to_rad(90.0),
		deg_to_rad(-90.0),
		PI,
	]
	for offset: float in offsets:
		var yaw: float = facing + offset
		var stand := Vector3(
			from.x + sin(yaw) * AVOID_METERS,
			from.y,
			from.z + cos(yaw) * AVOID_METERS
		)
		if not _dest_ok(data, block, from, stand, grid):
			continue
		if not can_step(data, from, stand, grid):
			continue
		return stand
	return from


static func can_step(
	data: WorldData, from: Vector3, dest: Vector3, grid: WorldGrid = null
) -> bool:
	if data == null:
		return true
	if not is_standable(data, _world_to_cell(data, dest)):
		return false
	return _motion_ok(data, from, dest, grid)


static func path_clear(
	data: WorldData, from: Vector3, dest: Vector3, grid: WorldGrid, max_steps: int = 24
) -> bool:
	## Greedy cell walk; false when a cliff/water wall or house blocks every step.
	if data == null or grid == null:
		return true
	var pos: Vector3 = from
	for _i: int in max_steps:
		var to_dest: Vector3 = dest - pos
		to_dest.y = 0.0
		if to_dest.length() <= WANDER_ARRIVE:
			return true
		var next: Vector3 = step_toward(data, pos, dest, grid)
		var delta: Vector3 = next - pos
		delta.y = 0.0
		if delta.length() < 0.1:
			return false
		pos = next
		pos.y = from.y
	return false


static func step_toward(
	data: WorldData, from: Vector3, dest: Vector3, grid: WorldGrid = null
) -> Vector3:
	## Next open cell toward dest. Analog of walking a unit, not through a house.
	## With a grid, also refuse steps that `revise_xz` blocks (cliff / water banks).
	if data == null:
		return dest
	var from_cell: Vector2i = _world_to_cell(data, from)
	var dest_cell: Vector2i = _world_to_cell(data, dest)
	if from_cell == dest_cell:
		if grid == null or can_step(data, from, dest, grid):
			return dest
		return from
	var dx: int = signi(dest_cell.x - from_cell.x)
	var dz: int = signi(dest_cell.y - from_cell.y)
	var tried: Dictionary = {}
	var tries: Array[Vector2i] = []
	if dx != 0:
		tries.append(Vector2i(dx, 0))
	if dz != 0:
		tries.append(Vector2i(0, dz))
	if dx != 0 and dz != 0:
		tries.append(Vector2i(dx, dz))
	if dx != 0:
		tries.append(Vector2i(dx, 1))
		tries.append(Vector2i(dx, -1))
	if dz != 0:
		tries.append(Vector2i(1, dz))
		tries.append(Vector2i(-1, dz))
	for off: Vector2i in tries:
		var n: Vector2i = from_cell + off
		tried[n] = true
		if _step_cell_ok(data, from, n, grid):
			return data.cell_to_world(n)
	var around: Array[Vector2i] = []
	for z: int in range(-1, 2):
		for x: int in range(-1, 2):
			if x == 0 and z == 0:
				continue
			var n := Vector2i(from_cell.x + x, from_cell.y + z)
			if tried.has(n):
				continue
			if _step_cell_ok(data, from, n, grid):
				around.append(n)
	if around.is_empty():
		return from
	var best: Vector2i = around[0]
	var best_d: int = _cell_manhattan(best, dest_cell)
	for n: Vector2i in around:
		var d: int = _cell_manhattan(n, dest_cell)
		if d < best_d:
			best = n
			best_d = d
	return data.cell_to_world(best)


static func _step_cell_ok(
	data: WorldData, from: Vector3, cell: Vector2i, grid: WorldGrid
) -> bool:
	if not is_standable(data, cell):
		return false
	return _motion_ok(data, from, data.cell_to_world(cell), grid)


static func _motion_ok(
	data: WorldData, from: Vector3, dest: Vector3, grid: WorldGrid
) -> bool:
	var dir: Vector3 = dest - from
	dir.y = 0.0
	var dist: float = dir.length()
	if dist <= 0.05:
		return true
	var step: Vector3 = from + dir.normalized() * minf(dist, data.cell_size)
	if not is_standable(data, _world_to_cell(data, step)):
		return false
	if grid == null:
		return true
	var revised: Vector3 = FieldCollision.revise_xz(data, grid, from, step)
	var want := Vector2(step.x - from.x, step.z - from.z)
	var got := Vector2(revised.x - from.x, revised.z - from.z)
	if want.length_squared() < 0.0001:
		return true
	return got.dot(want.normalized()) > 0.15


static func pick_act(
	looks: VillagerPersonality.Looks, rng: RandomNumberGenerator = null
) -> StringName:
	## `RANDOM(10)` vs looks boarders: wait / walk / run.
	var roll: int = _rand_i(rng, 10)
	var boarder: Array[int] = _act_boarder(looks)
	if roll <= boarder[0]:
		return ACT_WAIT
	if roll <= boarder[1]:
		return ACT_WALK
	return ACT_RUN


static func _table_for(looks: VillagerPersonality.Looks) -> Array:
	match looks:
		VillagerPersonality.Looks.NORMAL:
			return _girl_table()
		VillagerPersonality.Looks.PEPPY:
			return _kogirl_table()
		VillagerPersonality.Looks.LAZY:
			return _boy_table()
		VillagerPersonality.Looks.JOCK:
			return _sport_table()
		VillagerPersonality.Looks.CRANKY:
			return _grim_table()
		VillagerPersonality.Looks.SNOOTY:
			return _naniwa_table()
		_:
			return _boy_table()


static func _girl_table() -> Array:
	## Normal (`l_girl_goal_data`).
	return [
		_slot(6 * 3600, []),
		_slot(12 * 3600, [GOAL_SHRINE, GOAL_HOME, GOAL_ALONE]),
		_slot(13 * 3600, []),
		_slot(18 * 3600 + 30 * 60, [GOAL_SHRINE, GOAL_HOME]),
		_slot(24 * 3600, []),
	]


static func _kogirl_table() -> Array:
	## Peppy (`l_kogirl_goal_data`): shrine + home all day.
	return [_slot(24 * 3600, [GOAL_SHRINE, GOAL_HOME])]


static func _boy_table() -> Array:
	## Lazy (`l_boy_goal_data`).
	return [
		_slot(9 * 3600, []),
		_slot(12 * 3600, [GOAL_ALONE]),
		_slot(14 * 3600, []),
		_slot(19 * 3600 + 30 * 60, [GOAL_SHRINE, GOAL_HOME]),
		_slot(24 * 3600, []),
	]


static func _sport_table() -> Array:
	## Jock (`l_sport_man_data`).
	return [
		_slot(6 * 3600 + 30 * 60, []),
		_slot(12 * 3600, [GOAL_SHRINE, GOAL_HOME, GOAL_ALONE, GOAL_ALONE]),
		_slot(12 * 3600 + 30 * 60, []),
		_slot(
			23 * 3600,
			[GOAL_SHRINE, GOAL_SHRINE, GOAL_HOME, GOAL_HOME, GOAL_ALONE]
		),
		_slot(24 * 3600, []),
	]


static func _grim_table() -> Array:
	## Cranky (`l_grim_man_goal_data`).
	return [
		_slot(
			24 * 3600,
			[
				GOAL_SHRINE, GOAL_SHRINE, GOAL_SHRINE,
				GOAL_ALONE, GOAL_ALONE, GOAL_ALONE, GOAL_ALONE,
				GOAL_ALONE, GOAL_ALONE, GOAL_ALONE,
			]
		)
	]


static func _naniwa_table() -> Array:
	## Snooty (`l_naniwa_lady_goal_data`).
	var late: Array[StringName] = [
		GOAL_SHRINE, GOAL_SHRINE, GOAL_SHRINE, GOAL_SHRINE, GOAL_SHRINE,
		GOAL_SHRINE, GOAL_SHRINE, GOAL_ALONE, GOAL_ALONE, GOAL_ALONE,
	]
	return [
		_slot(1 * 3600 + 30 * 60, late),
		_slot(10 * 3600, []),
		_slot(13 * 3600, [GOAL_HOME]),
		_slot(14 * 3600, []),
		_slot(21 * 3600, [GOAL_SHRINE, GOAL_SHRINE, GOAL_HOME, GOAL_HOME, GOAL_ALONE]),
		_slot(22 * 3600, []),
		_slot(24 * 3600, late),
	]


static func _slot(end_sec: int, kinds: Array) -> Dictionary:
	return {"end": end_sec, "kinds": kinds}


static func _kinds_from(raw: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw:
		out.append(StringName(str(entry)))
	return out


static func _other_home(
	home_block: Vector2i, homes: Array[Vector2i], rng: RandomNumberGenerator
) -> Vector2i:
	var pool: Array[Vector2i] = []
	for block: Vector2i in homes:
		if is_fg_block(block) and block != home_block:
			pool.append(block)
	if not pool.is_empty():
		return pool[_rand_i(rng, pool.size())]
	return _except_home(home_block, homes, rng)


static func _except_home(
	home_block: Vector2i, homes: Array[Vector2i], rng: RandomNumberGenerator
) -> Vector2i:
	var used_x: Dictionary = {}
	var used_z: Dictionary = {}
	for block: Vector2i in homes:
		used_x[block.x] = true
		used_z[block.y] = true
	used_x[home_block.x] = true
	used_z[home_block.y] = true
	var xs: Array[int] = []
	var zs: Array[int] = []
	for x: int in range(FG_X0, FG_X1 + 1):
		if not used_x.has(x):
			xs.append(x)
	for z: int in range(FG_Z0, FG_Z1 + 1):
		if not used_z.has(z):
			zs.append(z)
	if xs.is_empty() or zs.is_empty():
		return FALLBACK_BLOCK
	return Vector2i(xs[_rand_i(rng, xs.size())], zs[_rand_i(rng, zs.size())])


static func _alone_block(occupied: Array[Vector2i], rng: RandomNumberGenerator) -> Vector2i:
	var busy: Dictionary = {}
	for block: Vector2i in occupied:
		busy[block] = true
	var empty: Array[Vector2i] = []
	for bz: int in range(FG_Z0, FG_Z1 + 1):
		for bx: int in range(FG_X0, FG_X1 + 1):
			var block := Vector2i(bx, bz)
			if not busy.has(block):
				empty.append(block)
	if empty.is_empty():
		return ALONE_DEFAULT
	return empty[_rand_i(rng, empty.size())]


static func _walkable_cells(data: WorldData, block: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var origin: Vector2i
	var cols: int
	var rows: int
	if has_town_acres(data) and is_fg_block(block):
		origin = Vector2i((block.x - 1) * WorldGenerator.UT, (block.y - 1) * WorldGenerator.UT)
		cols = WorldGenerator.UT
		rows = WorldGenerator.UT
	else:
		origin = Vector2i.ZERO
		cols = data.columns
		rows = data.rows
	for z: int in range(origin.y + 1, origin.y + rows - 1):
		for x: int in range(origin.x + 1, origin.x + cols - 1):
			var cell := Vector2i(x, z)
			if not data.is_in_bounds(cell):
				continue
			if is_standable(data, cell):
				out.append(cell)
	return out


static func _origin_cell(data: WorldData, block: Vector2i) -> Vector2i:
	if has_town_acres(data) and is_fg_block(block):
		return Vector2i((block.x - 1) * WorldGenerator.UT, (block.y - 1) * WorldGenerator.UT)
	return Vector2i.ZERO


static func _walkable_terrain(terrain: WorldGrid.Terrain) -> bool:
	return (
		terrain == WorldGrid.Terrain.GRASS
		or terrain == WorldGrid.Terrain.SOIL
		or terrain == WorldGrid.Terrain.SAND
		or terrain == WorldGrid.Terrain.PATH
		or terrain == WorldGrid.Terrain.STONE
	)


static func _cell_manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _world_to_cell(data: WorldData, world_pos: Vector3) -> Vector2i:
	var org: Vector3 = data.origin()
	return Vector2i(
		int(floor((world_pos.x - org.x) / data.cell_size)),
		int(floor((world_pos.z - org.z) / data.cell_size))
	)


static func _dest_ok(
	data: WorldData,
	block: Vector2i,
	from: Vector3,
	stand: Vector3,
	grid: WorldGrid = null
) -> bool:
	if not is_in_block(data, block, stand):
		return false
	if not is_standable(data, _world_to_cell(data, stand)):
		return false
	var from_delta: Vector3 = stand - from
	from_delta.y = 0.0
	if from_delta.length() < MIN_STEP:
		return false
	if grid != null and not path_clear(data, from, stand, grid):
		return false
	return true


static func _is_blocked_cell(data: WorldData, cell: Vector2i) -> bool:
	_ensure_blocked_cache(data)
	return _blocked_cells.has(cell)


static func _ensure_blocked_cache(data: WorldData) -> void:
	var data_id: int = data.get_instance_id()
	var sig: int = _layout_sig(data)
	if data_id == _blocked_data_id and sig == _blocked_sig:
		return
	_blocked_data_id = data_id
	_blocked_sig = sig
	_blocked_cells.clear()
	for b: BuildingPlacement in data.buildings:
		if b == null or not b.occupy_grid:
			continue
		_mark_blocked(b.cell, b.footprint, b.facing)
	for o: ObjectPlacement in data.objects:
		if o == null or not o.occupy_grid:
			continue
		if not _BLOCK_STAND.has(o.kind):
			continue
		_mark_blocked(o.cell, o.footprint, o.facing)


static func _layout_sig(data: WorldData) -> int:
	## Cheap invalidation when trees are chopped or buildings change.
	var sig: int = data.buildings.size() + data.objects.size() * 7919
	if not data.buildings.is_empty():
		var first: BuildingPlacement = data.buildings[0]
		var last: BuildingPlacement = data.buildings[data.buildings.size() - 1]
		if first != null:
			sig = sig * 31 + first.cell.x + first.cell.y * 1024
		if last != null:
			sig = sig * 31 + last.cell.x + last.cell.y * 2048
	if not data.objects.is_empty():
		var o0: ObjectPlacement = data.objects[0]
		var o1: ObjectPlacement = data.objects[data.objects.size() - 1]
		if o0 != null:
			sig = sig * 31 + o0.cell.x + o0.cell.y * 4096 + hash(o0.kind)
		if o1 != null:
			sig = sig * 31 + o1.cell.x + o1.cell.y * 8192 + hash(o1.kind)
	return sig


static func _mark_blocked(anchor: Vector2i, size: Vector2i, facing: WorldGrid.Facing) -> void:
	var w: int = maxi(size.x, 1)
	var d: int = maxi(size.y, 1)
	for x: int in w:
		for z: int in d:
			_blocked_cells[anchor + _rotate_offset(Vector2i(x, z), facing)] = true


static func _covers(
	anchor: Vector2i, size: Vector2i, facing: WorldGrid.Facing, cell: Vector2i
) -> bool:
	var w: int = maxi(size.x, 1)
	var d: int = maxi(size.y, 1)
	for x: int in w:
		for z: int in d:
			if anchor + _rotate_offset(Vector2i(x, z), facing) == cell:
				return true
	return false


static func _rotate_offset(offset: Vector2i, facing: WorldGrid.Facing) -> Vector2i:
	match facing:
		WorldGrid.Facing.EAST:
			return Vector2i(offset.y, -offset.x)
		WorldGrid.Facing.NORTH:
			return Vector2i(-offset.x, -offset.y)
		WorldGrid.Facing.WEST:
			return Vector2i(-offset.y, offset.x)
		_:
			return offset


static func _act_boarder(looks: VillagerPersonality.Looks) -> Array[int]:
	match looks:
		VillagerPersonality.Looks.NORMAL:
			return [3, 6]
		VillagerPersonality.Looks.PEPPY:
			return [6, 8]
		VillagerPersonality.Looks.LAZY:
			return [5, 7]
		VillagerPersonality.Looks.JOCK:
			return [2, 4]
		VillagerPersonality.Looks.CRANKY:
			return [3, 6]
		VillagerPersonality.Looks.SNOOTY:
			return [4, 8]
		_:
			return [5, 7]


static func _snap_walkable(data: WorldData, world_pos: Vector3) -> Vector3:
	var org: Vector3 = data.origin()
	var cell := Vector2i(
		int(floor((world_pos.x - org.x) / data.cell_size)),
		int(floor((world_pos.z - org.z) / data.cell_size))
	)
	if data.is_in_bounds(cell) and is_standable(data, cell):
		return data.cell_to_world(cell)
	for radius: int in range(1, 8):
		for dz: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var n := Vector2i(cell.x + dx, cell.y + dz)
				if data.is_in_bounds(n) and is_standable(data, n):
					return data.cell_to_world(n)
	return world_pos


static func _rand_f(rng: RandomNumberGenerator) -> float:
	if rng != null:
		return rng.randf()
	return randf()


static func _rand_i(rng: RandomNumberGenerator, n: int) -> int:
	if n <= 1:
		return 0
	if rng != null:
		return rng.randi_range(0, n - 1)
	return randi() % n
