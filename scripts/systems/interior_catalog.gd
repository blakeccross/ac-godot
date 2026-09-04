class_name InteriorCatalog
extends RefCounted

## Every indoor field id (`mFI_FIELD_ROOM_*`, NPC rooms, player rooms). Templates
## only — runtime furniture lives on `InteriorBook`.

const NPC_ROOM_COUNT := 15
const PLAYER_HOUSE_ID := &"player"
const CELL_SIZE := 2.0
const WALL_BANK_COUNT := 71
const FLOOR_BANK_COUNT := 71
const ROOM_TEX_ROOT := "res://assets/generated/textures/rooms/"
const NPC_ROOMS_PATH := "res://assets/generated/environment/fg/npc_rooms.json"
## Disc NPC rooms occupy the NW 8×8 of the 16×16 FG grid (`fgnpcdata.bin`).
const NPC_INNER_ORIGIN := Vector2i(1, 1)
const NPC_INNER_SIZE := Vector2i(6, 6)
## `fgnpcdata` EXIT_DOOR pair + `aHUS_npc_house_door_data` enter stand.
const NPC_HOUSE_DOOR_CELL := Vector2i(3, 8)
const NPC_HOUSE_SPAWN_CELL := Vector2i(3, 7)
const NPC_HOUSE_SPAWN_GX := Vector3(160.0, 0.0, 300.0)
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

const WALL_DEFAULT := &"wall_default"
const WALL_BLUE := &"wall_blue"
const WALL_GREEN := &"wall_green"
const WALL_ROSE := &"wall_rose"
const WALL_CREAM := &"wall_cream"
const FLOOR_DEFAULT := &"floor_default"
const FLOOR_WOOD := &"floor_wood"
const FLOOR_TILE := &"floor_tile"
const FLOOR_STONE := &"floor_stone"

static var _rooms: Dictionary = {}
static var _houses: Dictionary = {}
static var _building_to_house: Dictionary = {}
static var _npc_layouts: Dictionary = {}
static var _npc_layouts_loaded: bool = false
static var _loaded: bool = false
## room_id → authored `.tscn` (Shell / Terrain / Furniture / Doors). Empty → InteriorBuilder.
static var _scene_paths: Dictionary = {}


static func reset() -> void:
	_rooms.clear()
	_houses.clear()
	_building_to_house.clear()
	_npc_layouts.clear()
	_npc_layouts_loaded = false
	_scene_paths.clear()
	_loaded = false


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
	return _ensure_villager_room(room_id) != null


static func room_template(room_id: StringName) -> Room:
	ensure_loaded()
	if room_id == &"":
		return null
	if _rooms.has(room_id):
		return _rooms[room_id] as Room
	return _ensure_villager_room(room_id)


static func house_template(house_id: StringName) -> House:
	ensure_loaded()
	if house_id == &"":
		return null
	if _houses.has(house_id):
		return _houses[house_id] as House
	_ensure_villager_room(house_id)
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
	if _rooms.has(target) or _ensure_villager_room(target) != null:
		return target
	var npc_room: StringName = npc_room_id(target)
	if _rooms.has(npc_room) or _ensure_villager_room(npc_room) != null:
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


static func has_wall(wall_id: StringName) -> bool:
	return wall_color(wall_id) != Color(0, 0, 0, 0)


static func has_floor(floor_id: StringName) -> bool:
	return floor_color(floor_id) != Color(0, 0, 0, 0)


static func wall_style_id(index: int) -> StringName:
	return StringName("wall_%02d" % clampi(index, 0, WALL_BANK_COUNT - 1))


static func floor_style_id(index: int) -> StringName:
	return StringName("floor_%02d" % clampi(index, 0, FLOOR_BANK_COUNT - 1))


static func style_index(style_id: StringName, prefix: String) -> int:
	var raw := String(style_id)
	if not raw.begins_with(prefix):
		return -1
	var rest := raw.substr(prefix.length())
	if not rest.is_valid_int():
		return -1
	return rest.to_int()


static func wall_texture_path(wall_id: StringName, page: int = 0) -> String:
	var idx: int = style_index(wall_id, "wall_")
	if idx < 0 or idx >= WALL_BANK_COUNT:
		return ""
	var path := "%swall/wall_%02d_%d.png" % [ROOM_TEX_ROOT, idx, clampi(page, 0, 1)]
	if ResourceLoader.exists(path):
		return path
	path = "%swall/wall_%02d_0.png" % [ROOM_TEX_ROOT, idx]
	return path if ResourceLoader.exists(path) else ""


static func floor_texture_path(floor_id: StringName, page: int = 0) -> String:
	var idx: int = style_index(floor_id, "floor_")
	if idx < 0 or idx >= FLOOR_BANK_COUNT:
		return ""
	var path := "%sfloor/floor_%02d_%d.png" % [ROOM_TEX_ROOT, idx, clampi(page, 0, 3)]
	if ResourceLoader.exists(path):
		return path
	path = "%sfloor/floor_%02d_0.png" % [ROOM_TEX_ROOT, idx]
	return path if ResourceLoader.exists(path) else ""


static func wall_color(wall_id: StringName) -> Color:
	match wall_id:
		WALL_BLUE:
			return Color(0.52, 0.68, 0.84)
		WALL_GREEN:
			return Color(0.55, 0.72, 0.58)
		WALL_ROSE:
			return Color(0.82, 0.58, 0.62)
		WALL_CREAM:
			return Color(0.9, 0.84, 0.72)
		WALL_DEFAULT:
			return Color(0.86, 0.8, 0.7)
		_:
			var idx: int = style_index(wall_id, "wall_")
			if idx < 0:
				return Color(0, 0, 0, 0)
			return Color.from_hsv(fmod(float(idx) * 0.13, 1.0), 0.22, 0.86)


static func floor_color(floor_id: StringName) -> Color:
	match floor_id:
		FLOOR_WOOD:
			return Color(0.62, 0.44, 0.28)
		FLOOR_TILE:
			return Color(0.78, 0.76, 0.72)
		FLOOR_STONE:
			return Color(0.58, 0.58, 0.6)
		FLOOR_DEFAULT:
			return Color(0.72, 0.62, 0.48)
		_:
			var idx: int = style_index(floor_id, "floor_")
			if idx < 0:
				return Color(0, 0, 0, 0)
			return Color.from_hsv(fmod(float(idx) * 0.17 + 0.08, 1.0), 0.35, 0.62)


static func _register_all() -> void:
	_register_player()
	_register_npc()
	_register_shops()
	_register_public()
	_register_museum()
	_register_scene_paths()
	_bind(&"player_house", PLAYER_HOUSE_ID)
	_bind(&"player_house_1", PLAYER_HOUSE_ID)
	_bind(&"player_house_2", PLAYER_HOUSE_ID)
	_bind(&"player_house_3", PLAYER_HOUSE_ID)
	_bind(&"house_door", PLAYER_HOUSE_ID)
	_bind(&"acre_shop", &"shop")
	_bind(&"museum", &"museum")
	_bind(&"able_sisters", &"needlework")
	_bind(&"post_office", &"post_office")
	_bind(&"police", &"police_box")


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


static func _register_player() -> void:
	var main := _make(
		&"player_main",
		Room.Kind.PLAYER,
		"Living Room",
		PLAYER_INNER_ORIGIN,
		PLAYER_INNER_SIZE,
		{
			"decorate": true,
			"wall": wall_style_id(PLAYER_START_WALL),
			"floor": floor_style_id(PLAYER_START_FLOOR),
			"shells": PackedStringArray(["rom_myhome1_floor", "rom_myhome1_wall"]),
		}
	)
	_apply_player_small_door(main)
	_fill_player_starter(main)
	_put_room(main)
	_put_room(
		_make(
			&"player_upper",
			Room.Kind.PLAYER,
			"Upstairs",
			Vector2i(5, 5),
			Vector2i(6, 6),
			{
				"decorate": true,
				"wall": wall_style_id(PLAYER_START_WALL),
				"floor": floor_style_id(PLAYER_START_FLOOR),
				"parent": &"player_main",
				"shells": PackedStringArray(["rom_myhome2_floor", "rom_myhome2_wall"]),
			}
		)
	)
	_put_room(
		_make(
			&"player_basement",
			Room.Kind.PLAYER,
			"Basement",
			Vector2i(4, 4),
			Vector2i(8, 8),
			{"decorate": true, "wall": WALL_DEFAULT, "floor": FLOOR_STONE, "parent": &"player_main",
				"shells": PackedStringArray(["rom_myhome_ug"])}
		)
	)
	_put_house(PLAYER_HOUSE_ID, &"player", &"player_house", [&"player_main"])


static func _register_npc() -> void:
	for i: int in NPC_ROOM_COUNT:
		var room_id := StringName("npc_%d" % i)
		var room := _make(
			room_id,
			Room.Kind.NPC,
			"House",
			NPC_INNER_ORIGIN,
			NPC_INNER_SIZE,
			{
				"wall": WALL_ROSE if i % 2 == 0 else WALL_GREEN,
				"floor": FLOOR_WOOD,
				## Arrange_Room draws rom_myhome2 floor/wall with carpet banks (not room01).
				"shells": PackedStringArray(["rom_myhome2_floor", "rom_myhome2_wall"]),
			}
		)
		_apply_npc_house_door(room)
		_add_ftr(room, &"wood_chair", Vector2i(3, 5), WorldGrid.Facing.SOUTH)
		_put_room(room)
		var house_id := room_id
		_put_house(house_id, &"", StringName("npc_house_%d" % i), [room_id])
		_bind(StringName("npc_house_%d" % i), house_id)


static func _ensure_villager_room(room_id: StringName) -> Room:
	if room_id == &"":
		return null
	if _rooms.has(room_id):
		return _rooms[room_id] as Room
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
	var room := _make(
		room_id,
		Room.Kind.NPC,
		label,
		NPC_INNER_ORIGIN,
		NPC_INNER_SIZE,
		{
			"wall": villager.wall_style_id(),
			"floor": villager.floor_style_id(),
			## Arrange_Room draws rom_myhome2 floor/wall with carpet banks (not room01).
			"shells": PackedStringArray(["rom_myhome2_floor", "rom_myhome2_wall"]),
		}
	)
	_apply_npc_house_door(room)
	_fill_npc_furniture(room, villager.id)
	_put_room(room)
	_put_house(room_id, villager.id, &"", [room_id])
	_bind(villager.id, room_id)
	return room


static func _fill_npc_furniture(room: Room, villager_id: StringName) -> void:
	var layout: Dictionary = _npc_layout(villager_id)
	var placements: Array = layout.get("placements", []) as Array
	if placements.is_empty():
		_add_ftr(room, &"wood_chair", Vector2i(3, 5), WorldGrid.Facing.SOUTH)
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
		_add_ftr(room, data.id, cell, facing, footprint, cloth)


static func _npc_layout(villager_id: StringName) -> Dictionary:
	_ensure_npc_layouts()
	if villager_id == &"":
		return {}
	return _npc_layouts.get(String(villager_id), {}) as Dictionary


static func _ensure_npc_layouts() -> void:
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


static func _register_shops() -> void:
	## Floor/wall: `aSI_wall/floor_default_table` → ETC bank `WALL_SHOP*` / `FLOOR_SHOP*`.
	## Shells bake style-0 placeholders; runtime paints the shop bank indices.
	var shop0 := _public(
		&"shop0",
		Room.Kind.SHOP,
		"Nook's Cranny",
		ShopDisplay.CRANNY_INNER_ORIGIN,
		ShopDisplay.CRANNY_INNER_SIZE,
		9,
		22
	)
	shop0.wall_id = ShopDisplay.nook_wall_id(0)
	shop0.floor_id = ShopDisplay.nook_floor_id(0)
	shop0.door_cell = ShopDisplay.CRANNY_DOOR_CELL
	shop0.spawn_cell = ShopDisplay.CRANNY_SPAWN_CELL
	shop0.shell_ids = PackedStringArray(["rom_shop1f", "rom_shop1w"])
	_put_room(shop0)
	var shop1 := _public(&"shop1", Room.Kind.SHOP, "Nook 'n' Go", Vector2i(3, 3), Vector2i(10, 10), 7, 23)
	shop1.wall_id = ShopDisplay.nook_wall_id(1)
	shop1.floor_id = ShopDisplay.nook_floor_id(1)
	shop1.shell_ids = PackedStringArray(["rom_shop2f", "rom_shop2w"])
	_put_room(shop1)
	var shop2 := _public(&"shop2", Room.Kind.SHOP, "Nookway", Vector2i(3, 3), Vector2i(10, 10), 9, 22)
	shop2.wall_id = ShopDisplay.nook_wall_id(2)
	shop2.floor_id = ShopDisplay.nook_floor_id(2)
	shop2.shell_ids = PackedStringArray(["rom_shop3f", "rom_shop3w"])
	_put_room(shop2)
	var shop3_1 := _public(
		&"shop3_1", Room.Kind.SHOP, "Nookington's", Vector2i(3, 3), Vector2i(10, 10), 9, 22
	)
	shop3_1.wall_id = ShopDisplay.nook_wall_id(3)
	shop3_1.floor_id = ShopDisplay.nook_floor_id(3)
	shop3_1.linked_rooms = [&"shop3_2"]
	shop3_1.shell_ids = PackedStringArray(["rom_shop4_1"])
	_put_room(shop3_1)
	var shop3_2 := _public(
		&"shop3_2", Room.Kind.SHOP, "Nookington's Annex", Vector2i(3, 3), Vector2i(10, 10), 9, 22
	)
	shop3_2.wall_id = &"wall_70"
	shop3_2.floor_id = &"floor_70"
	shop3_2.parent_room_id = &"shop3_1"
	shop3_2.shell_ids = PackedStringArray(["rom_shop4_2f", "rom_shop4_2w"])
	_put_room(shop3_2)
	## Broker is event-gated outdoors, not clock hours (`aBRS_open_check`).
	var broker := _make(
		&"broker_shop", Room.Kind.BROKER, "Redd's Tent", Vector2i(5, 5), Vector2i(6, 6), {}
	)
	broker.wall_id = &""
	broker.floor_id = &""
	broker.shell_ids = PackedStringArray(["rom_tent"])
	_put_room(broker)
	_put_house(&"shop", &"", &"acre_shop", [&"shop0"])
	_put_house(&"broker_shop", &"", &"broker_shop", [&"broker_shop"])
	_bind(&"broker_shop", &"broker_shop")


static func _register_public() -> void:
	## Post / police: always enterable; hour checks in decomp are lights only.
	var post := _make(
		&"post_office", Room.Kind.POST_OFFICE, "Post Office", Vector2i(5, 5), Vector2i(6, 6), {}
	)
	post.wall_id = &""
	post.floor_id = &""
	_put_room(post)
	var police := _make(&"police_box", Room.Kind.POLICE, "Police Station", Vector2i(5, 5), Vector2i(6, 6), {})
	police.wall_id = &""
	police.floor_id = &""
	police.shell_ids = PackedStringArray(["police_indoor"])
	_put_room(police)
	_put_room(_make(&"buggy", Room.Kind.DUMP, "Dump", Vector2i(4, 4), Vector2i(8, 8), {"floor": FLOOR_STONE}))
	var snow := _make(
		&"kamakura", Room.Kind.KAMAKURA, "Snow Cabin", Vector2i(5, 5), Vector2i(6, 6), {}
	)
	snow.wall_id = &""
	snow.floor_id = &""
	snow.shell_ids = PackedStringArray(["rom_kamakura"])
	_put_room(snow)
	## Able: closed 02:00–07:00 (`aNW_check_opend`); open 7→2 wraps past midnight.
	var needle := _public(
		&"needlework", Room.Kind.NEEDLEWORK, "Able Sisters", Vector2i(4, 4), Vector2i(8, 8), 7, 2
	)
	needle.wall_id = &""
	needle.floor_id = &""
	needle.shell_ids = PackedStringArray(["rom_tailor"])
	_add_ftr(needle, &"wood_table", Vector2i(6, 7), WorldGrid.Facing.SOUTH)
	_put_room(needle)
	_put_room(
		_make(&"lighthouse", Room.Kind.LIGHTHOUSE, "Lighthouse", Vector2i(6, 6), Vector2i(4, 4), {"floor": FLOOR_STONE})
	)
	var tent := _make(&"tent", Room.Kind.TENT, "Tent", Vector2i(5, 5), Vector2i(6, 6), {})
	tent.wall_id = &""
	tent.floor_id = &""
	tent.shell_ids = PackedStringArray(["rom_tent"])
	_put_room(tent)
	_put_room(_make(&"cottage", Room.Kind.COTTAGE, "Cottage", Vector2i(5, 5), Vector2i(6, 6), {}))
	_put_house(&"post_office", &"", &"post_office", [&"post_office"])
	_put_house(&"police_box", &"", &"police", [&"police_box"])
	_put_house(&"dump", &"", &"buggy", [&"buggy"])
	_put_house(&"kamakura", &"", &"kamakura", [&"kamakura"])
	_put_house(&"needlework", &"", &"able_sisters", [&"needlework"])
	_put_house(&"lighthouse", &"", &"lighthouse", [&"lighthouse"])
	_put_house(&"tent", &"", &"tent", [&"tent"])
	_put_house(&"cottage", &"", &"cottage", [&"cottage"])
	_bind(&"buggy", &"dump")
	_bind(&"kamakura", &"kamakura")
	_bind(&"lighthouse", &"lighthouse")
	_bind(&"tent", &"tent")


static func _register_museum() -> void:
	## Pipeline shells keep baked TEX_EDGE textures — no wallpaper/carpet bank.
	## Inner sizes match floor prims at acre scale (`rom_museum*_floor*`).
	## Floor prim AABB at acre scale: X cells 1–11, Z cells 3–11 → (1,3)+(10,8).
	## Old (3,3)+(10,10) plus the one-cell wall inset put west collision too far in
	## and left a gap past the east visual wall.
	## Always open — `aMsm_ctrl_light` is lights only (6–18), not an entry gate.
	var entrance := _make(
		&"museum_entrance", Room.Kind.MUSEUM, "Museum", Vector2i(1, 3), Vector2i(10, 8), {}
	)
	entrance.linked_rooms = [
		&"museum_painting", &"museum_fossil", &"museum_insect", &"museum_fish"
	]
	entrance.wall_id = &""
	entrance.floor_id = &""
	entrance.shell_ids = PackedStringArray(["rom_museum1"])
	_put_room(entrance)
	var wing_sizes := {
		&"museum_painting": Vector2i(14, 12),
		&"museum_fossil": Vector2i(14, 12),
		&"museum_insect": Vector2i(12, 14),
		&"museum_fish": Vector2i(10, 14),
	}
	## Floor prims sit one cell in from acre NW (not vertically centered).
	## Painting/fossil floor z ends at 26 m (cell 13); insect/fish extend to acre SE.
	var wing_origins := {
		&"museum_painting": Vector2i(1, 1),
		&"museum_fossil": Vector2i(1, 1),
		&"museum_insect": Vector2i(1, 1),
		&"museum_fish": Vector2i(3, 1),
	}
	var wing_shells := {
		&"museum_painting": PackedStringArray(["rom_museum3"]),
		&"museum_fossil": PackedStringArray(["rom_museum2"]),
		&"museum_insect": PackedStringArray(["rom_museum4", "rom_museum4_wall", "rom_museum4_ue"]),
		&"museum_fish": PackedStringArray(["rom_museum5", "rom_museum5_wall"]),
	}
	for wing: StringName in entrance.linked_rooms:
		var label := String(wing).replace("museum_", "").capitalize()
		var inner: Vector2i = wing_sizes.get(wing, Vector2i(10, 10)) as Vector2i
		var origin: Vector2i = wing_origins.get(wing, Vector2i.ZERO) as Vector2i
		var room := _make(wing, Room.Kind.MUSEUM, "%s Wing" % label, origin, inner, {})
		room.parent_room_id = &"museum_entrance"
		room.wall_id = &""
		room.floor_id = &""
		if wing_shells.has(wing):
			room.shell_ids = wing_shells[wing]
		_put_room(room)
	_put_house(
		&"museum",
		&"",
		&"museum",
		[
			&"museum_entrance",
			&"museum_painting",
			&"museum_fossil",
			&"museum_insect",
			&"museum_fish",
		]
	)


static func _public(
	id: StringName,
	kind: Room.Kind,
	display: String,
	origin: Vector2i,
	size: Vector2i,
	open_hour: int,
	close_hour: int
) -> Room:
	return _make(
		id,
		kind,
		display,
		origin,
		size,
		{"open": open_hour, "close": close_hour}
	)


static func _make(
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
	room.wall_id = opts.get("wall", WALL_DEFAULT) as StringName
	room.floor_id = opts.get("floor", FLOOR_DEFAULT) as StringName
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


static func _apply_npc_house_door(room: Room) -> void:
	## `fgnpcdata` EXIT at (3,8)/(4,8); enter `{160,0,300}` facing north.
	if room == null:
		return
	room.door_cell = NPC_HOUSE_DOOR_CELL
	room.spawn_cell = NPC_HOUSE_SPAWN_CELL


static func _apply_player_small_door(room: Room) -> void:
	## `l_proom_s_tmp` EXIT at (2,7)/(3,7); enter `{120,0,220}` facing north.
	if room == null:
		return
	room.door_cell = PLAYER_SMALL_DOOR_CELL
	room.spawn_cell = PLAYER_SMALL_SPAWN_CELL


static func _fill_player_starter(room: Room) -> void:
	## `mHm_SetDefaultPlayerRoomData`: orange crate at (1,1), cassette at (4,1).
	if room == null or not room.placements.is_empty():
		return
	var origin: Vector2i = room.inner_origin
	var crate: FurnitureData = ItemCatalog.furniture_for_visual(&"int_nog_mikanbox")
	if crate != null:
		_add_ftr(room, crate.id, origin, WorldGrid.Facing.SOUTH)
	var tape: FurnitureData = ItemCatalog.furniture_for_visual(&"int_sum_casse01")
	if tape != null:
		_add_ftr(room, tape.id, origin + Vector2i(3, 0), WorldGrid.Facing.SOUTH)


static func _add_ftr(
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


static func _put_room(room: Room) -> void:
	_rooms[room.id] = room


static func _put_house(
	id: StringName, occupant: StringName, outdoor: StringName, rooms: Array
) -> void:
	var house := House.new()
	house.id = id
	house.occupant_id = occupant
	house.outdoor_building_id = outdoor
	for room_id: Variant in rooms:
		house.rooms.append(room_id as StringName)
	_houses[id] = house


static func _bind(building_id: StringName, house_id: StringName) -> void:
	_building_to_house[building_id] = house_id
