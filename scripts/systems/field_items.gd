class_name FieldItems
extends RefCounted

## Items lying on the field (`Save fg`'s item units): what the player drops, fruit and
## furniture shaken from trees, presents off balloons. One item a unit, kept across rooms and
## saves. Dropping puts the item on the unit in front, or the nearest free unit around it
## (`mPlib_Get_space_putin_item`'s search). Picking it up frees the unit. At renewal the turnips
## lying out spoil once a Sunday has come round, and spoiled ones are cleared away
## (`mAGrw_SpoilKabu` / `mAGrw_ClearSpoiledKabu`). Not an autoload.
##
## `Game.field_items`: `fitem_<x>_<z>` → `{id, wrapped}`.

const PREFIX := "fitem_"
const SCENE := "res://scenes/world/item_pickup.tscn"
const GROUP := &"field_item"
## `mPlib`'s put search: in front, then the sides, then behind.
const AROUND: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 1), Vector2i(1, 1), Vector2i(0, 1),
]


static func persist_id(cell: Vector2i) -> StringName:
	return StringName("%s%d_%d" % [PREFIX, cell.x, cell.y])


static func cell_from_persist(id: StringName) -> Vector2i:
	var s := String(id)
	if not s.begins_with(PREFIX):
		return Vector2i(-1, -1)
	var parts: PackedStringArray = s.substr(PREFIX.length()).split("_")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


static func is_field_item(pid: StringName) -> bool:
	return Game.field_items.has(String(pid))


static func item_at(cell: Vector2i) -> StringName:
	var rec: Variant = Game.field_items.get(String(persist_id(cell)), {})
	return StringName(str((rec as Dictionary).get("id", ""))) if typeof(rec) == TYPE_DICTIONARY else &""


## A unit an item can lie on: in bounds, free, and ground rather than water or a cliff.
static func can_put(grid: WorldGrid, cell: Vector2i) -> bool:
	if grid == null or not grid.is_in_bounds(cell) or grid.is_occupied(cell):
		return false
	var t: WorldGrid.Terrain = grid.terrain_at(cell)
	return t != WorldGrid.Terrain.WATER and t != WorldGrid.Terrain.CLIFF


## The unit in front if free, else the nearest free one around it. `facing` is the step from
## the player to the unit in front. (-1, -1) when there is nowhere.
static func drop_cell(grid: WorldGrid, front: Vector2i, facing: Vector2i) -> Vector2i:
	if can_put(grid, front):
		return front
	## The search turns with the player: "-1, 0" is their left.
	var left := Vector2i(facing.y, -facing.x)
	for off: Vector2i in AROUND:
		var cell: Vector2i = front + left * -off.x + facing * -off.y
		if can_put(grid, cell):
			return cell
	return Vector2i(-1, -1)


## Lay `item_id` on `cell`. Returns the ground item (not yet positioned when `fall_from` is
## given: the caller drops it in), or null when the unit is taken.
static func put(world: Node, cell: Vector2i, item_id: StringName, wrapped: bool = false) -> Node3D:
	var grid: WorldGrid = world.get("grid") as WorldGrid if world != null else null
	if not can_put(grid, cell) or ItemCatalog.get_item(item_id) == null:
		return null
	var pid: StringName = persist_id(cell)
	if not grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM):
		return null
	Game.field_items[String(pid)] = {"id": String(item_id), "wrapped": wrapped}
	return _instance(world, grid, cell, pid)


## Picked up: the record goes and the unit is free (`item_pickup` calls this).
static func picked(pid: StringName) -> bool:
	if not Game.field_items.has(String(pid)):
		return false
	Game.field_items.erase(String(pid))
	return true


static func restore(world: Node, grid: WorldGrid) -> void:
	if grid == null:
		return
	for key: Variant in Game.field_items.keys():
		var pid := StringName(str(key))
		var cell: Vector2i = cell_from_persist(pid)
		var rec: Variant = Game.field_items[key]
		if typeof(rec) != TYPE_DICTIONARY or not grid.is_in_bounds(cell) \
				or (grid.is_occupied(cell) and grid.occupant_at(cell) != pid) \
				or ItemCatalog.get_item(StringName(str((rec as Dictionary).get("id", "")))) == null:
			Game.field_items.erase(key)
			continue
		if not grid.is_occupied(cell):
			grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM)
		_instance(world, grid, cell, pid)


## `mAGrw_CheckSpoilKabuTime`: the renewals just run (`days` of them, the last today) reached
## a Sunday morning.
static func sunday_passed(year: int, month: int, day: int, days: int) -> bool:
	var weekday: int = EventDates.weekday(year, month, day)
	for k: int in clampi(days, 0, 7):
		if posmod(weekday - k, 7) == 0:
			return true
	return false


## `mAGrw_ClearSpoiledKabu` then `mAGrw_SpoilKabu` over the field; with `spoil`, the turnips
## in the pockets too (`mAGrw_SpoilAllPossession`). Live ground items follow.
static func renew(spoil: bool, inventory: Inventory = null, tree: SceneTree = null) -> void:
	for key: Variant in Game.field_items.keys():
		var rec: Dictionary = Game.field_items[key]
		var id := StringName(str(rec.get("id", "")))
		if id == KabuMarket.SPOILED:
			Game.field_items.erase(key)
			_refresh_node(tree, StringName(str(key)))
		elif spoil and KabuMarket.bundle_size(id) > 0:
			rec["id"] = String(KabuMarket.SPOILED)
			_refresh_node(tree, StringName(str(key)))
	if spoil and inventory != null:
		spoil_pockets(inventory)


static func spoil_pockets(inventory: Inventory) -> int:
	var n: int = 0
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inventory.slot_at(i)
		if slot != null and not slot.is_empty() and KabuMarket.bundle_size(slot.item.item_id) > 0:
			slot.item.item_id = KabuMarket.SPOILED
			n += 1
	if n > 0:
		inventory.changed.emit()
	return n


static func _refresh_node(tree: SceneTree, pid: StringName) -> void:
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(GROUP):
		if node.get("persist_id") != pid:
			continue
		if not Game.field_items.has(String(pid)):
			var world: Node = World.find(tree)
			var grid: WorldGrid = world.get("grid") as WorldGrid if world != null else null
			if grid != null:
				grid.remove(pid)
			node.queue_free()
		elif node.has_method("set_item"):
			node.call("set_item", ItemCatalog.get_item(StringName(str((Game.field_items[String(pid)] as Dictionary).get("id", "")))))


static func _instance(world: Node, grid: WorldGrid, cell: Vector2i, pid: StringName) -> Node3D:
	if world == null:
		return null
	var objects: Node = world.get_node_or_null("Objects")
	var rec: Dictionary = Game.field_items.get(String(pid), {})
	var item: ItemData = ItemCatalog.get_item(StringName(str(rec.get("id", ""))))
	if objects == null or item == null or not ResourceLoader.exists(SCENE):
		return null
	var host: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	host.set("item", item)
	host.set("wrapped", bool(rec.get("wrapped", false)))
	host.set("persist_id", pid)
	host.set("occupant_id", pid)
	host.set("occupy_grid", false)
	host.add_to_group(GROUP)
	objects.add_child(host)
	var pos: Vector3 = grid.cell_to_world(cell)
	if "layout" in world and world.layout != null:
		pos.y = FieldCollision.ground_y(world.layout as WorldData, cell, FieldCollision.FG_GROUND_DIST)
	host.global_position = pos
	return host
