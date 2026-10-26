class_name FurnitureEditing
extends RefCounted

## Rearranging the player's own room: put the held piece down, pick one up, turn it, and lay
## wallpaper or carpet. Only works while `Game.is_decorating()`.


## The furniture in the selected pocket, if that is what the player is holding.
static func held() -> FurnitureData:
	var slot: InventorySlot = Game.inventory.selected_slot()
	if slot == null or slot.is_empty():
		return null
	return ItemCatalog.get_item(slot.item.item_id) as FurnitureData


## Set the held piece down on the cell in front of `player`.
static func place_held(player: Player) -> bool:
	var session: IndoorSession = Game.interior_session
	if player == null or session == null or not Game.is_decorating():
		return false
	var data: FurnitureData = held()
	if data == null:
		return false
	var facing: WorldGrid.Facing = WorldGrid.facing_from_player_yaw(player.facing_yaw())
	var cell: Vector2i = session.grid.step(session.grid.world_to_cell(player.global_position), facing)
	if session.is_full():
		Game.post_notice("This room can't hold any more furniture.")
		return false
	var entry: FurniturePlacement = session.place(data, cell, facing)
	if entry == null:
		Game.post_notice("Can't place that here.")
		return false
	Game.inventory.remove(data.id, 1)
	var host: Interior = Interior.find(Game.get_tree())
	if host != null:
		host.spawn_placement(entry)
	Game.post_notice("Placed %s." % data.display_name)
	return true


## Take a placed piece, and whatever sits on or in it, back into the pockets.
static func pick_up(placement_id: StringName) -> bool:
	var session: IndoorSession = Game.interior_session
	if session == null or not Game.is_decorating():
		return false
	var entry: FurniturePlacement = session.room.placement_by_id(placement_id)
	if entry == null:
		return false
	if entry.layer == 0 and _has_surface_items(session, entry):
		Game.post_notice("Clear that first.")
		return false
	var data: ItemData = ItemCatalog.get_item(entry.furniture_id)
	if data == null or not Game.inventory.has_space_for(data, 1):
		return false
	if not _return_contents(entry):
		return false
	if session.pick_up(placement_id) == &"":
		return false
	Game.inventory.add(data, 1)
	_select(data.id)
	var host: Interior = Interior.find(Game.get_tree())
	if host != null:
		host.despawn_placement(placement_id)
	Game.post_notice("Picked up %s." % data.display_name)
	return true


static func rotate(placement_id: StringName) -> bool:
	var session: IndoorSession = Game.interior_session
	if session == null or not Game.is_decorating():
		return false
	if not session.rotate(placement_id, 1):
		return false
	var host: Interior = Interior.find(Game.get_tree())
	if host != null:
		host.refresh_placement(placement_id)
	return true


## Lay wallpaper or carpet over the room's walls or floor.
static func apply_cover(data: ItemData) -> bool:
	var session: IndoorSession = Game.interior_session
	if data == null or session == null or not Game.is_decorating():
		return false
	match data.category:
		ItemData.Category.WALL:
			if not session.decorate_wall(data.id):
				return false
			Game.post_notice("Changed the wallpaper.")
		ItemData.Category.FLOOR:
			if not session.decorate_floor(data.id):
				return false
			Game.post_notice("Changed the carpet.")
		_:
			return false
	Game.inventory.remove(data.id, 1)
	return true


## Select the pocket holding `item_id`, so a piece just picked up is in hand.
static func _select(item_id: StringName) -> void:
	var inventory: Inventory = Game.inventory
	for i: int in range(Inventory.POCKET_SLOTS - 1, -1, -1):
		var slot: InventorySlot = inventory.slot_at(i)
		if slot != null and not slot.is_empty() and slot.item.item_id == item_id:
			inventory.select(i)


static func _has_surface_items(session: IndoorSession, entry: FurniturePlacement) -> bool:
	var data: FurnitureData = session.furniture_of(entry.furniture_id)
	var size: Vector2i = entry.resolved_footprint(data)
	for cell: Vector2i in session.grid.footprint_cells(entry.cell, size, entry.facing):
		if session.surface_item_at(cell) != null:
			return true
	return false


## Move what is displayed on, or stored in, a piece into the pockets before it is lifted.
## Fails, changing nothing, if the pockets cannot hold it all.
static func _return_contents(entry: FurniturePlacement) -> bool:
	var contents: Array[ItemData] = []
	if entry.display_id != &"":
		var shown: ItemData = ItemCatalog.get_item(entry.display_id)
		if shown != null:
			contents.append(shown)
	for stored_id: String in entry.stored:
		var stored: ItemData = ItemCatalog.get_item(StringName(stored_id))
		if stored != null:
			contents.append(stored)
	for item: ItemData in contents:
		if not Game.inventory.has_space_for(item, 1):
			Game.post_notice("Pockets are full.")
			return false
	for item: ItemData in contents:
		Game.inventory.add(item, 1)
	entry.display_id = &""
	entry.stored.clear()
	return true
