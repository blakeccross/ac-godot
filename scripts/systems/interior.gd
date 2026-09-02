class_name Interior
extends RefCounted

## Indoor occupancy on a `WorldGrid`. Place / pick / rotate / wall+floor.
## Placement rules live on `FurnitureData` (floor / table / small / wall).

var room: Room
var grid: WorldGrid = WorldGrid.new()


func bind(p_room: Room) -> void:
	room = p_room
	grid = WorldGrid.new()
	if room == null:
		grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
		return
	var cols: int = maxi(room.columns, 1)
	var rows: int = maxi(room.rows, 1)
	## Museum acre shells / door GX / mMmd_UT are absolute from NW — keep origin at 0.
	## Homes and shops stay centered so the walkable rect sits on the camera.
	var origin := (
		Vector3.ZERO
		if room.kind == Room.Kind.MUSEUM
		else Vector3(-float(cols) * grid.cell_size * 0.5, 0.0, -float(rows) * grid.cell_size * 0.5)
	)
	grid.configure(cols, rows, 2.0, origin)
	for x: int in cols:
		for z: int in rows:
			var cell := Vector2i(x, z)
			if room.is_inner(cell):
				grid.set_terrain(cell, WorldGrid.Terrain.STONE)
			else:
				grid.set_terrain(cell, WorldGrid.Terrain.BLOCKED)
	for entry: FurniturePlacement in room.placements:
		_occupy(entry)


func furniture_of(furniture_id: StringName) -> FurnitureData:
	return ItemCatalog.get_item(furniture_id) as FurnitureData


func placement_at(cell: Vector2i) -> FurniturePlacement:
	if room == null:
		return null
	var occ: StringName = grid.occupant_at(cell)
	if occ != &"":
		return room.placement_by_id(occ)
	return surface_item_at(cell)


func surface_item_at(cell: Vector2i) -> FurniturePlacement:
	if room == null:
		return null
	for entry: FurniturePlacement in room.placements:
		if entry != null and entry.layer > 0 and entry.cell == cell:
			return entry
	return null


func can_place(
	data: FurnitureData,
	cell: Vector2i,
	facing: WorldGrid.Facing,
	ignore_id: StringName = &"",
	footprint: Vector2i = Vector2i.ZERO
) -> bool:
	if room == null or data == null:
		return false
	if not data.indoor:
		return false
	var size: Vector2i = footprint if footprint != Vector2i.ZERO else data.resolved_footprint()
	if size == Vector2i.ZERO:
		return false
	var cells: Array[Vector2i] = grid.footprint_cells(cell, size, facing)
	for occupied: Vector2i in cells:
		if occupied == room.door_cell:
			return false
		if not room.is_inner(occupied):
			return false
	if data.needs_wall() and not _faces_wall(cell, facing):
		return false
	if data.needs_surface():
		var host: FurniturePlacement = _table_at(cell, ignore_id)
		if host != null:
			var stacked: FurniturePlacement = surface_item_at(cell)
			return stacked == null or stacked.id == ignore_id
	return grid.can_place(cell, size, facing, WorldGrid.PlaceKind.FURNITURE, ignore_id)


func place(
	data: FurnitureData, cell: Vector2i, facing: WorldGrid.Facing, placement_id: StringName = &""
) -> FurniturePlacement:
	if not can_place(data, cell, facing):
		return null
	var entry := FurniturePlacement.new()
	entry.id = placement_id if placement_id != &"" else room.next_placement_id()
	entry.furniture_id = data.id
	entry.cell = cell
	entry.facing = facing
	entry.footprint = data.resolved_footprint()
	entry.on = not data.starts_off
	if data.needs_surface() and _table_at(cell) != null:
		entry.layer = 1
		room.placements.append(entry)
		return entry
	if not grid.place(entry.id, cell, entry.resolved_footprint(data), facing, WorldGrid.PlaceKind.FURNITURE):
		return null
	room.placements.append(entry)
	return entry


func rotate(placement_id: StringName, steps: int = 1) -> bool:
	var entry: FurniturePlacement = room.placement_by_id(placement_id) if room else null
	if entry == null:
		return false
	var data: FurnitureData = furniture_of(entry.furniture_id)
	if data == null or not data.can_rotate:
		return false
	if entry.layer > 0:
		entry.facing = grid.rotate_facing(entry.facing, steps)
		return true
	var size: Vector2i = entry.resolved_footprint(data)
	var next_facing: WorldGrid.Facing = grid.rotate_facing(entry.facing, steps)
	if not can_place(data, entry.cell, next_facing, entry.id, size):
		return false
	grid.remove(entry.id)
	entry.facing = next_facing
	return grid.place(entry.id, entry.cell, size, next_facing, WorldGrid.PlaceKind.FURNITURE)


func pick_up(placement_id: StringName) -> StringName:
	var entry: FurniturePlacement = room.placement_by_id(placement_id) if room else null
	if entry == null:
		return &""
	if entry.layer == 0 and surface_item_at(entry.cell) != null:
		return &""
	var furniture_id: StringName = entry.furniture_id
	if entry.layer == 0:
		grid.remove(entry.id)
	room.placements.erase(entry)
	return furniture_id


func decorate_wall(wall_id: StringName) -> bool:
	if room == null or not room.can_decorate or wall_id == &"":
		return false
	if not InteriorCatalog.has_wall(wall_id):
		return false
	room.wall_id = wall_id
	return true


func decorate_floor(floor_id: StringName) -> bool:
	if room == null or not room.can_decorate or floor_id == &"":
		return false
	if not InteriorCatalog.has_floor(floor_id):
		return false
	room.floor_id = floor_id
	return true


func _occupy(entry: FurniturePlacement) -> void:
	if entry == null or entry.id == &"":
		return
	if entry.layer > 0:
		return
	var data: FurnitureData = furniture_of(entry.furniture_id)
	if data == null:
		return
	grid.place(
		entry.id, entry.cell, entry.resolved_footprint(data), entry.facing, WorldGrid.PlaceKind.FURNITURE
	)


func _table_at(cell: Vector2i, ignore_id: StringName = &"") -> FurniturePlacement:
	var host: FurniturePlacement = null
	var occ: StringName = grid.occupant_at(cell)
	if occ != &"" and occ != ignore_id:
		host = room.placement_by_id(occ) if room else null
	if host == null:
		return null
	var data: FurnitureData = furniture_of(host.furniture_id)
	if data == null or not data.allows_on_top():
		return null
	return host


func _faces_wall(cell: Vector2i, facing: WorldGrid.Facing) -> bool:
	if room == null:
		return false
	var ahead: Vector2i = grid.step(cell, facing)
	return not room.is_inner(ahead)
