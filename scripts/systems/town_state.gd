class_name TownState
extends Resource

## The town's own saved state outside the per-system books: what lies on the field (weeds,
## shells, mushrooms, signboards, snowmen, the ball, buried things, plants), its rating, the
## weather, the tune and native fruit, and the event bookkeeping of the town. Held by
## `Game.town`. Saved under the same keys as before, so the JSON save format is unchanged.

const DEFAULT_TOWN_NAME := "Town"

var removed_interactables: Array[String] = []
var stump_interactables: Array[String] = []
var hole_interactables: Array[String] = []
## Weeds in the field (`GRASS_A`–`GRASS_C`): `weed_<x>_<z>` → variant 0–2. Saved.
var weeds: Dictionary = {}
## `Save.clear_grass`: a wish has cleared the town of weeds; none grow back (saved).
var clear_grass: bool = false
## Renewals not yet sown with weeds (crossed indoors or while the game was off). Saved.
var weed_days_pending: int = 0
## `mFAs_GetFieldRank`: the town's rating 0–6 from the last assessment.
var field_rank: int = 0
## `Save.good_field`: days in a row at rank 6 and the day last counted (−1 none). Saved.
var perfect_streak: int = 0
var perfect_streak_day: int = -1
## `Save.dust_flag`: trash pushed the rating to nothing; it stays there until it is all gone.
var dust_flag: bool = false
## `mSC_TROPHY_GOLDEN_AXE`: the wishing well has given the golden axe. Saved.
var golden_axe_got: bool = false
## `allgrow_ss_pos_info.stone_pos`: the rock that pays out Bells ("" none or spent). Saved.
var money_rock: String = ""
## The day the money rock was last picked (−1 never), so a spent one waits for tomorrow. Saved.
var money_rock_day: int = -1
## `ITM_FOOD_MUSHROOM` on the field: `mushroom_<x>_<z>` → 1. Saved.
var mushrooms: Dictionary = {}
## Sea shells on the beach (`ShellUse`): `shell_<x>_<z>` → item id. Saved.
var shells: Dictionary = {}
## Signboards the residents put up (`SignboardUse`): `signboard_<x>_<z>` → `{design}`. Saved.
var signboards: Dictionary = {}
## Things lying on the field (`FieldItems`): `fitem_<x>_<z>` → {id, wrapped}. Saved.
var field_items: Dictionary = {}
## The second bridge Tortimer builds (`SecondBridge`, `Save_Get(bridge)`). Saved.
var bridge: Dictionary = {}
## `Save.mushroom_time`: when mushrooms were last set or cleared (`Clock.absolute_minute`, −1
## never) and `active`: a new day has started, so the 8 AM crop may grow. Saved.
var mushroom_minute: int = -1
var mushroom_active: bool = false
## `Save.snowmen`: three slots, each {} or {head, body (sizes 0–1), score, cell [x, z], age}.
var snowmen: Array = [{}, {}, {}]
## `Save.snowman_year…hour` as `Clock.absolute_minute` (−1 never): no new balls until 6 AM.
var snowman_built_minute: int = -1
## The snowman-season balls (`mEv` common place / area): part → {cell [x, z], dist}. Saved.
var snowballs: Dictionary = {}
## The town's ball (`Common_Get(ball_pos)` / `ball_type`), `BallUse`. Saved.
var ball: Dictionary = {}
var plant_states: Dictionary = {}
## Buried dig spots: persist_id → {kind, item_id, cell_x, cell_z} (`mFI` deposit / shine).
var buried_deposits: Dictionary = {}
var world_mode: WorldData.Mode = WorldData.Mode.TEST
var world_seed: int = WorldGenerator.DEFAULT_SEED
## A town brought over from a GameCube save (`TownImport`): {acres: 70 `combi_table` words,
## field: 30 acres × 256 item numbers}. When set, `WorldGenerator` builds that map and what
## stands on it instead of rolling them from `world_seed`. Saved.
var imported_field: Dictionary = {}
## Town grass motif (`bg_tex_idx`): 0 triangle, 1 square, 2 circle.
var grass_pattern: int = WorldData.GrassPattern.TRIANGLE
## `Save_Get(fruit)`: the town's native fruit. Other fruit sells to Nook at the foreign price.
var town_fruit: StringName = &"apple"
var town_name: String = DEFAULT_TOWN_NAME
## This town's identity, so a passport knows its home (`mLd_CheckThisLand`). Random per town.
var town_id: int = 0
## `Save_Get(melody)`: the town tune (`TownTune`), set at the tune board.
var town_tune: PackedByteArray = TownTune.default_notes()
## `Save_Get(num_statues)` — how many Nook house statues the town has built (0..3, gold →
## jade); the next one takes the following rank.
var num_statues: int = 0
## `Save.cheated_flag` / `npc_force_go_home`: the clock was found earlier than the last save
## (`aNPS2_game_start_wait`). Saved; it bars the birthday surprise.
var cheated_flag: bool = false
## Session weather (`mEnv_WEATHER_*`). Rolled by `Weather` on `field_renewed`.
var weather: StringName = &"clear"
## `mEnv_WEATHER_INTENSITY_*` (none/light/normal/heavy).
var weather_intensity: int = int(Weather.Intensity.NONE)
## `Save_Get(gyoei_term)` / `gyoei_term_transition_offset` — for fish: the *next* of the
## 24 half-month terms and how many days (0–5) before it starts its list ramps in
## (`aSOG_gyoei_chk_term_info`). Saved with the town.
var fish_season_term: int = 0
var fish_season_offset: int = 0
var dialogue_vars: Dictionary = {}
## The fishing tourney's records (`Save_Get(fishRecord)`), `FishRecord`. Saved.
var fish_records: Array = []
## `treasure_buried_time` / `treasure_checked_time` as ordinals (0 never). Saved.
var treasure_buried_day: int = 0
## Blanca's face and painter in this town (`Save_Get(mask_cat)`, `MaskCat`).
var mask_cat: Dictionary = {}
## `Save_Get(haniwa_scheduled)`: fine weather after rain orders gyroids for the next growth
## (`mAGrw_OrderSetHaniwa`); `BuriedUse.renew` buries them and clears it.
var gyroids_scheduled: bool = false
## `HOLE_SHINE`: the hole the day's shine spot left (`bIT_common_bury_after`).
var shine_hole: StringName = &""
var treasure_checked_day: int = 0


## Its keys of `Game.to_save()`, written into `out`.
func write_save(out: Dictionary) -> void:
	out["removed_interactables"] = removed_interactables.duplicate()
	out["stump_interactables"] = stump_interactables.duplicate()
	out["hole_interactables"] = hole_interactables.duplicate()
	out["weeds"] = weeds.duplicate()
	out["clear_grass"] = clear_grass
	out["weed_days_pending"] = weed_days_pending
	out["field_rank"] = field_rank
	out["perfect_streak"] = perfect_streak
	out["perfect_streak_day"] = perfect_streak_day
	out["dust_flag"] = dust_flag
	out["golden_axe_got"] = golden_axe_got
	out["money_rock"] = money_rock
	out["money_rock_day"] = money_rock_day
	out["mushrooms"] = mushrooms.duplicate()
	out["shells"] = shells.duplicate()
	out["signboards"] = signboards.duplicate(true)
	out["field_items"] = field_items.duplicate(true)
	out["bridge"] = bridge.duplicate(true)
	out["mushroom_minute"] = mushroom_minute
	out["mushroom_active"] = mushroom_active
	out["snowmen"] = snowmen.duplicate(true)
	out["snowman_built_minute"] = snowman_built_minute
	out["snowballs"] = snowballs.duplicate(true)
	out["ball"] = ball.duplicate()
	out["plants"] = plant_states.duplicate(true)
	out["buried"] = buried_deposits.duplicate(true)
	out["world_mode"] = int(world_mode)
	out["world_seed"] = world_seed
	if not imported_field.is_empty():
		out["imported_field"] = imported_field.duplicate(true)
	out["grass_pattern"] = grass_pattern
	out["town_fruit"] = String(town_fruit)
	out["town_name"] = town_name
	out["num_statues"] = num_statues
	out["cheated_flag"] = cheated_flag
	out["town_tune"] = Array(town_tune)
	out["weather"] = String(weather)
	out["weather_intensity"] = weather_intensity
	out["fish_season_term"] = {"term": fish_season_term, "offset": fish_season_offset}
	out["dialogue_vars"] = dialogue_vars.duplicate(true)
	out["fish_records"] = fish_records.duplicate(true)
	out["treasure_buried_day"] = treasure_buried_day
	out["town_id"] = town_id
	out["mask_cat"] = mask_cat.duplicate(true)
	out["gyroids_scheduled"] = gyroids_scheduled
	out["shine_hole"] = String(shine_hole)
	out["treasure_checked_day"] = treasure_checked_day


## Its part of a `Game.apply_snapshot` dictionary (missing keys take the defaults).
func read_save(data: Dictionary) -> void:
	removed_interactables.clear()
	var removed: Variant = data.get("removed_interactables", [])
	if typeof(removed) == TYPE_ARRAY:
		for entry: Variant in removed:
			removed_interactables.append(str(entry))
	stump_interactables.clear()
	var stumps: Variant = data.get("stump_interactables", [])
	if typeof(stumps) == TYPE_ARRAY:
		for entry: Variant in stumps:
			var key := str(entry)
			if not removed_interactables.has(key):
				stump_interactables.append(key)
	weeds.clear()
	var saved_weeds: Variant = data.get("weeds", {})
	if typeof(saved_weeds) == TYPE_DICTIONARY:
		for key: Variant in saved_weeds:
			weeds[str(key)] = clampi(int(saved_weeds[key]), 0, 2)
	clear_grass = bool(data.get("clear_grass", false))
	weed_days_pending = maxi(int(data.get("weed_days_pending", 0)), 0)
	field_rank = clampi(int(data.get("field_rank", 0)), 0, TownAssessment.RANK_PERFECT)
	perfect_streak = clampi(int(data.get("perfect_streak", 0)), 0, TownAssessment.PERFECT_STREAK_MAX)
	perfect_streak_day = int(data.get("perfect_streak_day", -1))
	dust_flag = bool(data.get("dust_flag", false))
	golden_axe_got = bool(data.get("golden_axe_got", false))
	money_rock = str(data.get("money_rock", ""))
	money_rock_day = int(data.get("money_rock_day", -1))
	signboards.clear()
	var saved_signs: Variant = data.get("signboards", {})
	if typeof(saved_signs) == TYPE_DICTIONARY:
		signboards = (saved_signs as Dictionary).duplicate(true)
	bridge = {}
	var saved_bridge: Variant = data.get("bridge", {})
	if typeof(saved_bridge) == TYPE_DICTIONARY and not (saved_bridge as Dictionary).is_empty():
		bridge = SecondBridge.new_state()
		bridge.merge(saved_bridge as Dictionary, true)
	field_items.clear()
	var saved_items: Variant = data.get("field_items", {})
	if typeof(saved_items) == TYPE_DICTIONARY:
		field_items = (saved_items as Dictionary).duplicate(true)
	shells.clear()
	var saved_shells: Variant = data.get("shells", {})
	if typeof(saved_shells) == TYPE_DICTIONARY:
		for key: Variant in saved_shells:
			shells[str(key)] = str(saved_shells[key])
	mushrooms.clear()
	var saved_mushrooms: Variant = data.get("mushrooms", {})
	if typeof(saved_mushrooms) == TYPE_DICTIONARY:
		for key: Variant in saved_mushrooms:
			mushrooms[str(key)] = 1
	mushroom_minute = int(data.get("mushroom_minute", -1))
	mushroom_active = bool(data.get("mushroom_active", false))
	snowmen = [{}, {}, {}]
	var saved_snowmen: Variant = data.get("snowmen", [])
	if typeof(saved_snowmen) == TYPE_ARRAY:
		for i: int in mini((saved_snowmen as Array).size(), SnowmanRules.SAVE_COUNT):
			var e: Variant = saved_snowmen[i]
			if typeof(e) == TYPE_DICTIONARY and not (e as Dictionary).is_empty():
				snowmen[i] = (e as Dictionary).duplicate(true)
	snowman_built_minute = int(data.get("snowman_built_minute", -1))
	ball = (data.get("ball", {}) as Dictionary).duplicate() if typeof(data.get("ball", {})) == TYPE_DICTIONARY else {}
	snowballs.clear()
	var saved_balls: Variant = data.get("snowballs", {})
	if typeof(saved_balls) == TYPE_DICTIONARY:
		for key: Variant in saved_balls:
			if typeof(saved_balls[key]) == TYPE_DICTIONARY:
				snowballs[int(key)] = (saved_balls[key] as Dictionary).duplicate(true)
	hole_interactables.clear()
	var holes: Variant = data.get("hole_interactables", [])
	if typeof(holes) == TYPE_ARRAY:
		for entry: Variant in holes:
			hole_interactables.append(str(entry))
	plant_states.clear()
	var plants: Variant = data.get("plants", {})
	if typeof(plants) == TYPE_DICTIONARY:
		for key: Variant in (plants as Dictionary).keys():
			var rec: Variant = plants[key]
			if typeof(rec) == TYPE_DICTIONARY:
				plant_states[str(key)] = (rec as Dictionary).duplicate()
	buried_deposits.clear()
	var buried: Variant = data.get("buried", {})
	if typeof(buried) == TYPE_DICTIONARY:
		for key: Variant in (buried as Dictionary).keys():
			var rec: Variant = buried[key]
			if typeof(rec) == TYPE_DICTIONARY:
				buried_deposits[str(key)] = (rec as Dictionary).duplicate()
	world_mode = int(data.get("world_mode", WorldData.Mode.TEST)) as WorldData.Mode
	world_seed = int(data.get("world_seed", WorldGenerator.DEFAULT_SEED))
	var saved_field: Variant = data.get("imported_field", {})
	imported_field = (saved_field as Dictionary).duplicate(true) if typeof(saved_field) == TYPE_DICTIONARY else {}
	if data.has("grass_pattern"):
		grass_pattern = WorldData.clamp_grass_pattern(int(data["grass_pattern"]))
	elif world_mode == WorldData.Mode.GENERATED:
		grass_pattern = WorldGenerator.decide_grass_pattern(world_seed)
	else:
		grass_pattern = WorldData.GrassPattern.TRIANGLE
	town_fruit = StringName(str(data.get("town_fruit", "apple")))
	treasure_buried_day = int(data.get("treasure_buried_day", 0))
	town_id = int(data.get("town_id", 0))
	mask_cat = (data.get("mask_cat", {}) as Dictionary).duplicate(true) if typeof(data.get("mask_cat")) == TYPE_DICTIONARY else {}
	if town_id == 0:
		town_id = Travel.new_town_id()
	gyroids_scheduled = bool(data.get("gyroids_scheduled", false))
	shine_hole = StringName(str(data.get("shine_hole", "")))
	treasure_checked_day = int(data.get("treasure_checked_day", 0))
	fish_records.clear()
	var saved_fish: Variant = data.get("fish_records", [])
	if typeof(saved_fish) == TYPE_ARRAY:
		for r: Variant in saved_fish:
			if typeof(r) == TYPE_DICTIONARY:
				var rec: Dictionary = r
				fish_records.append({"name": str(rec.get("name", "")), "player": bool(rec.get("player", false)),
					"size": int(rec.get("size", 0)), "ordinal": int(rec.get("ordinal", 0)),
					"minute": int(rec.get("minute", 0)), "settled": bool(rec.get("settled", false))})
	town_name = str(data.get("town_name", DEFAULT_TOWN_NAME))
	num_statues = clampi(int(data.get("num_statues", 0)), 0, 3)
	cheated_flag = bool(data.get("cheated_flag", false))
	town_tune = TownTune.sanitize(data.get("town_tune", null))
	weather = StringName(str(data.get("weather", "clear")))
	if data.has("weather_intensity"):
		weather_intensity = int(data["weather_intensity"])
	elif data.has("weather_packed"):
		var unpacked: Dictionary = Weather.unpack(int(data["weather_packed"]))
		weather = Weather.kind_name(unpacked["kind"] as Weather.Kind)
		weather_intensity = int(unpacked["intensity"])
	else:
		weather_intensity = int(Weather.default_intensity_for(Weather.kind_from_name(weather)))
	## `Save_Get(gyoei_term)`: the fish ramp's next term and its 0–5 day lead.
	var fish_term: Dictionary = data.get("fish_season_term", {})
	fish_season_term = clampi(int(fish_term.get("term", 0)), 0, 23)
	fish_season_offset = clampi(int(fish_term.get("offset", 0)), 0, 5)
	dialogue_vars.clear()
	var vars_raw: Variant = data.get("dialogue_vars", {})
	if typeof(vars_raw) == TYPE_DICTIONARY:
		dialogue_vars = (vars_raw as Dictionary).duplicate(true)


## A new town's values (`Game.reset_session`).
func reset() -> void:
	town_id = Travel.new_town_id()
	mask_cat = {}
	fish_season_term = 0
	fish_season_offset = 0
	fish_records.clear()
	treasure_buried_day = 0
	gyroids_scheduled = false
	shine_hole = &""
	treasure_checked_day = 0
	removed_interactables.clear()
	stump_interactables.clear()
	hole_interactables.clear()
	weeds.clear()
	clear_grass = false
	weed_days_pending = 0
	field_rank = 0
	perfect_streak = 0
	perfect_streak_day = -1
	dust_flag = false
	golden_axe_got = false
	money_rock = ""
	money_rock_day = -1
	mushrooms.clear()
	shells.clear()
	signboards.clear()
	field_items.clear()
	bridge = {}
	mushroom_minute = -1
	mushroom_active = false
	snowmen = [{}, {}, {}]
	snowman_built_minute = -1
	ball = {}
	snowballs.clear()
	plant_states.clear()
	buried_deposits.clear()
	town_name = DEFAULT_TOWN_NAME
	num_statues = 0
	cheated_flag = false
	town_tune = TownTune.default_notes()
	weather = &"clear"
	weather_intensity = int(Weather.Intensity.NONE)
	dialogue_vars.clear()
	world_mode = WorldData.Mode.TEST
	world_seed = WorldGenerator.DEFAULT_SEED
	imported_field = {}
	grass_pattern = WorldData.GrassPattern.TRIANGLE
	town_fruit = &"apple"
