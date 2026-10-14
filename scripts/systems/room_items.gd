class_name RoomItems
extends RefCounted

## Things put down in your own house that are not furniture (`mCoBG_LAYER0` floor units and
## `mCoBG_LAYER1` table tops holding an ordinary item): fruit, shells, letters, tools.
## They are room placements whose id names an item rather than furniture, so they save with
## the room and ride along on a table that is pushed. The HRA takes a point off for each
## (`mMkRm_EvaluateLetsClean`).

## Units tried around the one in front of the player, nearest first.
const AROUND: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]


## A placement holding an item rather than furniture.
static func is_loose(entry: FurniturePlacement) -> bool:
	if entry == null or entry.furniture_id == &"":
		return false
	var item: ItemData = ItemCatalog.get_item(entry.furniture_id)
	return item != null and not (item is FurnitureData)


## Only the player's own floors keep things put down (`mFI` drop in `PLAYER_ROOM` fields).
static func can_hold(room: Room) -> bool:
	return room != null and PlayerHouse.is_player_room(room.id)


static func count(room: Room) -> int:
	var n: int = 0
	if room == null:
		return 0
	for entry: FurniturePlacement in room.placements:
		if is_loose(entry):
			n += 1
	return n


## Where an item put down at `front` lands: `{cell, layer}`, or empty when nowhere is free.
## A free floor unit, or the top of a table with nothing on it.
static func spot(session: IndoorSession, front: Vector2i) -> Dictionary:
	if session == null or not can_hold(session.room):
		return {}
	for off: Vector2i in AROUND:
		var cell: Vector2i = front + off
		if not session.room.is_inner(cell) or session.room.is_exit_cell(cell):
			continue
		if session.grid.occupant_at(cell) == &"":
			return {"cell": cell, "layer": 0}
		if session._table_at(cell) != null and session.surface_item_at(cell) == null:
			return {"cell": cell, "layer": 1}
	return {}


## Put `item` down in front of the player. Returns the new placement or null.
static func drop(session: IndoorSession, front: Vector2i, item: ItemData, wrapped: bool = false) -> FurniturePlacement:
	if item == null or item is FurnitureData:
		return null
	var at: Dictionary = spot(session, front)
	if at.is_empty():
		return null
	var entry := FurniturePlacement.new()
	entry.id = session.room.next_placement_id()
	entry.furniture_id = item.id
	entry.cell = at["cell"]
	entry.layer = int(at["layer"])
	entry.footprint = Vector2i.ONE
	entry.wrapped = wrapped
	session.room.placements.append(entry)
	if entry.layer == 0:
		session.grid.place(entry.id, entry.cell, Vector2i.ONE, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM)
	session._report_change()
	return entry


## The pickup for `placement_id` was taken: off the room.
static func picked(placement_id: StringName) -> bool:
	var session: IndoorSession = Game.interior_session if Game != null else null
	if session == null or session.room == null:
		return false
	var entry: FurniturePlacement = session.room.placement_by_id(placement_id)
	if not is_loose(entry):
		return false
	session.room.placements.erase(entry)
	session.grid.remove(entry.id)
	session._report_change()
	return true


## The pickup node for a loose placement (`InteriorBuilder.add_furniture`).
static func instance(root: Node3D, session: IndoorSession, entry: FurniturePlacement) -> Node3D:
	var item: ItemData = ItemCatalog.get_item(entry.furniture_id)
	if root == null or item == null or not ResourceLoader.exists(FieldItems.SCENE):
		return null
	var host: Node3D = (load(FieldItems.SCENE) as PackedScene).instantiate() as Node3D
	host.name = String(entry.id)
	host.set("item", item)
	host.set("wrapped", entry.wrapped)
	host.set("persist_id", entry.id)
	host.set("occupant_id", entry.id)
	host.set("occupy_grid", false)
	var pos: Vector3 = session.grid.furniture_world(entry.cell, Vector2i.ONE, entry.facing)
	pos.y = session.surface_y(entry.cell) if entry.layer > 0 else 0.0
	host.position = pos
	root.add_child(host)
	return host
