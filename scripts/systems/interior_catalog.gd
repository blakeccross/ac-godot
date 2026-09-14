class_name InteriorCatalog
extends RefCounted

## Every indoor field id (`mFI_FIELD_ROOM_*`, NPC rooms, player rooms). Templates
## only — runtime furniture lives on `InteriorBook`. Wall/floor style resolution
## lives on `InteriorStyleCatalog`.
##
## Registration is split by building family — `InteriorCatalogPlayer`,
## `InteriorCatalogNpc`, `InteriorCatalogShops`, `InteriorCatalogPublic`,
## `InteriorCatalogMuseum` — each calling the authoring API below
## (`make_room`, `put_room`, `put_house`, `bind_building`, ...).

const NPC_ROOM_COUNT := 15
const PLAYER_HOUSE_ID := &"player"
const CELL_SIZE := 2.0
## Disc NPC rooms occupy the NW 8×8 of the 16×16 FG grid (`fgnpcdata.bin`).
const NPC_INNER_ORIGIN := Vector2i(1, 1)
const NPC_INNER_SIZE := Vector2i(6, 6)
## `fgnpcdata` EXIT_DOOR pair + `aHUS_npc_house_door_data` enter stand.
const NPC_HOUSE_DOOR_CELL := Vector2i(3, 8)
const NPC_HOUSE_SPAWN_CELL := Vector2i(3, 7)
const NPC_HOUSE_SPAWN_GX := Vector3(160.0, 0.0, 300.0)
## Able Sisters outdoor enter (`aNW_needlework_shop_door_data`): same stand / NORTH.
## `aNW_needlework_shop_door_data` GX {160,0,300}, orient 4 (north) — you enter AND
## leave at the door. `rom_tailor.col.json` (16×16 units @ 40 GX) puts this on the
## porch cell (4,7); `block_auto_enter_doors` keeps you from re-exiting until you
## step off it into the shop.
const ABLE_SPAWN_GX := Vector3(160.0, 0.0, 300.0)
const ABLE_SPAWN_FACING := WorldGrid.Facing.NORTH
## Small player main (`l_proom_s_tmp`, `rom_myhome1_*`): 4×4 walkable, same NW origin.
const PLAYER_INNER_ORIGIN := Vector2i(1, 1)
const PLAYER_INNER_SIZE := Vector2i(4, 4)
## `l_proom_s_tmp` EXIT_DOOR + `aMHS_goto_next_pl_scene` startX/Z[HOMESIZE_S].
const PLAYER_SMALL_DOOR_CELL := Vector2i(2, 7)
const PLAYER_SMALL_SPAWN_CELL := Vector2i(2, 5)
const PLAYER_SMALL_SPAWN_GX := Vector3(120.0, 0.0, 220.0)
## `l_mHm_player_room_default_data[0]`: stone wall & old flooring.
const PLAYER_START_WALL := 3
const PLAYER_START_FLOOR := 38

static var _rooms: Dictionary = {}
static var _houses: Dictionary = {}
static var _building_to_house: Dictionary = {}
static var _loaded: bool = false
## room_id → authored `.tscn` (Shell / Terrain / Furniture / Doors). Empty → InteriorBuilder.
static var _scene_paths: Dictionary = {}


static func reset() -> void:
	_rooms.clear()
	_houses.clear()
	_building_to_house.clear()
	_scene_paths.clear()
	_loaded = false
	InteriorCatalogNpc.reset_layouts()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_rooms.clear()
	_houses.clear()
	_building_to_house.clear()
	_scene_paths.clear()
	_register_all()
	_loaded = true


static func room_ids() -> Array[StringName]:
	ensure_loaded()
	var out: Array[StringName] = []
	for key: Variant in _rooms.keys():
		out.append(key as StringName)
	out.sort()
	return out


static func house_ids() -> Array[StringName]:
	ensure_loaded()
	var out: Array[StringName] = []
	for key: Variant in _houses.keys():
		out.append(key as StringName)
	out.sort()
	return out


static func has_room(room_id: StringName) -> bool:
	ensure_loaded()
	if _rooms.has(room_id):
		return true
	return InteriorCatalogNpc.ensure_villager_room(room_id) != null


## Eager-registry check only — no lazy villager-room fallback. Lets
## `InteriorCatalogNpc.ensure_villager_room` probe the cache without recursing.
static func has_registered_room(room_id: StringName) -> bool:
	ensure_loaded()
	return _rooms.has(room_id)


static func room_template(room_id: StringName) -> Room:
	ensure_loaded()
	if room_id == &"":
		return null
	if _rooms.has(room_id):
		return _rooms[room_id] as Room
	return InteriorCatalogNpc.ensure_villager_room(room_id)


static func house_template(house_id: StringName) -> House:
	ensure_loaded()
	if house_id == &"":
		return null
	if _houses.has(house_id):
		return _houses[house_id] as House
	InteriorCatalogNpc.ensure_villager_room(house_id)
	return _houses.get(house_id) as House


static func house_for_building(building_id: StringName) -> StringName:
	ensure_loaded()
	if building_id == &"":
		return &""
	if _building_to_house.has(building_id):
		return _building_to_house[building_id] as StringName
	var raw := String(building_id)
	if raw.begins_with("npc_house_"):
		var house_id := StringName("npc_%s" % raw.substr(String("npc_house_").length()))
		if _houses.has(house_id):
			return house_id
	if _houses.has(building_id):
		return building_id
	return &""


static func npc_room_id(villager_id: StringName) -> StringName:
	if villager_id == &"":
		return &""
	return StringName("npc_%s" % String(villager_id))


static func resolve_entry(target: StringName) -> StringName:
	ensure_loaded()
	if target == &"":
		return &""
	if _rooms.has(target) or InteriorCatalogNpc.ensure_villager_room(target) != null:
		return target
	var npc_room: StringName = npc_room_id(target)
	if _rooms.has(npc_room) or InteriorCatalogNpc.ensure_villager_room(npc_room) != null:
		return npc_room
	var house_id: StringName = house_for_building(target)
	if house_id == &"":
		return &""
	## Nook outdoor enter uses current upgrade room (`shop0`…`shop3_1`).
	if house_id == &"shop":
		return nook_entry_room()
	var house: House = _houses[house_id] as House
	if house == null:
		return &""
	return house.entry_room_id()


static func nook_entry_room() -> StringName:
	if Game != null and Game.shops != null:
		return Game.shops.nook_room_id()
	return &"shop0"


static func scene_path(room_id: StringName) -> String:
	ensure_loaded()
	if room_id == &"":
		return ""
	return str(_scene_paths.get(room_id, ""))


static func has_authored_scene(room_id: StringName) -> bool:
	var path: String = scene_path(room_id)
	return path != "" and ResourceLoader.exists(path)


static func is_open_now(room: Room) -> bool:
	if room == null or room.is_always_open():
		return true
	return Clock.in_hour_window(room.open_hour, room.close_hour)


static func closed_notice(room: Room) -> String:
	if room == null:
		return "It's locked."
	match room.kind:
		Room.Kind.SHOP, Room.Kind.BROKER, Room.Kind.NEEDLEWORK:
			return "The shop is closed."
		Room.Kind.MUSEUM:
			return "The museum is closed."
		Room.Kind.POST_OFFICE:
			return "The post office is closed."
		_:
			return "It's locked."


static func _register_all() -> void:
	InteriorCatalogPlayer.register()
	InteriorCatalogNpc.register()
	InteriorCatalogShops.register()
	InteriorCatalogPublic.register()
	InteriorCatalogMuseum.register()
	_register_scene_paths()
	bind_building(&"player_house", PLAYER_HOUSE_ID)
	bind_building(&"player_house_1", PLAYER_HOUSE_ID)
	bind_building(&"player_house_2", PLAYER_HOUSE_ID)
	bind_building(&"player_house_3", PLAYER_HOUSE_ID)
	bind_building(&"house_door", PLAYER_HOUSE_ID)
	bind_building(&"acre_shop", &"shop")
	bind_building(&"museum", &"museum")
	bind_building(&"able_sisters", &"needlework")
	bind_building(&"post_office", &"post_office")
	bind_building(&"police", &"police_box")


static func _register_scene_paths() -> void:
	## Authored indoor layouts under `scenes/world/interiors/` (+ museum wings).
	var interiors := "res://scenes/world/interiors/"
	var museum := "res://scenes/world/museum/"
	_scene_paths[&"shop0"] = interiors + "shop0.tscn"
	_scene_paths[&"shop1"] = interiors + "shop1.tscn"
	_scene_paths[&"shop2"] = interiors + "shop2.tscn"
	_scene_paths[&"shop3_1"] = interiors + "shop3_1.tscn"
	_scene_paths[&"shop3_2"] = interiors + "shop3_2.tscn"
	_scene_paths[&"needlework"] = interiors + "needlework.tscn"
	_scene_paths[&"police_box"] = interiors + "police_box.tscn"
	_scene_paths[&"post_office"] = interiors + "post_office.tscn"
	_scene_paths[&"museum_entrance"] = museum + "museum_entrance.tscn"
	_scene_paths[&"museum_painting"] = museum + "museum_painting.tscn"
	_scene_paths[&"museum_fossil"] = museum + "museum_fossil.tscn"
	_scene_paths[&"museum_insect"] = museum + "museum_insect.tscn"
	_scene_paths[&"museum_fish"] = museum + "museum_fish.tscn"


## --- Authoring API used by the `InteriorCatalog*` registrar classes ---

static func make_public_room(
	id: StringName,
	kind: Room.Kind,
	display: String,
	origin: Vector2i,
	size: Vector2i,
	open_hour: int,
	close_hour: int
) -> Room:
	return make_room(
		id,
		kind,
		display,
		origin,
		size,
		{"open": open_hour, "close": close_hour}
	)


static func make_room(
	id: StringName,
	kind: Room.Kind,
	display: String,
	origin: Vector2i,
	size: Vector2i,
	opts: Dictionary
) -> Room:
	var room := Room.new()
	room.id = id
	room.kind = kind
	room.display_name = display
	room.columns = 16
	room.rows = 16
	room.inner_origin = origin
	room.inner_size = size
	var door_x: int = origin.x + int(size.x / 2)
	var door_z: int = origin.y + size.y - 1
	room.door_cell = Vector2i(door_x, door_z)
	room.spawn_cell = Vector2i(door_x, door_z - 1)
	room.can_decorate = bool(opts.get("decorate", false))
	room.wall_id = opts.get("wall", InteriorStyleCatalog.WALL_DEFAULT) as StringName
	room.floor_id = opts.get("floor", InteriorStyleCatalog.FLOOR_DEFAULT) as StringName
	if opts.has("shells"):
		var shells: Variant = opts["shells"]
		if shells is PackedStringArray:
			room.shell_ids = (shells as PackedStringArray).duplicate()
		elif typeof(shells) == TYPE_ARRAY:
			for entry: Variant in shells as Array:
				room.shell_ids.append(str(entry))
	room.open_hour = int(opts.get("open", -1))
	room.close_hour = int(opts.get("close", -1))
	if opts.has("parent"):
		room.parent_room_id = opts["parent"] as StringName
	return room


static func fill_player_starter(room: Room) -> void:
	## `mHm_SetDefaultPlayerRoomData`: orange crate at (1,1), cassette at (4,1).
	if room == null or not room.placements.is_empty():
		return
	var origin: Vector2i = room.inner_origin
	var crate: FurnitureData = ItemCatalog.furniture_for_visual(&"int_nog_mikanbox")
	if crate != null:
		add_furniture_placement(room, crate.id, origin, WorldGrid.Facing.SOUTH)
	var tape: FurnitureData = ItemCatalog.furniture_for_visual(&"int_sum_casse01")
	if tape != null:
		add_furniture_placement(room, tape.id, origin + Vector2i(3, 0), WorldGrid.Facing.SOUTH)


static func add_furniture_placement(
	room: Room,
	furniture_id: StringName,
	cell: Vector2i,
	facing: WorldGrid.Facing,
	footprint: Vector2i = Vector2i.ZERO,
	cloth_index: int = -1
) -> void:
	var entry := FurniturePlacement.new()
	entry.id = room.next_placement_id()
	entry.furniture_id = furniture_id
	entry.cell = cell
	entry.facing = facing
	entry.footprint = footprint
	entry.cloth_index = cloth_index
	room.placements.append(entry)


static func put_room(room: Room) -> void:
	_rooms[room.id] = room


static func put_house(
	id: StringName, occupant: StringName, outdoor: StringName, rooms: Array
) -> void:
	var house := House.new()
	house.id = id
	house.occupant_id = occupant
	house.outdoor_building_id = outdoor
	for room_id: Variant in rooms:
		house.rooms.append(room_id as StringName)
	_houses[id] = house


static func bind_building(building_id: StringName, house_id: StringName) -> void:
	_building_to_house[building_id] = house_id
