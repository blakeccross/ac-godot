class_name VillagerHome
extends RefCounted

## Outdoor door checks for villager houses (`aHUS_odekake_check`).


## Empty string → door may open. Otherwise a notice for the player.
static func door_notice(occupant_or_entry: StringName) -> String:
	var villager_id: StringName = _resolve_villager(occupant_or_entry)
	if villager_id == &"":
		return ""
	var data: VillagerData = VillagerCatalog.get_villager(villager_id)
	if data == null:
		return ""
	var state: VillagerState = Game.villagers.get_or_create(villager_id)
	var activity: StringName = _activity_now(data)
	if not state.is_home:
		return "%s isn't home right now." % _name(data)
	if activity == VillagerActivity.SLEEP:
		return "%s is sleeping." % _name(data)
	## Awake at home (IN_HOUSE) — enter.
	return ""


static func can_enter(occupant_or_entry: StringName) -> bool:
	return door_notice(occupant_or_entry) == ""


static func should_spawn_indoor(occupant_id: StringName) -> bool:
	## Indoor `ac_npc2`: visible when home and not SLEEP.
	if occupant_id == &"":
		return false
	var data: VillagerData = VillagerCatalog.get_villager(occupant_id)
	if data == null:
		return false
	var state: VillagerState = Game.villagers.get_or_create(occupant_id)
	if not state.is_home:
		return false
	return _activity_now(data) != VillagerActivity.SLEEP


static func indoor_stand(session: Interior) -> Vector3:
	## Into-room stand near mid walkable (`aNPC_think_into_room` ~160,360 GX).
	if session == null or session.grid == null or session.room == null:
		return Vector3(8.0, 0.0, 10.0)
	var room: Room = session.room
	var cell := Vector2i(
		room.inner_origin.x + maxi(room.inner_size.x / 2, 1),
		room.inner_origin.y + maxi(room.inner_size.y / 2, 1)
	)
	return session.grid.cell_to_world(cell)


static func _resolve_villager(entry: StringName) -> StringName:
	if entry == &"":
		return &""
	if VillagerCatalog.get_villager(entry) != null:
		return entry
	var room_id: StringName = InteriorCatalog.resolve_entry(entry)
	if room_id == &"":
		return &""
	var raw := String(room_id)
	if raw.begins_with("npc_"):
		var id := StringName(raw.substr(4))
		if VillagerCatalog.get_villager(id) != null:
			return id
	var house: House = InteriorCatalog.house_template(room_id)
	if house != null and house.occupant_id != &"":
		return house.occupant_id
	house = InteriorCatalog.house_template(InteriorCatalog.house_for_building(entry))
	if house != null:
		return house.occupant_id
	return &""


static func _activity_now(data: VillagerData) -> StringName:
	if data == null:
		return VillagerActivity.FIELD
	var table: ScheduleData = data.schedule_table()
	if table == null:
		return VillagerActivity.FIELD
	return table.activity_now()


static func _name(data: VillagerData) -> String:
	if data != null and data.display_name != "":
		return data.display_name
	return "They"
