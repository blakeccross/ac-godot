class_name MushroomUse
extends RefCounted

## Autumn mushrooms (`m_mushroom`). During mushroom season (`mEv_EVENT_MUSHROOM_SEASON`,
## Oct 15–25) the first field visit on a new day between 8:00 and 9:15 sets
## `5 − minutes/15` mushrooms (one at 9:00–9:14) under grown trees: a random acre column, a
## random acre in it, a random host tree, a random free unit beside or below it. Then one
## goes for every quarter hour that passes. Neither happens in the player's acre's row or
## column (`mMsr_SetMushroomNum`) or acre (`mMsr_ClearMushrooms`). A mushroom is an ordinary
## ground item (`ITM_FOOD_MUSHROOM`) worth 5,000 Bells at the shop. Not an autoload.

const ITEM_ID := &"mushroom"
const SEASON_EVENT := &"mushroom_season"
const ACTIVE_HOUR := 8
const NUM := 5
const QUARTER := 15
## `area_table`: left, right, below-left, below, below-right of the tree.
const AROUND: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const SCENE := "res://scenes/world/item_pickup.tscn"


static func persist_id(cell: Vector2i) -> StringName:
	return StringName("mushroom_%d_%d" % [cell.x, cell.y])


static func cell_from_persist(id: StringName) -> Vector2i:
	var s := String(id)
	if not s.begins_with("mushroom_"):
		return Vector2i(-1, -1)
	var parts: PackedStringArray = s.substr(9).split("_")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


static func in_season() -> bool:
	return Game.events != null and Game.events.is_active(SEASON_EVENT)


## `mMsr_GetMushroomNum`: how many to set now (0 = none).
static func crop(hour: int, minute: int, new_day: bool) -> int:
	if not new_day:
		return 0
	if hour == ACTIVE_HOUR:
		return NUM - minute / QUARTER
	if hour == ACTIVE_HOUR + 1 and minute < QUARTER:
		return NUM - 4
	return 0


## `mMsr_GetFirstClearMushroomNum`: quarter hours between two absolute minutes.
static func quarters_between(a_minute: int, b_minute: int) -> int:
	if a_minute == b_minute:
		return 0
	return absi(a_minute / QUARTER - b_minute / QUARTER)


static func _day(minute: int) -> int:
	return floori(float(minute) / 1440.0)


## `mMsr_FirstClearMushroom`, at the start of a play session: mushrooms whose quarter hours
## ran out while the game was off are gone; a new day readies the next crop.
static func first_clear(world: Node, now_minute: int, rng: RandomNumberGenerator) -> void:
	var last: int = Game.mushroom_minute if Game.mushroom_minute >= 0 else now_minute
	var n: int = quarters_between(now_minute, last)
	if n > 0:
		clear(world, n, Vector2i(-1, -1), rng)
	if _day(last) != _day(now_minute):
		Game.mushroom_active = true
	Game.mushroom_minute = now_minute


## `mMsr_SetMushroom`, called while the player is out on the field.
static func tick(world: Node, now_minute: int, hour: int, minute: int, player_block: Vector2i, rng: RandomNumberGenerator) -> void:
	if not in_season():
		return
	## Never set: as if last done yesterday.
	var last: int = Game.mushroom_minute if Game.mushroom_minute >= 0 else now_minute - 1440
	var new_day: bool = Game.mushroom_active or _day(last) != _day(now_minute)
	var n: int = crop(hour, minute, new_day)
	if n > 0 and n <= NUM:
		grow(world, n, player_block, rng)
		Game.mushroom_minute = now_minute
		Game.mushroom_active = false
		return
	var gone: int = quarters_between(now_minute, last)
	if gone > 0:
		clear(world, gone, player_block, rng)
		if not Game.mushroom_active and _day(last) != _day(now_minute):
			Game.mushroom_active = true
		Game.mushroom_minute = now_minute


## Host trees per field acre: block → Array of tree cells with a free spot around them.
static func hosts(world: Node) -> Dictionary:
	var out: Dictionary = {}
	var grid: WorldGrid = world.get("grid") as WorldGrid if world != null else null
	if grid == null or world.get_tree() == null:
		return out
	for node: Node in world.get_tree().get_nodes_in_group("plant"):
		if not node is Node3D or not node.has_method("can_host_mushroom") or node.is_queued_for_deletion():
			continue
		if not bool(node.call("can_host_mushroom")):
			continue
		var cell: Vector2i = grid.world_to_cell((node as Node3D).global_position)
		var block: Vector2i = TownSpace.block_of_cell(cell)
		if block.x < 1 or block.x > TownAssessment.FG_BLOCK_X or block.y < 1 or block.y > TownAssessment.FG_BLOCK_Z:
			continue
		## `ut_x < UT_X_NUM - 1 && ut_z < UT_Z_NUM - 1`.
		if cell.x % 16 >= 15 or cell.y % 16 >= 15:
			continue
		if free_spots(grid, cell).is_empty():
			continue
		if not out.has(block):
			out[block] = []
		(out[block] as Array).append(cell)
	return out


static func free_spots(grid: WorldGrid, tree_cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for o: Vector2i in AROUND:
		var c: Vector2i = tree_cell + o
		if grid.can_place(c, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM):
			out.append(c)
	return out


## `mMsr_SetMushroomNum`: column, then acre, then tree, then spot. The player's acre row and
## column are left out.
static func grow(world: Node, amount: int, player_block: Vector2i, rng: RandomNumberGenerator) -> int:
	var grid: WorldGrid = world.get("grid") as WorldGrid if world != null else null
	if grid == null:
		return 0
	var placed: int = 0
	for _n: int in amount:
		var by_block: Dictionary = hosts(world)
		var columns: Dictionary = {}
		for block: Variant in by_block:
			var b: Vector2i = block
			if b.x == player_block.x or b.y == player_block.y:
				continue
			if not columns.has(b.x):
				columns[b.x] = []
			(columns[b.x] as Array).append(b)
		if columns.is_empty():
			break
		var xs: Array = columns.keys()
		xs.sort()
		var column: Array = columns[xs[rng.randi_range(0, xs.size() - 1)]]
		column.sort()
		var trees: Array = by_block[column[rng.randi_range(0, column.size() - 1)]]
		var tree_cell: Vector2i = trees[rng.randi_range(0, trees.size() - 1)]
		var spots: Array[Vector2i] = free_spots(grid, tree_cell)
		if spots.is_empty():
			continue
		if _put(world, grid, spots[rng.randi_range(0, spots.size() - 1)]):
			placed += 1
	return placed


## `mMsr_ClearMushrooms`: `amount` mushrooms go, shared across acres, never from the player's
## acre. More than are left takes them all.
static func clear(world: Node, amount: int, player_block: Vector2i, rng: RandomNumberGenerator) -> int:
	var candidates: Array = []
	for key: Variant in Game.mushrooms.keys():
		var cell: Vector2i = cell_from_persist(StringName(str(key)))
		if cell.x < 0 or TownSpace.block_of_cell(cell) == player_block:
			continue
		candidates.append(String(key))
	candidates.sort()
	var cleared: int = 0
	while cleared < amount and not candidates.is_empty():
		var pick: int = rng.randi_range(0, candidates.size() - 1) if amount < candidates.size() + cleared else 0
		_remove(world, StringName(str(candidates[pick])))
		candidates.remove_at(pick)
		cleared += 1
	return cleared


static func restore(world: Node, grid: WorldGrid) -> void:
	if grid == null:
		return
	for key: Variant in Game.mushrooms.keys():
		var pid := StringName(str(key))
		var cell: Vector2i = cell_from_persist(pid)
		if not grid.is_in_bounds(cell):
			Game.mushrooms.erase(key)
			continue
		if grid.is_occupied(cell) and grid.occupant_at(cell) != pid:
			Game.mushrooms.erase(key)
			continue
		if not grid.is_occupied(cell):
			grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM)
		_instance(world, grid, cell, pid)


## Picked up: the ground item is just gone (`item_pickup` calls this).
static func picked(pid: StringName) -> bool:
	if not Game.mushrooms.has(String(pid)):
		return false
	Game.mushrooms.erase(String(pid))
	return true


static func _put(world: Node, grid: WorldGrid, cell: Vector2i) -> bool:
	var pid: StringName = persist_id(cell)
	if not grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM):
		return false
	Game.mushrooms[String(pid)] = 1
	_instance(world, grid, cell, pid)
	return true


static func _remove(world: Node, pid: StringName) -> void:
	Game.mushrooms.erase(String(pid))
	var grid: WorldGrid = world.get("grid") as WorldGrid if world != null else null
	if grid != null:
		grid.remove(pid)
	if world != null and world.get_tree() != null:
		for node: Node in world.get_tree().get_nodes_in_group("mushroom"):
			if node.get("persist_id") == pid:
				node.queue_free()


static func _instance(world: Node, grid: WorldGrid, cell: Vector2i, pid: StringName) -> void:
	if world == null:
		return
	var objects: Node = world.get_node_or_null("Objects")
	var item: ItemData = ItemCatalog.get_item(ITEM_ID)
	if objects == null or item == null or not ResourceLoader.exists(SCENE):
		return
	var host: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	host.set("item", item)
	host.set("persist_id", pid)
	host.set("occupant_id", pid)
	host.add_to_group("mushroom")
	objects.add_child(host)
	var pos: Vector3 = grid.cell_to_world(cell)
	if "layout" in world and world.layout != null:
		pos.y = FieldCollision.ground_y(world.layout as WorldData, cell, FieldCollision.FG_GROUND_DIST)
	host.global_position = pos
