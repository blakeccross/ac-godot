class_name InteriorSaveMigrations
extends RefCounted

## One-off backward-compatibility fixups applied to `Room` data loaded from
## older save files. Kept separate from `InteriorBook` so the live data
## model isn't tangled with save-format history.


static func cloth_by_id(room: Room) -> Dictionary:
	var bag := {}
	if room == null:
		return bag
	for entry: FurniturePlacement in room.placements:
		if entry != null and entry.id != &"" and entry.cloth_index >= 0:
			bag[entry.id] = entry.cloth_index
	return bag


static func cloth_by_slot(room: Room) -> Dictionary:
	var bag := {}
	if room == null:
		return bag
	for entry: FurniturePlacement in room.placements:
		if entry != null and entry.cloth_index >= 0:
			bag[_cloth_slot(entry)] = entry.cloth_index
	return bag


static func restore_missing_cloth(room: Room, by_id: Dictionary, by_slot: Dictionary) -> void:
	if room == null:
		return
	for entry: FurniturePlacement in room.placements:
		if entry == null or entry.cloth_index >= 0:
			continue
		if by_id.has(entry.id):
			entry.cloth_index = int(by_id[entry.id])
		elif by_slot.has(_cloth_slot(entry)):
			entry.cloth_index = int(by_slot[_cloth_slot(entry)])


static func migrate_player_placeholder(room: Room) -> void:
	## Older templates used cream/wood tints (no bank PNG) and a dummy chair.
	if room == null or room.kind != Room.Kind.PLAYER:
		return
	var remap_wall := room.wall_id == InteriorStyleCatalog.WALL_CREAM
	var remap_floor := room.floor_id == InteriorStyleCatalog.FLOOR_WOOD
	if remap_wall:
		room.wall_id = InteriorStyleCatalog.wall_style_id(InteriorCatalog.PLAYER_START_WALL)
	if remap_floor:
		room.floor_id = InteriorStyleCatalog.floor_style_id(InteriorCatalog.PLAYER_START_FLOOR)
	if remap_wall or remap_floor:
		var kept: Array[FurniturePlacement] = []
		for entry: FurniturePlacement in room.placements:
			if entry != null and entry.furniture_id == &"wood_chair" and entry.cell == Vector2i(6, 7):
				continue
			kept.append(entry)
		room.placements = kept
	_migrate_player_small_inner(room)
	if room.id != &"player_main" or not room.placements.is_empty():
		return
	var start_wall: StringName = InteriorStyleCatalog.wall_style_id(InteriorCatalog.PLAYER_START_WALL)
	var start_floor: StringName = InteriorStyleCatalog.floor_style_id(InteriorCatalog.PLAYER_START_FLOOR)
	if room.wall_id == start_wall and room.floor_id == start_floor:
		InteriorCatalog.fill_player_starter(room)


static func _migrate_player_small_inner(room: Room) -> void:
	## Main used to be a centered 6×6. `rom_myhome1` is the 4×4 small shell.
	if room == null or room.id != &"player_main":
		return
	if room.inner_size != InteriorCatalog.PLAYER_INNER_SIZE:
		return
	var old_origin := Vector2i(5, 5)
	var old_size := Vector2i(6, 6)
	var delta: Vector2i = room.inner_origin - old_origin
	if delta == Vector2i.ZERO:
		return
	var needs := false
	for entry: FurniturePlacement in room.placements:
		if entry == null:
			continue
		if not room.is_inner(entry.cell) and _in_rect(entry.cell, old_origin, old_size):
			needs = true
			break
	if not needs:
		return
	var kept: Array[FurniturePlacement] = []
	for entry: FurniturePlacement in room.placements:
		if entry == null:
			continue
		if _in_rect(entry.cell, old_origin, old_size):
			entry.cell += delta
		if room.is_inner(entry.cell):
			kept.append(entry)
	room.placements = kept


static func _in_rect(cell: Vector2i, origin: Vector2i, size: Vector2i) -> bool:
	return (
		cell.x >= origin.x
		and cell.y >= origin.y
		and cell.x < origin.x + size.x
		and cell.y < origin.y + size.y
	)


static func _cloth_slot(entry: FurniturePlacement) -> String:
	return "%s:%d:%d" % [String(entry.furniture_id), entry.cell.x, entry.cell.y]
