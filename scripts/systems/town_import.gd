class_name TownImport
extends RefCounted

## Turns a GameCube town (`GameCubeTown.decode`) into this game's save: the town's name, id,
## tune, fruit and grass, its real acre map and what stands on it (kept as `imported_field`,
## which `WorldGenerator` builds the field from instead of random picks), weeds, items lying
## out and buried things, the villagers in their own houses, and each resident's name, looks,
## shirt, pockets, money, loan and house size and plot. Everything else starts the way a new
## town's does. The original's clock is the GameCube's real-time clock, so the imported town
## starts at the computer's time.
##
## `build` returns `{payload, summary}`: `payload` is a `SaveService` file, `summary` counts
## what came across ({town_name, residents, villagers, items, skipped_items, skipped_villagers}).

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


static func build(town: Dictionary) -> Dictionary:
	var summary: Dictionary = {
		"town_name": str(town.get("town_name", "")),
		"residents": 0,
		"villagers": 0,
		"items": 0,
		"skipped_items": 0,
		"skipped_villagers": 0,
	}
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
		slots.append(_resident(raw, summary))
		summary["residents"] = int(summary["residents"]) + 1
		if current < 0:
			current = i
	world["roster"] = {"current": maxi(current, 0), "slots": slots}
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
		rows.append({"id": String(data.id), "home": [home.x, home.y], "moved_in": bool(v.get("moved_in", false))})
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
static func _resident(raw: Dictionary, summary: Dictionary) -> Dictionary:
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
	return {
		"player_name": str(raw.get("name", "")),
		"player_gender": String(gender),
		"player_face": clampi(int(raw.get("face", 0)), 0, IntroSequence.FACE_TYPE_NUM - 1),
		"cloth_id": String(cloth),
		"has_map": true,
		"first_job": {"kind": int(FirstJob.Kind.DONE)},
		PlayerRoster.KEY_INVENTORY: {
			"slots": pockets,
			"wallet": int(raw.get("wallet", 0)),
			"savings": int(raw.get("savings", 0)),
			"loan": int(raw.get("loan", 0)),
		},
		PlayerRoster.KEY_HOUSE: {
			"id": String(InteriorCatalog.PLAYER_HOUSE_ID),
			"outdoor_building_id": String(FieldObjectCatalog.player_plot_id(int(house.get("plot", 0)))),
			"size_tier": size,
			"next_size_tier": clampi(int(house.get("next_size", size)), 0, int(House.SizeTier.STATUE)),
			"has_basement": bool(house.get("has_basement", false)),
			"statue_rank": clampi(int(house.get("statue_rank", 0)), 0, 3),
			"outlook_pal": clampi(int(house.get("roof", 0)), 0, House.OUTLOOK_PAL_COUNT - 1),
		},
	}
