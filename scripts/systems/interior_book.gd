class_name InteriorBook
extends RefCounted

## Runtime rooms and houses. Owned by `Game`, not an autoload.

var _rooms: Dictionary = {}
var _houses: Dictionary = {}


func clear() -> void:
	_rooms.clear()
	_houses.clear()


func room(room_id: StringName) -> Room:
	if room_id == &"":
		return null
	if _rooms.has(room_id):
		return _rooms[room_id] as Room
	var template: Room = InteriorCatalog.room_template(room_id)
	if template == null:
		return null
	var copy: Room = template.duplicate(true) as Room
	copy.placements = _dup_placements(template.placements)
	_rooms[room_id] = copy
	return copy


func house(house_id: StringName) -> House:
	if house_id == &"":
		return null
	if _houses.has(house_id):
		return _houses[house_id] as House
	var template: House = InteriorCatalog.house_template(house_id)
	if template == null:
		return null
	var copy: House = template.duplicate(true) as House
	_houses[house_id] = copy
	return copy


func to_save() -> Dictionary:
	var rooms_out := {}
	for key: Variant in _rooms.keys():
		var entry: Room = _rooms[key] as Room
		if entry == null or entry.id == &"":
			continue
		rooms_out[String(entry.id)] = entry.to_save()
	var houses_out := {}
	for key: Variant in _houses.keys():
		var building: House = _houses[key] as House
		if building == null or building.id == &"":
			continue
		houses_out[String(building.id)] = building.to_save()
	return {"rooms": rooms_out, "houses": houses_out}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var bag: Dictionary = data
	var rooms_raw: Variant = bag.get("rooms", {})
	if typeof(rooms_raw) == TYPE_DICTIONARY:
		for key: Variant in (rooms_raw as Dictionary).keys():
			var room_id := StringName(str(key))
			var template: Room = InteriorCatalog.room_template(room_id)
			var cloth_by_id: Dictionary = _cloth_by_id(template)
			var cloth_by_slot: Dictionary = _cloth_by_slot(template)
			var copy: Room = room(room_id)
			if copy == null:
				continue
			copy.apply_runtime((rooms_raw as Dictionary)[key])
			_restore_missing_cloth(copy, cloth_by_id, cloth_by_slot)
			_migrate_player_placeholder(copy)
	var houses_raw: Variant = bag.get("houses", {})
	if typeof(houses_raw) != TYPE_DICTIONARY:
		return
	for key: Variant in (houses_raw as Dictionary).keys():
		var house_id := StringName(str(key))
		var copy: House = house(house_id)
		if copy != null:
			copy.apply_snapshot((houses_raw as Dictionary)[key])


func _dup_placements(src: Array[FurniturePlacement]) -> Array[FurniturePlacement]:
	var out: Array[FurniturePlacement] = []
	for entry: FurniturePlacement in src:
		if entry == null:
			continue
		out.append(entry.duplicate(true) as FurniturePlacement)
	return out


func _cloth_by_id(room: Room) -> Dictionary:
	var bag := {}
	if room == null:
		return bag
	for entry: FurniturePlacement in room.placements:
		if entry != null and entry.id != &"" and entry.cloth_index >= 0:
			bag[entry.id] = entry.cloth_index
	return bag


func _cloth_by_slot(room: Room) -> Dictionary:
	var bag := {}
	if room == null:
		return bag
	for entry: FurniturePlacement in room.placements:
		if entry != null and entry.cloth_index >= 0:
			bag[_cloth_slot(entry)] = entry.cloth_index
	return bag


func _migrate_player_placeholder(room: Room) -> void:
	## Older templates used cream/wood tints (no bank PNG) and a dummy chair.
	if room == null or room.kind != Room.Kind.PLAYER:
		return
	var remap_wall := room.wall_id == InteriorCatalog.WALL_CREAM
	var remap_floor := room.floor_id == InteriorCatalog.FLOOR_WOOD
	if remap_wall:
		room.wall_id = InteriorCatalog.wall_style_id(InteriorCatalog.PLAYER_START_WALL)
	if remap_floor:
		room.floor_id = InteriorCatalog.floor_style_id(InteriorCatalog.PLAYER_START_FLOOR)
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
	var start_wall: StringName = InteriorCatalog.wall_style_id(InteriorCatalog.PLAYER_START_WALL)
	var start_floor: StringName = InteriorCatalog.floor_style_id(InteriorCatalog.PLAYER_START_FLOOR)
	if room.wall_id == start_wall and room.floor_id == start_floor:
		InteriorCatalog._fill_player_starter(room)


func _migrate_player_small_inner(room: Room) -> void:
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


func _in_rect(cell: Vector2i, origin: Vector2i, size: Vector2i) -> bool:
	return (
		cell.x >= origin.x
		and cell.y >= origin.y
		and cell.x < origin.x + size.x
		and cell.y < origin.y + size.y
	)


func _restore_missing_cloth(room: Room, by_id: Dictionary, by_slot: Dictionary) -> void:
	if room == null:
		return
	for entry: FurniturePlacement in room.placements:
		if entry == null or entry.cloth_index >= 0:
			continue
		if by_id.has(entry.id):
			entry.cloth_index = int(by_id[entry.id])
		elif by_slot.has(_cloth_slot(entry)):
			entry.cloth_index = int(by_slot[_cloth_slot(entry)])


func _cloth_slot(entry: FurniturePlacement) -> String:
	return "%s:%d:%d" % [String(entry.furniture_id), entry.cell.x, entry.cell.y]
