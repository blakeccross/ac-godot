class_name TownImport
extends RefCounted

## Turns a GameCube town (`GameCubeTown.decode`) into this game's save: the town's name, id,
## tune, fruit and grass, its real acre map and what stands on it (kept as `imported_field`,
## which `WorldGenerator` builds the field from instead of random picks), weeds, items lying
## out and buried things, the villagers in their own houses (with each resident's friendships),
## and each resident's name, looks, shirt, pockets, money, loan, house size/plot and rooms
## (furniture with storage and switch bits, wallpaper, carpet), plus the systems this port
## keeps: museum, shop and stalk market, police box, post office, notice board, lighthouse,
## designs, catalog, species log, mail, rainbow, bridge, snowmen and fish records. Island FG
## and event blobs with no Godot system stay behind. The original's clock is the GameCube's
## real-time clock, so the imported town starts at the computer's time.
##
## `build` returns `{payload, summary}`: `payload` is a `SaveService` file, `summary` counts
## what came across ({town_name, residents, villagers, items, friendships, skipped_items,
## skipped_villagers}).

## `GRASS_A`…`GRASS_C`.
const WEED_FIRST := 0x0008
const WEED_LAST := 0x000A
## `ITM_FOSSIL` / `ITM_PITFALL`: buried, they dig up as their own kinds.
const FOSSIL := 0x2511
const PITFALL := 0x2512
## `NAME_TYPE_FTR0`, `NAME_TYPE_ITEM1`, `NAME_TYPE_FTR1`: things that can lie on the field.
const PICKUP_TYPES: Array[int] = [1, 2, 3]
## `mPr_SEX_FEMALE`.
const FEMALE := 1
## `mHm_ROOM_*` → `PlayerHouse` room ids.
const ROOM_IDS: Array[StringName] = [PlayerHouse.MAIN, PlayerHouse.UPPER, PlayerHouse.BASEMENT]
## `mSM_COLLECT_INSECT_*` / `FISH_*` bit bases inside `furniture_collected_bitfield`.
const INSECT_BIT0 := 0x2F2
const FISH_BIT0 := 0x31A
const SPECIES_NUM := 40
## Museum nibble packs (`mMmd_info_c`).
const MUSEUM_FOSSIL := 13
const MUSEUM_ART := 8
const MUSEUM_FISH := 21
const MUSEUM_INSECT := 21


static func build(town: Dictionary) -> Dictionary:
	var summary: Dictionary = {
		"town_name": str(town.get("town_name", "")),
		"residents": 0,
		"villagers": 0,
		"items": 0,
		"friendships": 0,
		"skipped_items": 0,
		"skipped_villagers": 0,
	}
	var weather: Dictionary = _weather(int(town.get("weather", 0)))
	var world: Dictionary = {
		"world_mode": int(WorldData.Mode.GENERATED),
		"world_seed": int(town.get("town_id", 0)),
		"town_name": summary["town_name"] if summary["town_name"] != "" else TownState.DEFAULT_TOWN_NAME,
		"town_id": int(town.get("town_id", 0)),
		"town_tune": Array(town.get("tune", TownTune.default_notes()) as PackedByteArray),
		"town_fruit": String(_fruit(int(town.get("fruit", 0)))),
		"grass_pattern": WorldData.clamp_grass_pattern(int(town.get("grass_pattern", 0))),
		"num_statues": clampi(int(town.get("statues", 0)), 0, 3),
		"imported_field": {"acres": town.get("acres", []), "field": _field_arrays(town.get("field", []))},
		"clear_grass": bool(town.get("clear_grass", false)),
		"dust_flag": bool(town.get("dust_flag", false)),
		"perfect_streak": maxi(0, int(town.get("perfect_streak", 0))),
		"gyroids_scheduled": bool(town.get("gyroids_scheduled", false)),
		"weather": String(weather["kind"]),
		"weather_intensity": int(weather["intensity"]),
		"fish_season_term": {
			"term": int(town.get("fish_term", 0)),
			"offset": int(town.get("fish_term_offset", 0)),
		},
		"rainbow": _rainbow(town.get("rainbow", {})),
		"museum": _museum(town.get("museum", PackedByteArray())),
		"shops": _shops(town.get("shop", {}), town.get("stalk", {})),
		"police": _police(town.get("police", [])),
		"post": _post(town.get("post", {}), summary),
		"notice_board": _notice(town.get("notice", [])),
		"lighthouse": _lighthouse(town.get("lighthouse", {})),
		"bridge": _bridge(town.get("bridge", {})),
		"snowmen": _snowmen(town.get("snowmen", [])),
		"fish_records": _fish_records(town.get("fish_records", [])),
		"designs": _town_designs(town.get("designs_shop", [])),
	}
	_add_field(world, town, summary)
	world["residents"] = _villagers(town, summary)
	var slots: Array = []
	var current: int = -1
	var residents: Array = town.get("residents", [])
	for i: int in PlayerRoster.MAX:
		var raw: Dictionary = residents[i] if i < residents.size() else {}
		if raw.is_empty():
			slots.append({})
			continue
		slots.append(_resident(raw, town, summary))
		summary["residents"] = int(summary["residents"]) + 1
		if current < 0:
			current = i
	world["roster"] = {"current": maxi(current, 0), "slots": slots}
	## Able Sisters visit days for the first resident who talked to Sable.
	if current >= 0 and typeof(slots[current]) == TYPE_DICTIONARY:
		var sable: Dictionary = (slots[current] as Dictionary).get("_sable", {})
		if typeof(sable) == TYPE_DICTIONARY:
			(world["designs"] as Dictionary)["sable_days"] = int(sable.get("days", 0))
			(world["designs"] as Dictionary)["sable_last_date"] = str(sable.get("date", ""))
		(slots[current] as Dictionary).erase("_sable")
	var now: Dictionary = Time.get_datetime_dict_from_system()
	var payload: Dictionary = {
		"version": SaveService.SAVE_VERSION,
		"clock": {
			"year": now["year"], "month": now["month"], "day": now["day"],
			"hour": now["hour"], "minute": now["minute"], "second": now["second"],
		},
		"os_time": int(Time.get_unix_time_from_system()),
		"world": world,
		"reset_code": 0,
		"resetti_disabled": false,
	}
	return {"payload": payload, "summary": summary}


## `Save_Get(fruit)` → the native fruit (apple when the save names none of the five).
static func _fruit(number: int) -> StringName:
	var i: int = number - CodeItems.FOOD0
	return CodeItems.FOODS[i] if i >= 0 and i < ShopBook.FRUITS.size() else &"apple"


## `Save.weather`: upper nibble intensity, lower type — opposite of `Weather.pack`.
static func _weather(packed: int) -> Dictionary:
	var kind: int = clampi(packed & 0xF, 0, int(Weather.Kind.SAKURA))
	var intensity: int = clampi((packed >> 4) & 0xF, 0, int(Weather.Intensity.HEAVY))
	return {"kind": Weather.kind_name(kind as Weather.Kind), "intensity": intensity}


static func _rainbow(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {"reserved": false, "month": 0, "day": 0}
	var row: Dictionary = raw
	return {
		"reserved": bool(row.get("reserved", false)),
		"month": int(row.get("month", 0)),
		"day": int(row.get("day", 0)),
	}


## Plain arrays for JSON: acre → 256 item numbers.
static func _field_arrays(field: Array) -> Array:
	var out: Array = []
	for acre: Variant in field:
		out.append(Array(acre as PackedInt32Array) if acre is PackedInt32Array else acre)
	return out


## Weeds, items lying out and buried things go into the town's own records; trees, flowers,
## rocks, fences and buildings are rebuilt from `imported_field` by the generator.
static func _add_field(world: Dictionary, town: Dictionary, summary: Dictionary) -> void:
	var weeds: Dictionary = {}
	var items: Dictionary = {}
	var buried: Dictionary = {}
	var field: Array = town.get("field", [])
	var deposits: Array = town.get("buried", [])
	for acre: int in mini(field.size(), GameCubeTown.FIELD_X * GameCubeTown.FIELD_Z):
		var units: PackedInt32Array = field[acre]
		var rows: PackedInt32Array = deposits[acre] if acre < deposits.size() else PackedInt32Array()
		var origin := Vector2i((acre % GameCubeTown.FIELD_X) * GameCubeTown.UNITS, (acre / GameCubeTown.FIELD_X) * GameCubeTown.UNITS)
		for i: int in units.size():
			var number: int = units[i]
			var ux: int = i % GameCubeTown.UNITS
			var uz: int = i / GameCubeTown.UNITS
			var cell: Vector2i = origin + Vector2i(ux, uz)
			var is_buried: bool = uz < rows.size() and ((rows[uz] >> ux) & 1) == 1
			if is_buried:
				var record: Dictionary = _buried(number, cell)
				if record.is_empty():
					summary["skipped_items"] = int(summary["skipped_items"]) + 1
				else:
					buried[String(BuriedUse.persist_id(cell))] = record
				continue
			if number >= WEED_FIRST and number <= WEED_LAST:
				weeds[String(WeedUse.persist_id(cell))] = number - WEED_FIRST
				continue
			if not PICKUP_TYPES.has(number >> 12):
				continue
			var id: StringName = CodeItems.id_of(number)
			if id == &"":
				summary["skipped_items"] = int(summary["skipped_items"]) + 1
				continue
			items[String(FieldItems.persist_id(cell))] = {"id": String(id), "wrapped": false}
			summary["items"] = int(summary["items"]) + 1
	world["weeds"] = weeds
	world["field_items"] = items
	world["buried"] = buried


static func _buried(number: int, cell: Vector2i) -> Dictionary:
	var kind: StringName = BuriedUse.KIND_ITEM
	var id: StringName = CodeItems.id_of(number)
	if number == FOSSIL:
		kind = BuriedUse.KIND_FOSSIL
	elif number == PITFALL:
		kind = BuriedUse.KIND_PITFALL
		id = BuriedUse.PITFALL_ITEM
	if id == &"":
		return {}
	return {
		BuriedUse.KEY_KIND: String(kind),
		BuriedUse.KEY_ITEM: String(id),
		BuriedUse.KEY_CELL_X: cell.x,
		BuriedUse.KEY_CELL_Z: cell.y,
	}


## `Save_Get(animals)` → `TownResidents` slots, in the save's order.
static func _villagers(town: Dictionary, summary: Dictionary) -> Dictionary:
	var rows: Array = []
	var plots: Array = []
	var raw: Array = town.get("villagers", [])
	for i: int in TownResidents.ANIMAL_NUM_MAX:
		var v: Dictionary = raw[i] if i < raw.size() else {}
		var data: VillagerData = VillagerCatalog.by_npc_index(int(v.get("npc_index", -1))) if not v.is_empty() else null
		if data == null:
			if not v.is_empty():
				summary["skipped_villagers"] = int(summary["skipped_villagers"]) + 1
			rows.append({})
			continue
		var home: Vector2i = v.get("home", GameCubeTown.NO_HOME)
		var row: Dictionary = {"id": String(data.id), "home": [home.x, home.y], "moved_in": bool(v.get("moved_in", false))}
		var cloth: StringName = CodeItems.id_of(int(v.get("cloth", 0)))
		if cloth != &"" and String(cloth).begins_with("shirt_"):
			row["cloth_id"] = String(cloth)
		rows.append(row)
		if home != GameCubeTown.NO_HOME:
			plots.append([home.x, home.y])
		summary["villagers"] = int(summary["villagers"]) + 1
	return {
		"slots": rows,
		"now_npc_max": clampi(int(town.get("villager_max", TownResidents.LOOKS_NUM)), TownResidents.ANIMAL_NUM_MIN, TownResidents.ANIMAL_NUM_MAX),
		"used_plots": plots,
	}


## One `Private_c` → a `PlayerRoster` slot. The first job and the map are long done in a town
## someone has been living in.
static func _resident(raw: Dictionary, town: Dictionary, summary: Dictionary) -> Dictionary:
	var gender: StringName = IntroSequence.GENDER_FEMALE if int(raw.get("gender", 0)) == FEMALE else IntroSequence.GENDER_MALE
	var cloth: StringName = CodeItems.id_of(int(raw.get("cloth", 0)))
	if cloth == &"" or not String(cloth).begins_with("shirt_"):
		cloth = IntroSequence.starting_cloth(gender)
	var pockets: Array = []
	for p: Variant in raw.get("pockets", []):
		var pocket: Dictionary = p
		var number: int = int(pocket.get("item", 0))
		var id: StringName = CodeItems.id_of(number) if number != 0 else &""
		if id == &"" and number != 0:
			summary["skipped_items"] = int(summary["skipped_items"]) + 1
		pockets.append({"id": String(id), "count": 1 if id != &"" else 0, "condition": clampi(int(pocket.get("condition", 0)), 0, 2)})
	var house: Dictionary = raw.get("house", {})
	var size: int = clampi(int(house.get("size", 0)), 0, int(House.SizeTier.STATUE))
	var next_size: int = clampi(int(house.get("next_size", size)), 0, int(House.SizeTier.STATUE))
	var order_year: int = int(house.get("order_year", 0))
	var order_month: int = int(house.get("order_month", 0))
	var order_day: int = int(house.get("order_day", 0))
	var basement_ordered: bool = bool(house.get("basement_ordered", false))
	var statue_ordered: bool = bool(house.get("statue_ordered", false))
	var renew: bool = bool(house.get("renew", false))
	## A pending size change with no order date would land on the first load (`CHECK_ORDER_DATE`
	## against year 0). Snap next to current so import does not invent a free upgrade / loan.
	if next_size != size and order_year <= 0 and not basement_ordered and not statue_ordered:
		next_size = size
	var has_basement: bool = bool(house.get("has_basement", false))
	var rooms: Dictionary = _rooms(raw.get("rooms", []), size, has_basement, summary)
	var bonds: Dictionary = _relationships(raw, town, summary)
	var room_ids: Array = []
	for room_id: StringName in ROOM_IDS:
		if rooms.has(String(room_id)):
			room_ids.append(String(room_id))
	var catalog: Dictionary = _catalog(raw, summary)
	var species: Dictionary = _species(raw)
	var designs: Dictionary = _player_designs(raw)
	var mail: Array = _resident_mail(raw, summary)
	var goki: Dictionary = house.get("goki_time", {}) if typeof(house.get("goki_time")) == TYPE_DICTIONARY else {}
	var gyroid: Dictionary = house.get("gyroid", {}) if typeof(house.get("gyroid")) == TYPE_DICTIONARY else {}
	var sable: Dictionary = raw.get("sable_date", {}) if typeof(raw.get("sable_date")) == TYPE_DICTIONARY else {}
	var sable_date := ""
	if int(sable.get("year", 0)) > 0:
		sable_date = "%04d-%02d-%02d" % [int(sable.get("year", 0)), int(sable.get("month", 0)), int(sable.get("day", 0))]
	var roof: int = clampi(int(house.get("roof", 0)), 0, House.OUTLOOK_PAL_COUNT - 1)
	var ordered_roof: int = clampi(int(house.get("ordered_roof", roof)), 0, House.OUTLOOK_PAL_COUNT - 1)
	var next_roof: int = clampi(int(house.get("next_roof", roof)), 0, House.OUTLOOK_PAL_COUNT - 1)
	return {
		"player_name": str(raw.get("name", "")),
		"player_gender": String(gender),
		"player_face": clampi(int(raw.get("face", 0)), 0, IntroSequence.FACE_TYPE_NUM - 1),
		"cloth_id": String(cloth),
		"has_map": true,
		"first_job": {"kind": int(FirstJob.Kind.DONE)},
		"relationships": bonds,
		"catalog": catalog,
		"species_log": species,
		PlayerRoster.KEY_DESIGNS: designs,
		PlayerRoster.KEY_INVENTORY: {
			"slots": pockets,
			"mail": mail,
			"wallet": clampi(int(raw.get("wallet", 0)), 0, Inventory.WALLET_MAX),
			"savings": maxi(0, int(raw.get("savings", 0))),
			"loan": maxi(0, int(raw.get("loan", 0))),
		},
		PlayerRoster.KEY_ROOMS: rooms,
		PlayerRoster.KEY_HOUSE: {
			"id": String(InteriorCatalog.PLAYER_HOUSE_ID),
			"outdoor_building_id": String(FieldObjectCatalog.player_plot_id(int(house.get("plot", 0)))),
			"size_tier": size,
			"next_size_tier": next_size,
			"has_basement": has_basement,
			"basement_ordered": basement_ordered,
			"statue_ordered": statue_ordered,
			"renew": renew,
			"statue_rank": clampi(int(house.get("statue_rank", 0)), 0, 3),
			"order_date": [order_year, order_month, order_day],
			"outlook_pal": roof,
			"ordered_outlook_pal": ordered_roof,
			"next_outlook_pal": next_roof,
			"rooms": room_ids,
			"has_saved": bool(house.get("has_saved", false)),
			"music_box": str(int(house.get("music_box", 0))),
			"goki_count": clampi(int(house.get("goki_count", 0)), 0, 10),
			"goki_date": [int(goki.get("year", 0)), int(goki.get("month", 0)), int(goki.get("day", 0))],
			"gyroid_items": _gyroid_items(gyroid, summary),
			"gyroid_message": str(gyroid.get("message", "")),
			"gyroid_bells": maxi(0, int(gyroid.get("bells", 0))),
		},
		"_sable": {"days": clampi(int(raw.get("sable_days", 0)), 0, DesignBook.SABLE_DAYS_MAX), "date": sable_date},
	}


## `mHm_flr_c` layers → saved player rooms. Layer 0 is floor furniture; layers 1–3 at the
## same cell fill that piece's storage (`st`). `ftr_switch` bits become `on`.
static func _rooms(raw_rooms: Variant, size: int, has_basement: bool, summary: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw_rooms) != TYPE_ARRAY:
		return out
	var floors: Array = raw_rooms
	for r: int in mini(floors.size(), ROOM_IDS.size()):
		if not _room_exists(r, size, has_basement):
			continue
		var floor: Dictionary = floors[r] if typeof(floors[r]) == TYPE_DICTIONARY else {}
		var layers: Array = floor.get("layers", []) if typeof(floor.get("layers")) == TYPE_ARRAY else []
		var switches: Array = floor.get("switches", []) if typeof(floor.get("switches")) == TYPE_ARRAY else []
		var switch0: int = int(switches[0]) if switches.size() > 0 else 0
		var floor_layer: PackedInt32Array = layers[0] if layers.size() > 0 and layers[0] is PackedInt32Array else PackedInt32Array()
		var by_cell: Dictionary = {}
		var placements: Array = []
		var seq: int = 0
		for i: int in floor_layer.size():
			var number: int = floor_layer[i]
			if number == 0 or not CodeItems.is_ftr(number):
				continue
			var id: StringName = CodeItems.id_of(number)
			if id == &"":
				summary["skipped_items"] = int(summary["skipped_items"]) + 1
				continue
			seq += 1
			var x: int = i % GameCubeTown.UNITS
			var z: int = i / GameCubeTown.UNITS
			var entry: Dictionary = {
				"id": "ftr_%d" % seq,
				"furniture_id": String(id),
				"x": x,
				"z": z,
				"facing": CodeItems.facing_of(number),
			}
			if x >= 1 and x <= 8 and z >= 1 and z <= 8:
				var shift: int = (x - 1 + (z - 1) * 8) & 0x3F
				if ((switch0 >> shift) & 1) == 0:
					entry["on"] = 0
			var stored: Array = []
			for layer: int in range(1, mini(layers.size(), GameCubeTown.LAYER_NUM)):
				var layer_items: PackedInt32Array = layers[layer] if layers[layer] is PackedInt32Array else PackedInt32Array()
				if i >= layer_items.size():
					continue
				var kept: int = layer_items[i]
				if kept == 0:
					continue
				var kept_id: StringName = CodeItems.id_of(kept)
				if kept_id == &"":
					summary["skipped_items"] = int(summary["skipped_items"]) + 1
					continue
				stored.append(String(kept_id))
				summary["items"] = int(summary["items"]) + 1
			if not stored.is_empty():
				entry["st"] = stored
			placements.append(entry)
			by_cell[i] = entry
			summary["items"] = int(summary["items"]) + 1
		## Surface / leftover layer-1 items with no floor furniture become `ly` placements.
		if layers.size() > 1 and layers[1] is PackedInt32Array:
			var surface: PackedInt32Array = layers[1]
			for i: int in surface.size():
				if by_cell.has(i):
					continue
				var number: int = surface[i]
				if number == 0:
					continue
				var id: StringName = CodeItems.id_of(number)
				if id == &"":
					summary["skipped_items"] = int(summary["skipped_items"]) + 1
					continue
				seq += 1
				placements.append({
					"id": "ftr_%d" % seq,
					"furniture_id": String(id),
					"x": i % GameCubeTown.UNITS,
					"z": i / GameCubeTown.UNITS,
					"facing": CodeItems.facing_of(number),
					"ly": 1,
				})
				summary["items"] = int(summary["items"]) + 1
		var room_id := String(ROOM_IDS[r])
		out[room_id] = {
			"id": room_id,
			"wall_id": String(InteriorStyleCatalog.wall_style_id(int(floor.get("wall_idx", 0)))),
			"floor_id": String(InteriorStyleCatalog.floor_style_id(int(floor.get("floor_idx", 0)))),
			"placements": placements,
			"placement_seq": seq,
		}
	return out


static func _room_exists(room: int, size: int, has_basement: bool) -> bool:
	match room:
		0:
			return true
		1:
			return size >= int(House.SizeTier.UPPER)
		2:
			return has_basement
	return false


## Each villager's `Anmmem_c` for this resident → `RelationshipBook` save rows.
static func _relationships(raw: Dictionary, town: Dictionary, summary: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var player_id: int = int(raw.get("player_id", 0))
	var land_id: int = int(raw.get("land_id", 0))
	var name: String = str(raw.get("name", ""))
	for v: Variant in town.get("villagers", []):
		if typeof(v) != TYPE_DICTIONARY or (v as Dictionary).is_empty():
			continue
		var villager: Dictionary = v
		var data: VillagerData = VillagerCatalog.by_npc_index(int(villager.get("npc_index", -1)))
		if data == null:
			continue
		var mem: Dictionary = _memory_for(villager.get("memories", []), name, player_id, land_id)
		if mem.is_empty():
			continue
		var bond: Dictionary = _bond(String(data.id), mem)
		out[String(data.id)] = bond
		summary["friendships"] = int(summary["friendships"]) + 1
	return out


static func _memory_for(memories: Variant, name: String, player_id: int, land_id: int) -> Dictionary:
	if typeof(memories) != TYPE_ARRAY:
		return {}
	for row: Variant in memories as Array:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var mem: Dictionary = row
		if int(mem.get("land_id", -1)) != land_id:
			continue
		if int(mem.get("player_id", -1)) == player_id and str(mem.get("name", "")) == name:
			return mem
		## Name + land is enough when player_id was cleared in an older copy.
		if str(mem.get("name", "")) == name:
			return mem
	return {}


static func _bond(villager_id: String, mem: Dictionary) -> Dictionary:
	var spoke: Dictionary = mem.get("last_spoke", {}) if typeof(mem.get("last_spoke")) == TYPE_DICTIONARY else {}
	var day: String = ""
	if int(spoke.get("year", 0)) > 0:
		day = "%04d-%02d-%02d" % [int(spoke.get("year", 0)), int(spoke.get("month", 0)), int(spoke.get("day", 0))]
	var friendship: int = clampi(int(mem.get("friendship", 0)), Relationship.FRIENDSHIP_MIN, Relationship.FRIENDSHIP_MAX)
	return {
		"id": villager_id,
		"friendship": friendship,
		"last_spoke_day": day,
		"talk_count": 1,
		"gift_count": 0,
		"talks": [],
		"gifts": [],
		"milestones": [],
		"has_memory": true,
		"letter_exists": bool(mem.get("letter_exists", false)),
		"letter_cond": int(mem.get("letter_cond", 0)),
		"send_reply": bool(mem.get("send_reply", false)),
		"letter_day": -1,
		"letter": {},
	}


static func _museum(raw: Variant) -> Dictionary:
	var bytes: PackedByteArray = raw as PackedByteArray if raw is PackedByteArray else PackedByteArray()
	return {
		"fossil": _byte_slice(bytes, 0, MUSEUM_FOSSIL),
		"art": _byte_slice(bytes, MUSEUM_FOSSIL, MUSEUM_ART),
		"fish": _byte_slice(bytes, MUSEUM_FOSSIL + MUSEUM_ART, MUSEUM_FISH),
		"insect": _byte_slice(bytes, MUSEUM_FOSSIL + MUSEUM_ART + MUSEUM_FISH, MUSEUM_INSECT),
	}


static func _byte_slice(bytes: PackedByteArray, at: int, count: int) -> Array:
	var out: Array = []
	for i: int in count:
		out.append(bytes[at + i] if at + i < bytes.size() else 0)
	return out


static func _shops(shop: Variant, stalk: Variant) -> Dictionary:
	var s: Dictionary = shop if typeof(shop) == TYPE_DICTIONARY else {}
	var goods: Array = []
	for number: Variant in s.get("goods", []):
		var id: StringName = CodeItems.id_of(int(number))
		if id != &"":
			goods.append(String(id))
	var rare: StringName = CodeItems.id_of(int(s.get("rare", 0)))
	## `ShopBook.renew` is `Clock.renew_index()`, not a calendar day — leave unset so
	## `ensure_today` restocks. `renewal` is the booked reopening ordinal from GC.
	var renewal: int = _ymd_ordinal(s.get("renewal", {}))
	var level: int = clampi(int(s.get("level", 0)), 0, 3)
	var sales: int = maxi(0, int(s.get("sales", 0)))
	## Mid-renovation saves keep the booked day; otherwise clear a stale GC date so a settled
	## shop is not closed on load.
	if not bool(s.get("upgrading", false)) and level >= _nook_real_level(sales, bool(s.get("visitor", false))):
		renewal = -1
	var row: Dictionary = {
		"id": String(ShopBook.NOOK_ID),
		"goods": goods,
		"sales": sales,
		"renew": -1,
		"level": level,
		"renewal": renewal,
		"visitor": bool(s.get("visitor", false)),
		"paint": clampi(int(s.get("paint", 0)), 0, 15),
		"rare": String(rare),
	}
	var out: Dictionary = {String(ShopBook.NOOK_ID): row}
	var st: Dictionary = stalk if typeof(stalk) == TYPE_DICTIONARY else {}
	var prices: Array = []
	for p: Variant in st.get("prices", []):
		prices.append(int(p))
	while prices.size() < 7:
		prices.append(0)
	if prices.size() > 7:
		prices.resize(7)
	var week: int = _ymd_ordinal(st.get("update", {}))
	if week > 0 or int(st.get("trend", 0)) != 0 or prices[0] != 0:
		out["_stalk_market"] = {
			"prices": prices,
			"trend": clampi(int(st.get("trend", 0)), 0, 2),
			"week": week,
		}
	return out


static func _police(raw: Variant) -> Dictionary:
	var keep: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for number: Variant in raw as Array:
			var id: StringName = CodeItems.id_of(int(number))
			if id != &"":
				keep.append(String(id))
	return {"keep_items": keep}


static func _post(raw: Variant, summary: Dictionary) -> Dictionary:
	var row: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var mail: Array = []
	for entry: Variant in row.get("mail", []):
		mail.append(_mail_save(entry, summary))
	while mail.size() < PostBook.MAIL_STORAGE_SIZE:
		mail.append({})
	if mail.size() > PostBook.MAIL_STORAGE_SIZE:
		mail.resize(PostBook.MAIL_STORAGE_SIZE)
	return {
		"mail": mail,
		"keep_mail_sum_players": int(row.get("keep_mail_sum_players", 0)),
		"keep_mail_sum_npcs": int(row.get("keep_mail_sum_npcs", 0)),
		"delivery_minute": -1,
	}


static func _notice(raw: Variant) -> Dictionary:
	var posts: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for entry: Variant in raw as Array:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = entry
			var t: Dictionary = row.get("time", {}) if typeof(row.get("time")) == TYPE_DICTIONARY else {}
			posts.append({
				"text": str(row.get("text", "")),
				"year": int(t.get("year", 0)),
				"month": int(t.get("month", 1)),
				"day": int(t.get("day", 1)),
				"hour": int(t.get("hour", 0)),
				"minute": int(t.get("minute", 0)),
			})
	return {"posts": posts, "checked": [0, 0, 0, 0]}


static func _lighthouse(raw: Variant) -> Dictionary:
	var row: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var year: int = int(row.get("year", 0))
	var month: int = int(row.get("month", 0))
	var day: int = int(row.get("day", 0))
	var started: int = int(row.get("taken", 0))
	return {
		"start": EventDates.ordinal(year, month, day) if year > 0 else 0,
		"month": month,
		"nights_lit": int(row.get("nights", 0)),
		"taken": (started & 0x0F) != 0,
		"contributed": (started & 0xF0) != 0,
		"completed": int(row.get("completed", 0)) != 0,
	}


static func _bridge(raw: Variant) -> Dictionary:
	var row: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	if row.is_empty() or (not bool(row.get("exists", false)) and not bool(row.get("pending", false))):
		return {}
	var build: Dictionary = row.get("build", {}) if typeof(row.get("build")) == TYPE_DICTIONARY else {}
	var state: Dictionary = SecondBridge.new_state()
	state["pending"] = bool(row.get("pending", false))
	state["exists"] = bool(row.get("exists", false))
	state["bx"] = int(row.get("bx", -1))
	state["bz"] = int(row.get("bz", -1))
	state["build"] = _ymd_ordinal(build)
	return state


static func _snowmen(raw: Variant) -> Array:
	var out: Array = [{}, {}, {}]
	if typeof(raw) != TYPE_ARRAY:
		return out
	for i: int in mini((raw as Array).size(), 3):
		var row: Variant = (raw as Array)[i]
		if typeof(row) != TYPE_DICTIONARY or (row as Dictionary).is_empty():
			continue
		var s: Dictionary = row
		## GC stores sizes as bytes; port keeps 0–1 floats.
		out[i] = {
			"head": clampf(float(s.get("head", 0)) / 255.0, 0.0, 1.0),
			"body": clampf(float(s.get("body", 0)) / 255.0, 0.0, 1.0),
			"score": int(s.get("score", 0)),
			"cell": [0, 0],
			"age": 0,
		}
	return out


static func _fish_records(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = entry
		var t: Dictionary = row.get("time", {}) if typeof(row.get("time")) == TYPE_DICTIONARY else {}
		var ordinal: int = _ymd_ordinal(t)
		out.append({
			"name": str(row.get("name", "")),
			"player": true,
			"size": int(row.get("size", 0)),
			"ordinal": ordinal,
			"minute": int(t.get("hour", 0)) * 60 + int(t.get("minute", 0)),
			"settled": true,
		})
	return out


static func _town_designs(shop: Variant) -> Dictionary:
	return {
		"shop": _design_saves(shop),
		"order": [0, 1, 2, 3, 4, 5, 6, 7],
		"album": [],
		"album_names": [],
		"sable_days": 0,
		"sable_last_date": "",
		"sister_now": 0,
		"first_talk_done": false,
		"listened": false,
	}


static func _player_designs(raw: Dictionary) -> Dictionary:
	var order: Array = []
	for v: Variant in raw.get("design_order", []):
		order.append(int(v) & 7)
	while order.size() < GameCubeTown.DESIGN_NUM:
		order.append(order.size())
	if order.size() > GameCubeTown.DESIGN_NUM:
		order.resize(GameCubeTown.DESIGN_NUM)
	return {"player": _design_saves(raw.get("designs", [])), "order": order}


static func _design_saves(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = entry
		var d := DesignPattern.blank()
		d.name = str(row.get("name", "blank"))
		d.palette = int(row.get("palette", 0)) & 0xF
		d.flag_set = bool(row.get("flag", false))
		var ci4: Variant = row.get("ci4", PackedByteArray())
		if ci4 is PackedByteArray:
			d.from_ci4(ci4 as PackedByteArray)
		out.append(d.to_save())
	return out


static func _catalog(raw: Dictionary, summary: Dictionary) -> Dictionary:
	var owned: Array = []
	var insects: Array = []
	_bits_to_furniture(raw.get("furniture_bits", PackedInt32Array()), owned, insects, summary)
	_bits_to_ids(raw.get("wall_bits", PackedInt32Array()), func(i: int) -> StringName: return InteriorStyleCatalog.wall_style_id(i), owned)
	_bits_to_ids(raw.get("carpet_bits", PackedInt32Array()), func(i: int) -> StringName: return InteriorStyleCatalog.floor_style_id(i), owned)
	var paper_any: bool = false
	for word: int in raw.get("paper_bits", PackedInt32Array()) as PackedInt32Array:
		if word != 0:
			paper_any = true
			break
	if paper_any:
		owned.append(String(ShopGoods.PAPER))
	_bits_to_ids(raw.get("music_bits", PackedInt32Array()), func(i: int) -> StringName: return MinidiskCatalog.item_id(i), owned)
	var orders: Array = []
	for entry: Variant in raw.get("catalog_orders", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = entry
		var id: StringName = CodeItems.id_of(int(row.get("item", 0)))
		if id == &"":
			if int(row.get("item", 0)) != 0:
				summary["skipped_items"] = int(summary["skipped_items"]) + 1
			continue
		orders.append({"item": String(id), "level": int(row.get("level", 0))})
		if orders.size() >= CatalogBook.ORDER_SLOTS:
			break
	return {"owned": owned, "orders": orders, "insects": insects}


static func _species(raw: Dictionary) -> Dictionary:
	var caught: Array = []
	var bits: PackedInt32Array = raw.get("furniture_bits", PackedInt32Array()) as PackedInt32Array
	for i: int in SPECIES_NUM:
		if _bit(bits, INSECT_BIT0 + i):
			var id: StringName = EncyclopediaCatalog.id_for(&"insect", i)
			if id != &"":
				caught.append(String(id))
		if _bit(bits, FISH_BIT0 + i):
			var id: StringName = EncyclopediaCatalog.id_for(&"fish", i)
			if id != &"":
				caught.append(String(id))
	caught.sort()
	return {"caught": caught}


static func _bits_to_furniture(bits: Variant, owned: Array, insects: Array, summary: Dictionary) -> void:
	var words: PackedInt32Array = bits as PackedInt32Array if bits is PackedInt32Array else PackedInt32Array()
	var total: int = words.size() * 32
	for i: int in total:
		if not _bit(words, i):
			continue
		if i >= INSECT_BIT0 and i < INSECT_BIT0 + SPECIES_NUM:
			insects.append(i - INSECT_BIT0)
			continue
		if i >= FISH_BIT0 and i < FISH_BIT0 + SPECIES_NUM:
			continue
		var id: StringName = FurnitureCatalog.item_id(i)
		if id == &"" or ItemCatalog.get_item(id) == null:
			summary["skipped_items"] = int(summary["skipped_items"]) + 1
			continue
		owned.append(String(id))


static func _bits_to_ids(bits: Variant, id_of_index: Callable, owned: Array) -> void:
	var words: PackedInt32Array = bits as PackedInt32Array if bits is PackedInt32Array else PackedInt32Array()
	for i: int in words.size() * 32:
		if not _bit(words, i):
			continue
		var id: StringName = id_of_index.call(i)
		if id != &"" and ItemCatalog.get_item(id) != null:
			owned.append(String(id))


static func _bit(words: PackedInt32Array, index: int) -> bool:
	var word: int = index >> 5
	if word < 0 or word >= words.size():
		return false
	return ((words[word] >> (index & 31)) & 1) == 1


static func _resident_mail(raw: Dictionary, summary: Dictionary) -> Array:
	var out: Array = []
	var bags: Array = []
	var house: Variant = raw.get("house", {})
	if typeof(house) == TYPE_DICTIONARY:
		bags.append((house as Dictionary).get("mailbox", []))
	bags.append(raw.get("mail", []))
	for bag: Variant in bags:
		if typeof(bag) != TYPE_ARRAY:
			continue
		for entry: Variant in bag as Array:
			var saved: Dictionary = _mail_save(entry, summary)
			if saved.is_empty():
				continue
			out.append(saved)
			if out.size() >= Inventory.MAIL_SLOTS:
				return out
	while out.size() < Inventory.MAIL_SLOTS:
		out.append({})
	return out


static func _mail_save(raw: Variant, summary: Dictionary) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY or (raw as Dictionary).is_empty():
		return {}
	var row: Dictionary = raw
	var present: StringName = CodeItems.id_of(int(row.get("present", 0)))
	if present == &"" and int(row.get("present", 0)) != 0:
		summary["skipped_items"] = int(summary["skipped_items"]) + 1
	var recip_type: int = int(row.get("recipient_type", 0))
	var sender_type: int = int(row.get("sender_type", 0))
	var recip_id := StringName(str(row.get("recipient_name", "")))
	var sender_id := StringName(str(row.get("sender_name", "")))
	if recip_type == 1:
		var data: VillagerData = VillagerCatalog.by_npc_index(int(row.get("recipient_npc", 0)) & 0xFFF)
		if data != null:
			recip_id = data.id
	if sender_type == 1:
		var data: VillagerData = VillagerCatalog.by_npc_index(int(row.get("sender_npc", 0)) & 0xFFF)
		if data != null:
			sender_id = data.id
	return {
		"recipient_id": String(recip_id),
		"recipient_name": str(row.get("recipient_name", "")),
		"recipient_type": recip_type if recip_type in [0, 1, 2] else int(MailData.NameType.NPC),
		"sender_id": String(sender_id),
		"sender_name": str(row.get("sender_name", "")),
		"sender_type": sender_type if sender_type in [0, 1, 2] else int(MailData.NameType.PLAYER),
		"present": String(present),
		"present_count": 1,
		"font": int(row.get("font", int(MailData.LetterFont.RECV))),
		"header": str(row.get("header", "")),
		"body": str(row.get("body", "")),
		"footer": str(row.get("footer", "")),
		"paper": int(row.get("paper", 0)),
	}


static func _gyroid_items(gyroid: Dictionary, summary: Dictionary) -> Array:
	var out: Array = []
	for entry: Variant in gyroid.get("items", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = entry
		var number: int = int(row.get("item", 0))
		if number == 0:
			out.append({"item": "", "count": 0, "cond": 0, "exchange": int(GyroidStore.Exchange.FREE), "price": 0})
			continue
		var id: StringName = CodeItems.id_of(number)
		if id == &"":
			summary["skipped_items"] = int(summary["skipped_items"]) + 1
			out.append({"item": "", "count": 0, "cond": 0, "exchange": int(GyroidStore.Exchange.FREE), "price": 0})
			continue
		var exchange: int = clampi(int(row.get("exchange", 0)), 0, int(GyroidStore.Exchange.SALE))
		out.append({
			"item": String(id),
			"count": 1,
			"cond": 0,
			"exchange": exchange,
			"price": int(row.get("extra", 0)) if exchange == int(GyroidStore.Exchange.SALE) else 0,
		})
	return out


static func _ymd_ordinal(raw: Variant) -> int:
	if typeof(raw) != TYPE_DICTIONARY:
		return -1
	var t: Dictionary = raw
	var year: int = int(t.get("year", 0))
	if year <= 0:
		return -1
	return EventDates.ordinal(year, int(t.get("month", 1)), int(t.get("day", 1)))


## Same thresholds as `ShopBook.real_level` (no live shop needed while building the payload).
static func _nook_real_level(sales: int, visitor: bool) -> int:
	if sales >= ShopBook.DSUPER_SUM and visitor:
		return 3
	if sales >= ShopBook.SUPER_SUM:
		return 2
	if sales >= ShopBook.COMBINI_SUM:
		return 1
	return 0
