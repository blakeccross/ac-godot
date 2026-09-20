class_name IndoorSession
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


## Furniture limit for this room (0 = none). Only the player's floors are capped.
func capacity() -> int:
	if room == null or not PlayerHouse.is_player_room(room.id):
		return 0
	var house: House = Game.interiors.player_house() if Game != null and Game.interiors != null else null
	return PlayerHouse.furniture_cap(room.id, house)


func is_full() -> bool:
	var cap: int = capacity()
	return cap > 0 and room.placements.size() >= cap


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
		if room.is_exit_cell(occupied):
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
	if is_full() or not can_place(data, cell, facing):
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


## Slide a floor piece by whole cells (`aMR_PlacePush/PullFurniture`). Everything resting on it
## rides along (`aMR_RequestItemToFitFurniture`). False when a target cell is blocked.
func move_placement(placement_id: StringName, delta: Vector2i) -> bool:
	var entry: FurniturePlacement = room.placement_by_id(placement_id) if room else null
	if entry == null or entry.layer > 0 or delta == Vector2i.ZERO:
		return false
	var data: FurnitureData = furniture_of(entry.furniture_id)
	if data == null or data.placement == FurnitureData.Placement.WALL:
		return false
	var size: Vector2i = entry.resolved_footprint(data)
	var next_cell: Vector2i = entry.cell + delta
	if not can_place(data, next_cell, entry.facing, entry.id, size):
		return false
	var riders: Array[FurniturePlacement] = _riders_of(entry, data)
	grid.remove(entry.id)
	entry.cell = next_cell
	if not grid.place(entry.id, entry.cell, size, entry.facing, WorldGrid.PlaceKind.FURNITURE):
		entry.cell -= delta
		grid.place(entry.id, entry.cell, size, entry.facing, WorldGrid.PlaceKind.FURNITURE)
		return false
	for rider: FurniturePlacement in riders:
		rider.cell += delta
	return true


## Turn a floor piece 90° about `pivot` (the end the player is holding). `steps` +1 is a left
## (counter-clockwise) turn. Multi-cell pieces swing through the two cells beside the pivot
## (`rotate_forbid_table`); `blocked_cell` is the player's cell. 1×1 and 2×2 pieces spin in place.
func rotate_about(
	placement_id: StringName, steps: int, pivot: Vector2i, blocked_cell: Vector2i = NO_CELL
) -> bool:
	var entry: FurniturePlacement = room.placement_by_id(placement_id) if room else null
	if entry == null or entry.layer > 0 or steps == 0:
		return false
	var data: FurnitureData = furniture_of(entry.furniture_id)
	if data == null or not data.can_rotate or data.placement == FurnitureData.Placement.WALL:
		return false
	var size: Vector2i = entry.resolved_footprint(data)
	var old_cells: Array[Vector2i] = grid.footprint_cells(entry.cell, size, entry.facing)
	if not old_cells.has(pivot):
		pivot = entry.cell
	var next_facing: WorldGrid.Facing = grid.rotate_facing(entry.facing, steps)
	var quarter: WorldGrid.Facing = grid.rotate_facing(WorldGrid.Facing.SOUTH, steps)
	var next_anchor: Vector2i = entry.cell
	var in_place: bool = old_cells.size() == 1 or (size.x == 2 and size.y == 2)
	if in_place:
		if data.check_rotation and _friction_blocked(entry, old_cells):
			return false
	else:
		var target: Array[Vector2i] = []
		var sweep: Array[Vector2i] = []
		for cell: Vector2i in old_cells:
			var turned: Vector2i = pivot + grid.rotate_offset(cell - pivot, quarter)
			target.append(turned)
			if cell != pivot:
				sweep.append(turned)
				sweep.append(cell + turned - pivot)
		for cell: Vector2i in sweep:
			if old_cells.has(cell):
				continue
			if not _sweep_cell_free(cell, entry.id, blocked_cell):
				return false
		var found: bool = false
		target.sort()
		for candidate: Vector2i in target:
			var cells: Array[Vector2i] = grid.footprint_cells(candidate, size, next_facing)
			cells.sort()
			if cells == target:
				next_anchor = candidate
				found = true
				break
		if not found:
			return false
		if data.check_rotation and _friction_blocked(entry, old_cells):
			return false
	var riders: Array[FurniturePlacement] = _riders_of(entry, data)
	var rider_cells: Array[Vector2i] = []
	for rider: FurniturePlacement in riders:
		rider_cells.append(pivot + grid.rotate_offset(rider.cell - pivot, quarter) if not in_place else rider.cell)
	grid.remove(entry.id)
	entry.cell = next_anchor
	entry.facing = next_facing
	if not grid.place(entry.id, entry.cell, size, entry.facing, WorldGrid.PlaceKind.FURNITURE):
		return false
	for i: int in riders.size():
		riders[i].cell = rider_cells[i]
		riders[i].facing = grid.rotate_facing(riders[i].facing, steps)
	return true


const NO_CELL := Vector2i(-99, -99)


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
	if not InteriorStyleCatalog.has_wall(wall_id):
		return false
	room.wall_id = wall_id
	return true


func decorate_floor(floor_id: StringName) -> bool:
	if room == null or not room.can_decorate or floor_id == &"":
		return false
	if not InteriorStyleCatalog.has_floor(floor_id):
		return false
	room.floor_id = floor_id
	return true


## Small pieces resting on a table's cells (`layer > 0`).
func _riders_of(entry: FurniturePlacement, data: FurnitureData) -> Array[FurniturePlacement]:
	var out: Array[FurniturePlacement] = []
	if room == null:
		return out
	var cells: Array[Vector2i] = grid.footprint_cells(entry.cell, entry.resolved_footprint(data), entry.facing)
	for other: FurniturePlacement in room.placements:
		if other != null and other.layer > 0 and cells.has(other.cell):
			out.append(other)
	return out


func _sweep_cell_free(cell: Vector2i, ignore_id: StringName, blocked_cell: Vector2i) -> bool:
	if cell == blocked_cell or not room.is_inner(cell) or room.is_exit_cell(cell):
		return false
	var who: StringName = grid.occupant_at(cell)
	return who == &"" or who == ignore_id


## `aMR_SearchNextSituation`: two touching pieces that both `check_rotation` jam each other.
func _friction_blocked(entry: FurniturePlacement, cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in cells:
		for offset: Vector2i in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]:
			var near: Vector2i = cell + offset
			if cells.has(near):
				continue
			var who: StringName = grid.occupant_at(near)
			if who == &"" or who == entry.id:
				continue
			var other: FurniturePlacement = room.placement_by_id(who)
			var other_data: FurnitureData = furniture_of(other.furniture_id) if other != null else null
			if other_data != null and other_data.check_rotation:
				return true
	return false


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
