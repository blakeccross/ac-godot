class_name TitleDemo
extends RefCounted

## Attract-mode rules for the title screen (`m_trademark.c`, `m_titledemo.c`, `m_npc.c`
## `mNpc_SetAnimalTitleDemo`). The recorded input and the fixed FG table are disc-derived
## data under `assets/generated/titledemo/demos.json` (`--kind title`); everything that is a
## rule rather than data lives here.

const DEMO_COUNT := 5
## `title_demo_move`: the demo ends (`mTD_game_end_init`) once this many ticks have run.
const TOTAL_FRAMES := 3600
## `mTD_tdemo_button_ok_check`: START is ignored from this tick on.
const BUTTON_LOCKOUT_FRAME := 3530
const DATA_PATH := "res://assets/generated/titledemo/demos.json"
## World XZ is measured from the outer map corner; the playable town starts one 640-GX
## border block in (`mFI` block 1).
const BORDER_GX := 640.0

## `tradeday_table` (m_trademark.c `mTM_demotime_set`), one row per demo.
const TRADE_DAYS: Array[Dictionary] = [
	{"month": 4, "day": 6, "hour": 13, "weather": &"sakura"},
	{"month": 6, "day": 16, "hour": 13, "weather": &"rain"},
	{"month": 8, "day": 1, "hour": 6, "weather": &"clear"},
	{"month": 11, "day": 1, "hour": 16, "weather": &"clear"},
	{"month": 2, "day": 1, "hour": 2, "weather": &"snow"},
]

## `demo_npc_list` (m_trademark.c): villager, acre (x, z) and unit (x, z) of its home.
## The decomp lists 14 but loops over 15 (`@BUG`); only these 14 are real. `start_*`: where
## the actor is born (`title_demo_actable`, `src/data/field/mvactor/title_demo.c`) — every
## villager, Lobo included although the fixed FG has no house marker for him.
const NPCS: Array[Dictionary] = [
	{"id": &"bob", "bx": 1, "bz": 2, "ux": 3, "uz": 7, "start_bx": 1, "start_bz": 2, "start_ux": 3, "start_uz": 9},
	{"id": &"paolo", "bx": 1, "bz": 2, "ux": 8, "uz": 11, "start_bx": 1, "start_bz": 2, "start_ux": 5, "start_uz": 13},
	{"id": &"vesta", "bx": 1, "bz": 4, "ux": 12, "uz": 11, "start_bx": 1, "start_bz": 4, "start_ux": 11, "start_uz": 14},
	{"id": &"joey", "bx": 2, "bz": 3, "ux": 5, "uz": 6, "start_bx": 2, "start_bz": 3, "start_ux": 7, "start_uz": 7},
	{"id": &"lobo", "bx": 2, "bz": 3, "ux": 4, "uz": 12, "start_bx": 2, "start_bz": 3, "start_ux": 2, "start_uz": 14},
	{"id": &"carrie", "bx": 3, "bz": 5, "ux": 11, "uz": 5, "start_bx": 3, "start_bz": 5, "start_ux": 8, "start_uz": 7},
	{"id": &"tank", "bx": 4, "bz": 3, "ux": 3, "uz": 12, "start_bx": 4, "start_bz": 3, "start_ux": 6, "start_uz": 13},
	{"id": &"buzz", "bx": 4, "bz": 4, "ux": 3, "uz": 4, "start_bx": 4, "start_bz": 4, "start_ux": 6, "start_uz": 5},
	{"id": &"rasher", "bx": 4, "bz": 4, "ux": 12, "uz": 13, "start_bx": 4, "start_bz": 4, "start_ux": 12, "start_uz": 14},
	{"id": &"biff", "bx": 4, "bz": 6, "ux": 5, "uz": 6, "start_bx": 4, "start_bz": 6, "start_ux": 3, "start_uz": 8},
	{"id": &"samson", "bx": 5, "bz": 2, "ux": 12, "uz": 4, "start_bx": 5, "start_bz": 2, "start_ux": 9, "start_uz": 2},
	{"id": &"jane", "bx": 5, "bz": 2, "ux": 9, "uz": 11, "start_bx": 5, "start_bz": 2, "start_ux": 11, "start_uz": 13},
	{"id": &"tybalt", "bx": 5, "bz": 4, "ux": 11, "uz": 4, "start_bx": 5, "start_bz": 4, "start_ux": 7, "start_uz": 3},
	{"id": &"cube", "bx": 5, "bz": 5, "ux": 5, "uz": 11, "start_bx": 5, "start_bz": 5, "start_ux": 5, "start_uz": 5},
]

## Head-table tool word → item id (`mTD_player_keydata_init`). `0x2204` is the gelato umbrella
## (demo 2, in the rain).
const TOOLS := {
	0x2201: &"axe",
	0x2203: &"fishing_rod",
	0x2204: &"gelato_umbrella",
}
## Verbs the scripted A press may trigger. The recordings only ever use tools and pickups; in a
## different town they can end up facing a villager or a door, and the original never lets the
## demo talk, enter buildings or shop.
const SAFE_VERBS: Array[StringName] = [
	Interaction.PICK_UP,
	Interaction.SHAKE,
	Interaction.CHOP,
	Interaction.DIG,
	Interaction.FILL,
	Interaction.WATER,
	Interaction.SWING_NET,
	Interaction.CAST,
	Interaction.AIR_AXE,
	Interaction.HOOK,
	## `Player_actor_CheckController_forUmbrella` reads the demo's A too.
	&"twirl_umbrella",
]
const SHIRT_IDS: Array[StringName] = [&"shirt_000", &"shirt_001", &"shirt_002", &"shirt_003", &"shirt_016"]

## `S_now_demono`: −1 = LOGO (nothing shown yet), then 1..5 cycling (`mTD_demono_get`).
static var _now_demo_no: int = -1
static var _cache: Dictionary = {}


## Advance to and return the next demo, 0-based (`mTD_demono_get` − 1).
static func next_demo_index() -> int:
	if _now_demo_no < 1:
		_now_demo_no = 1
	else:
		_now_demo_no += 1
		if _now_demo_no > DEMO_COUNT:
			_now_demo_no = 1
	return _now_demo_no - 1


static func reset_rotation() -> void:
	_now_demo_no = -1


static func trade_day(index: int) -> Dictionary:
	return TRADE_DAYS[clampi(index, 0, DEMO_COUNT - 1)]


## Parsed `demos.json`, or `{}` when the extraction step has not been run.
static func load_data() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	if not FileAccess.file_exists(DATA_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is Dictionary:
		_cache = parsed as Dictionary
	return _cache


static func has_data() -> bool:
	var demos: Variant = load_data().get("demos", [])
	return demos is Array and (demos as Array).size() == DEMO_COUNT


## The demo town's fixed acre layout (`data_fdd[SCENE_TITLE_DEMO].combi`): `mFM_MakeField`
## only reads a save's random field for `SCENE_FG`, so the attract town is always this
## 7×8 map. Returns `{types, heights, visuals}` sized for the 7×10 `TownFieldGenerator`
## grid (rows 8–9 stay empty), or `{}` when the extraction predates the acre table.
static func acres() -> Dictionary:
	var raw: Variant = load_data().get("acres", {})
	if not raw is Dictionary:
		return {}
	var table: Dictionary = raw as Dictionary
	var cols: int = int(table.get("cols", 0))
	var rows: int = int(table.get("rows", 0))
	var bg: Array = table.get("bg", []) as Array
	var types_in: Array = table.get("types", []) as Array
	var heights_in: Array = table.get("heights", []) as Array
	if cols != TownFieldGenerator.BLOCK_X or rows > TownFieldGenerator.BLOCK_Z:
		return {}
	if bg.size() != cols * rows or types_in.size() != bg.size() or heights_in.size() != bg.size():
		return {}
	var types := PackedByteArray()
	types.resize(TownFieldGenerator.BLOCK_TOTAL)
	types.fill(TownFieldGenerator.T_NONE)
	var heights := PackedByteArray()
	heights.resize(TownFieldGenerator.BLOCK_TOTAL)
	var visuals := PackedStringArray()
	visuals.resize(TownFieldGenerator.BLOCK_TOTAL)
	for i: int in bg.size():
		types[i] = block_type_from_decomp(int(types_in[i]), i / cols)
		heights[i] = int(heights_in[i])
		visuals[i] = String(bg[i])
	return {"types": types, "heights": heights, "visuals": visuals}


## `mFM_BLOCK_TYPE_*` → `TownFieldGenerator` id. The ids match except the ocean-side border
## cliffs (decomp 80/81 collide with the compacted museum/needlework ids), and the plain
## rail acre (`grd_s_t_5` is `mFM_BLOCK_TYPE_NONE` in `data_combi`), which the generator
## calls `T_TRACKS_DUMP`.
static func block_type_from_decomp(decomp_type: int, bz: int) -> int:
	match decomp_type:
		80:
			return TownFieldGenerator.T_BORDER_CLIFF_OCEAN_LEFT
		81:
			return TownFieldGenerator.T_BORDER_CLIFF_OCEAN_RIGHT
		TownFieldGenerator.T_NONE:
			return TownFieldGenerator.T_TRACKS_DUMP if bz == 1 else TownFieldGenerator.T_NONE
	return decomp_type


## `mTRC_go_process` only runs the train control in demo 1 (`mEv_TITLEDEMO_START1`), where
## `mTRC_schedule` parks it at the station (`TrainControl.mati_init`) and never lets it leave
## (control state 1 == last state 1). The other four demos have no train at all.
static func has_parked_train(index: int) -> bool:
	return index == 0


static func demo(index: int) -> Dictionary:
	var demos: Variant = load_data().get("demos", [])
	if demos is Array and index >= 0 and index < (demos as Array).size():
		return (demos as Array)[index] as Dictionary
	return {}


static func keys_for(index: int) -> PackedInt32Array:
	var keys := PackedInt32Array()
	var raw: Variant = demo(index).get("keys", [])
	if raw is Array:
		for word: Variant in raw as Array:
			keys.append(int(word))
	return keys


## Head-table spawn position in GX.
static func spawn_gx(index: int) -> Vector3:
	var pos: Variant = demo(index).get("pos", [])
	if pos is Array and (pos as Array).size() == 3:
		var p: Array = pos as Array
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	return Vector3(2240.0, 0.0, 1600.0)


## Head-table facing. Decomp angle 0 faces +Z, increasing toward +X: yaw = atan2(x, z).
static func spawn_yaw(index: int) -> float:
	return float(int(demo(index).get("angle", 0))) * MLib.S16


static func tool_item_id(index: int) -> StringName:
	return TOOLS.get(int(demo(index).get("tool", 0)), &"") as StringName


## Decomp town position (GX) → world metres inside a generated town.
static func gx_to_world(town: WorldData, gx: Vector3) -> Vector3:
	var local := Vector3(gx.x - BORDER_GX, 0.0, gx.z - BORDER_GX) * FieldCatalog.GX_TO_METERS
	return town.origin() + local


## `mPr_RandomSetPlayerData_title_demo`: `RANDOM(4) & 1` gender, random shirt and face.
static func random_identity(rng: RandomNumberGenerator) -> Dictionary:
	var female: bool = (rng.randi_range(0, 3) & 1) == 1
	return {
		"gender": IntroSequence.GENDER_FEMALE if female else IntroSequence.GENDER_MALE,
		"face": rng.randi_range(0, IntroSequence.FACE_TYPE_NUM - 1),
		"cloth": SHIRT_IDS[rng.randi_range(0, SHIRT_IDS.size() - 1)],
	}


static func allows_verb(verb: StringName) -> bool:
	return SAFE_VERBS.has(verb)


## Ticks elapsed for `seconds` of real time (the demo runs on the 60 Hz frame clock).
static func ticks_for(seconds: float) -> int:
	return int(floorf(seconds * DecompTime.TICK_HZ))


static func button_ok(frame: int) -> bool:
	return frame < BUTTON_LOCKOUT_FRAME


static func is_over(frame: int) -> bool:
	return frame >= TOTAL_FRAMES
