class_name VillagerWalk
extends RefCounted

## Field roam goals from looks + time (`mNpcW` kinds), not waypoint graphs.
## Concurrent off-home walkers match `mNpcW_GET_WALK_NUM` (max `mNpcW_MAX`).

const GOAL_SHRINE := &"shrine"
const GOAL_HOME := &"home"
const GOAL_ALONE := &"alone"
const GOAL_MY_HOME := &"my_home"

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

static var _walkers: Dictionary = {}


static func reset() -> void:
	_walkers.clear()


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
		var origin: Vector2i = _origin_cell(data, block)
		return data.cell_to_world(origin + Vector2i(8, 8))
	var cell: Vector2i = cells[_rand_i(rng, cells.size())]
	return data.cell_to_world(cell)


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
			if _walkable_terrain(data.terrain_at(cell)):
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


static func _rand_i(rng: RandomNumberGenerator, n: int) -> int:
	if n <= 1:
		return 0
	if rng != null:
		return rng.randi_range(0, n - 1)
	return randi() % n
