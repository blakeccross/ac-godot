class_name ShellUse
extends RefCounted

## Sea shells washing up on the beach (`mFI_SetShell`). A play session starts with twenty
## owed (`mFI_SetFirstSetShell`) and every tenth minute owes one more. Out on the field they
## land on free wave units of the beach acres, never the one the player is in, at most four
## to an acre (`mFI_ResearchShell`): an even share first, the rest at random
## (`mFI_DivideShell`). One in four is rare: a conch or white scallop (`mFI_GetShell`). A shell
## is an ordinary ground item; Nook pays a quarter of `mSP_ItemNo2ItemPrice`. Not an autoload.
##
## `Game.shells`: `shell_<x>_<z>` → item id. Saved.

const FIRST_NUM := 20
const MAX_PER_BLOCK := 4
const EVERY_MINUTES := 10
const NORMAL: Array[StringName] = [
	&"lions_paw", &"wentletrap", &"venus_comb", &"porceletta", &"sand_dollar", &"coral",
]
const RARE: Array[StringName] = [&"conch", &"white_scallop"]
const SCENE := "res://scenes/world/item_pickup.tscn"
const GROUP := &"beach_shell"


static func persist_id(cell: Vector2i) -> StringName:
	return StringName("shell_%d_%d" % [cell.x, cell.y])


static func cell_from_persist(id: StringName) -> Vector2i:
	var s := String(id)
	if not s.begins_with("shell_"):
		return Vector2i(-1, -1)
	var parts: PackedStringArray = s.substr(6).split("_")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


## `mFI_GetShell`: a rare one on `RANDOM(4) == 3`.
static func pick(rng: RandomNumberGenerator) -> StringName:
	if rng.randi_range(0, 3) == 3:
		return RARE[rng.randi_range(0, RARE.size() - 1)]
	return NORMAL[rng.randi_range(0, NORMAL.size() - 1)]


## `l_sandy_beach_bx/bz`: the five acres along the sea.
static func beach_blocks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for bx: int in range(1, TownAssessment.FG_BLOCK_X + 1):
		out.append(Vector2i(bx, TownAssessment.FG_BLOCK_Z))
	return out


## `mCoBG_CheckWaveAttr`; acres without collision data fall back to sand.
static func is_wave_cell(world: Node, grid: WorldGrid, cell: Vector2i) -> bool:
	var layout: WorldData = world.get("layout") as WorldData if world != null and "layout" in world else null
	var attr: int = FieldCollision.unit_attr_at_cell(layout, cell) if layout != null else -1
	if attr >= 0:
		return FieldCatalog.is_wave_attr(attr)
	return grid.terrain_at(cell) == WorldGrid.Terrain.SAND


static func free_cells(world: Node, grid: WorldGrid, block: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z: int in 16:
		for x: int in 16:
			var cell := Vector2i((block.x - 1) * 16 + x, (block.y - 1) * 16 + z)
			if not grid.is_in_bounds(cell) or not is_wave_cell(world, grid, cell):
				continue
			if grid.can_place(cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM):
				out.append(cell)
	return out


static func count_in(block: Vector2i) -> int:
	var n: int = 0
	for key: Variant in Game.shells.keys():
		if TownSpace.block_of_cell(cell_from_persist(StringName(str(key)))) == block:
			n += 1
	return n


## `mFI_DivideShell`: how many go to each acre. `room` is how many each can still take.
static func divide(room: Array[int], amount: int, rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = []
	out.resize(room.size())
	out.fill(0)
	var open := func() -> Array[int]:
		var idx: Array[int] = []
		for i: int in room.size():
			if out[i] < room[i]:
				idx.append(i)
		return idx
	## An even share while there are more to set than acres to take them.
	var blocks: Array[int] = open.call()
	while amount > 0 and not blocks.is_empty() and amount > blocks.size():
		for i: int in blocks:
			out[i] += 1
			amount -= 1
		blocks = open.call()
	## The rest one at a time to a random acre.
	while amount > 0:
		blocks = open.call()
		if blocks.is_empty():
			break
		out[blocks[rng.randi_range(0, blocks.size() - 1)]] += 1
		amount -= 1
	return out


## `mFI_SetShellWave`: set up to `amount`; returns how many landed.
static func wash_up(world: Node, amount: int, player_block: Vector2i, rng: RandomNumberGenerator) -> int:
	var grid: WorldGrid = world.get("grid") as WorldGrid if world != null else null
	if grid == null or amount <= 0:
		return 0
	var blocks: Array[Vector2i] = []
	var cells: Array = []
	var room: Array[int] = []
	for block: Vector2i in beach_blocks():
		if block == player_block:
			continue
		var free: Array[Vector2i] = free_cells(world, grid, block)
		var take: int = mini(MAX_PER_BLOCK - count_in(block), free.size())
		if take <= 0:
			continue
		blocks.append(block)
		cells.append(free)
		room.append(take)
	var share: Array[int] = divide(room, amount, rng)
	var placed: int = 0
	for i: int in blocks.size():
		var free: Array = cells[i]
		for _n: int in share[i]:
			if free.is_empty():
				break
			var cell: Vector2i = free.pop_at(rng.randi_range(0, free.size() - 1))
			if _put(world, grid, cell, pick(rng)):
				placed += 1
	return placed


## Once a game minute out on the field: a tenth minute owes another shell, and what is owed
## washes up (`mFI_SetShell`).
static func tick(world: Node, minute: int, player_block: Vector2i, rng: RandomNumberGenerator) -> void:
	if minute % EVERY_MINUTES == 0:
		if not Game.shell_minute_counted:
			Game.shell_minute_counted = true
			Game.shells_owed += 1
	else:
		Game.shell_minute_counted = false
	if Game.shells_owed > 0:
		wash_up(world, Game.shells_owed, player_block, rng)
		Game.shells_owed = 0


static func restore(world: Node, grid: WorldGrid) -> void:
	if grid == null:
		return
	for key: Variant in Game.shells.keys():
		var pid := StringName(str(key))
		var cell: Vector2i = cell_from_persist(pid)
		if not grid.is_in_bounds(cell) or (grid.is_occupied(cell) and grid.occupant_at(cell) != pid):
			Game.shells.erase(key)
			continue
		if not grid.is_occupied(cell):
			grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM)
		_instance(world, grid, cell, pid, StringName(str(Game.shells[key])))


## Picked up: the ground item is just gone (`item_pickup` calls this).
static func picked(pid: StringName) -> bool:
	if not Game.shells.has(String(pid)):
		return false
	Game.shells.erase(String(pid))
	return true


static func _put(world: Node, grid: WorldGrid, cell: Vector2i, item_id: StringName) -> bool:
	var pid: StringName = persist_id(cell)
	if not grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM):
		return false
	Game.shells[String(pid)] = String(item_id)
	_instance(world, grid, cell, pid, item_id)
	return true


static func _instance(world: Node, grid: WorldGrid, cell: Vector2i, pid: StringName, item_id: StringName) -> void:
	if world == null:
		return
	var objects: Node = world.get_node_or_null("Objects")
	var item: ItemData = ItemCatalog.get_item(item_id)
	if objects == null or item == null or not ResourceLoader.exists(SCENE):
		return
	var host: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	host.set("item", item)
	host.set("persist_id", pid)
	host.set("occupant_id", pid)
	host.add_to_group(GROUP)
	objects.add_child(host)
	var pos: Vector3 = grid.cell_to_world(cell)
	if "layout" in world and world.layout != null:
		pos.y = FieldCollision.ground_y(world.layout as WorldData, cell, FieldCollision.FG_GROUND_DIST)
	host.global_position = pos
