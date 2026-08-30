class_name House
extends Resource

## A building's indoor rooms. Player size tiers follow `mHm_HOMESIZE_*`;
## NPC and public buildings are one (or linked) rooms, not player loan upgrades.

enum SizeTier { SMALL, MEDIUM, LARGE, UPPER, STATUE }

@export var id: StringName = &""
@export var occupant_id: StringName = &""
@export var outdoor_building_id: StringName = &""
@export var rooms: Array[StringName] = []
@export var size_tier: SizeTier = SizeTier.SMALL


func entry_room_id() -> StringName:
	if rooms.is_empty():
		return &""
	return rooms[0]


func to_save() -> Dictionary:
	var ids: Array = []
	for room_id: StringName in rooms:
		ids.append(String(room_id))
	return {
		"id": String(id),
		"occupant_id": String(occupant_id),
		"outdoor_building_id": String(outdoor_building_id),
		"rooms": ids,
		"size_tier": int(size_tier),
	}


func apply_snapshot(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var bag: Dictionary = data
	id = StringName(str(bag.get("id", String(id))))
	occupant_id = StringName(str(bag.get("occupant_id", String(occupant_id))))
	outdoor_building_id = StringName(
		str(bag.get("outdoor_building_id", String(outdoor_building_id)))
	)
	size_tier = int(bag.get("size_tier", int(size_tier))) as SizeTier
	var ids: Variant = bag.get("rooms", [])
	if typeof(ids) != TYPE_ARRAY:
		return
	rooms.clear()
	for entry: Variant in ids:
		var room_id := StringName(str(entry))
		if room_id != &"":
			rooms.append(room_id)
