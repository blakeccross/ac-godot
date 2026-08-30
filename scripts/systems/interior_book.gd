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
			var copy: Room = room(room_id)
			if copy != null:
				copy.apply_runtime((rooms_raw as Dictionary)[key])
	var houses_raw: Variant = bag.get("houses", {})
	if typeof(houses_raw) != TYPE_DICTIONARY:
		return
	for key: Variant in (houses_raw as Dictionary).keys():
		var house_id := StringName(str(key))
		var copy: House = house(house_id)
		if copy != null:
			copy.apply_snapshot((houses_raw as Dictionary)[key])
