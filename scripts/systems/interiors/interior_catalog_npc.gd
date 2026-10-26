class_name InteriorCatalogNpc
extends RefCounted

## NPC house room templates. Covers both the eager disc rooms (`npc_0`…`npc_14`,
## `InteriorCatalog._register_all`) and lazy per-villager rooms resolved on
## demand by `ensure_villager_room` (called from `InteriorCatalog.room_template`
## and friends).

const NPC_ROOMS_PATH := "res://assets/generated/environment/fg/npc_rooms.json"

static var _npc_layouts: Dictionary = {}
static var _npc_layouts_loaded: bool = false


static func reset_layouts() -> void:
	_npc_layouts.clear()
	_npc_layouts_loaded = false


static func register() -> void:
	for i: int in InteriorCatalog.NPC_ROOM_COUNT:
		var room_id := StringName("npc_%d" % i)
		var room := InteriorCatalog.make_room(
			room_id,
			Room.Kind.NPC,
			"House",
			InteriorCatalog.NPC_INNER_ORIGIN,
			InteriorCatalog.NPC_INNER_SIZE,
			{
				"wall": InteriorStyleCatalog.WALL_ROSE if i % 2 == 0 else InteriorStyleCatalog.WALL_GREEN,
				"floor": InteriorStyleCatalog.FLOOR_WOOD,
				## Arrange_Room draws rom_myhome2 floor/wall with carpet banks (not room01).
				"shells": PackedStringArray(["rom_myhome2_floor", "rom_myhome2_wall"]),
			}
		)
		_apply_house_door(room)
		InteriorCatalog.add_furniture_placement(room, &"wood_chair", Vector2i(3, 5), WorldGrid.Facing.SOUTH)
		InteriorCatalog.put_room(room)
		var house_id := room_id
		InteriorCatalog.put_house(house_id, &"", StringName("npc_house_%d" % i), [room_id])
		InteriorCatalog.bind_building(StringName("npc_house_%d" % i), house_id)


## Lazily builds (and caches) the room for a villager id encoded as `npc_<id>`.
## Returns null for anything else, including the eager disc rooms above (those
## are already in `InteriorCatalog`'s registry by the time this is consulted).
static func ensure_villager_room(room_id: StringName) -> Room:
	if room_id == &"":
		return null
	if InteriorCatalog.has_registered_room(room_id):
		return InteriorCatalog.room_template(room_id)
	var raw := String(room_id)
	if not raw.begins_with("npc_"):
		return null
	var villager_id := StringName(raw.substr(4))
	if villager_id == &"" or String(villager_id).is_valid_int():
		return null
	var villager: VillagerData = VillagerCatalog.get_villager(villager_id)
	if villager == null or villager.id == &"":
		return null
	var label := "%s's House" % villager.display_name
	if villager.display_name.is_empty():
		label = "House"
	var room := InteriorCatalog.make_room(
		room_id,
		Room.Kind.NPC,
		label,
		InteriorCatalog.NPC_INNER_ORIGIN,
		InteriorCatalog.NPC_INNER_SIZE,
		{
			"wall": villager.wall_style_id(),
			"floor": villager.floor_style_id(),
			## Arrange_Room draws rom_myhome2 floor/wall with carpet banks (not room01).
			"shells": PackedStringArray(["rom_myhome2_floor", "rom_myhome2_wall"]),
		}
	)
	_apply_house_door(room)
	_fill_furniture(room, villager.id)
	InteriorCatalog.put_room(room)
	InteriorCatalog.put_house(room_id, villager.id, &"", [room_id])
	InteriorCatalog.bind_building(villager.id, room_id)
	return room


static func _apply_house_door(room: Room) -> void:
	## `fgnpcdata` EXIT at (3,8)/(4,8); enter `{160,0,300}` facing north.
	if room == null:
		return
	room.door_cell = InteriorCatalog.NPC_HOUSE_DOOR_CELL
	room.spawn_cell = InteriorCatalog.NPC_HOUSE_SPAWN_CELL


static func _fill_furniture(room: Room, villager_id: StringName) -> void:
	var layout: Dictionary = _layout(villager_id)
	var placements: Array = layout.get("placements", []) as Array
	if placements.is_empty():
		InteriorCatalog.add_furniture_placement(room, &"wood_chair", Vector2i(3, 5), WorldGrid.Facing.SOUTH)
		return
	for raw: Variant in placements:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		var visual := StringName(str(entry.get("visual_id", "")))
		if visual == &"":
			continue
		var data: FurnitureData = ItemCatalog.furniture_for_visual(visual)
		if data == null:
			continue
		var size_code: int = int(entry.get("size", 0))
		## TYPEB rest is `[* -]` (`l_typeB0_table` SOUTH → extra +X), not 1×2 south.
		var footprint := Vector2i(1, 1)
		if size_code == 2:
			footprint = Vector2i(2, 2)
		elif size_code == 1:
			footprint = Vector2i(2, 1)
		var cell_raw: Variant = entry.get("cell", [1, 1])
		var cell := Vector2i(1, 1)
		if typeof(cell_raw) == TYPE_ARRAY and (cell_raw as Array).size() >= 2:
			var arr: Array = cell_raw
			cell = Vector2i(int(arr[0]), int(arr[1]))
		var facing: WorldGrid.Facing = int(entry.get("facing", 0)) as WorldGrid.Facing
		var cloth: int = int(entry.get("cloth", -1))
		if cloth < 0 and visual == &"int_fmanekin":
			cloth = FieldCatalog.cloth_index_from_item(int(entry.get("item", 0)))
		InteriorCatalog.add_furniture_placement(room, data.id, cell, facing, footprint, cloth)


static func _layout(villager_id: StringName) -> Dictionary:
	_ensure_layouts_loaded()
	if villager_id == &"":
		return {}
	return _npc_layouts.get(String(villager_id), {}) as Dictionary


static func _ensure_layouts_loaded() -> void:
	if _npc_layouts_loaded:
		return
	_npc_layouts_loaded = true
	_npc_layouts.clear()
	if not FileAccess.file_exists(NPC_ROOMS_PATH):
		return
	var file := FileAccess.open(NPC_ROOMS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var bag: Dictionary = parsed
	var villagers: Variant = bag.get("villagers", {})
	if typeof(villagers) != TYPE_DICTIONARY:
		return
	for key: Variant in (villagers as Dictionary).keys():
		_npc_layouts[str(key)] = (villagers as Dictionary)[key]
