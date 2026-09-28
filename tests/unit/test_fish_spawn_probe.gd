extends GdUnitTestSuite

## Fish spawning, against `ac_set_ovl_gyoei.c`: which list an acre fishes from, the
## half-month ramp, the sub-area retry, the per-species unit filter, and the one-attempt-
## per-acre-entry / cull loop in `FishSchool`.

const S := preload("res://scripts/systems/fish_spawn_scheduler.gd")


func before_test() -> void:
	Game.reset_session()
	FishCatalog.reload()
	FishSpawnScheduler.reload()
	Clock.reset_to_default()
	Clock.paused = true
	Clock.year = 2001
	Game.weather = &"clear"


func after_test() -> void:
	Clock.reset_to_default()
	Clock.paused = false
	Game.weather = &"clear"


func _at(month: int, day: int, hour: int, minute: int = 0) -> void:
	Clock.month = month
	Clock.day = day
	Clock.hour = hour
	Clock.minute = minute
	Clock.second = 0


## Pin the saved term so the ramp is out of the way.
func _settle() -> void:
	var now_term: int = (Clock.month - 1) * 2 + (1 if Clock.day > 15 else 0)
	Game.gyoei_term = 0 if now_term == 23 else now_term + 1
	Game.gyoei_term_offset = 0


func _types(pool: Array) -> Array[int]:
	var out: Array[int] = []
	for e: Dictionary in pool:
		out.append(int(e["type_index"]))
	return out


func _weight_of(pool: Array, type_index: int) -> float:
	var total := 0.0
	for e: Dictionary in pool:
		if int(e["type_index"]) == type_index:
			total += float(e["weight"])
	return total


# ---- tables -------------------------------------------------------

func test_pond_is_fished_out_from_the_sixteenth_of_september() -> void:
	## `p_month[8] = { p_begining_september, NULL }`.
	_at(9, 10, 12)
	_settle()
	assert_array(_types(S.make_range_data(0, false, null, 0))).contains([32])
	_at(9, 20, 12)
	_settle()
	assert_array(S.make_range_data(0, false, null, 0)).is_empty()
	_at(1, 10, 12)
	_settle()
	assert_array(S.make_range_data(0, false, null, 0)).is_empty()


## The coarse per-species rows (museum, encyclopedia, `FishCatalog.available`) are the
## union of the spawn table: every month, slot and water a species appears in, and its
## heaviest weight. `SALMON2` (44) is the river-mouth salmon.
func test_species_rows_agree_with_the_spawn_table() -> void:
	S.ensure_loaded()
	var keys := {"river": WaterBodies.Kind.RIVER, "sea": WaterBodies.Kind.OCEAN, "pond": WaterBodies.Kind.POND}
	var seen: Dictionary = {}
	for term: int in 24:
		for key: String in keys:
			for slot: int in 4:
				for e: Dictionary in S._slot_entries(term, key, slot):
					var t: int = int(e["type_index"])
					if t == S.TYPE_SALMON2:
						t = S.TYPE_SALMON
					var row: Dictionary = seen.get(t, {"months": {}, "slots": {}, "waters": {}, "w": 0})
					row["months"][term / 2 + 1] = true
					row["slots"][slot] = true
					row["waters"][int(keys[key])] = true
					row["w"] = maxi(int(row["w"]), int(e["weight"]))
					seen[t] = row
	for t: int in seen:
		var fish: FishData = FishCatalog.get_by_type(t)
		var row: Dictionary = seen[t]
		var months: Array = row["months"].keys()
		months.sort()
		var want_months: Array = [] if months.size() == 12 else months
		var slots: Array = row["slots"].keys()
		slots.sort()
		var want_slots: Array = [] if slots.size() == 4 else slots
		var waters: Array = row["waters"].keys()
		waters.sort()
		var got_waters: Array = Array(fish.waters)
		got_waters.sort()
		assert_array(Array(fish.months)).override_failure_message("%s months" % fish.id).is_equal(want_months)
		assert_array(Array(fish.time_slots)).override_failure_message("%s slots" % fish.id).is_equal(want_slots)
		assert_array(got_waters).override_failure_message("%s waters" % fish.id).is_equal(waters)
		assert_int(fish.rarity_weight).override_failure_message("%s weight" % fish.id).is_equal(int(row["w"]))


func test_block_kinds_follow_the_block_info_table() -> void:
	assert_int(S.block_kind_for_type(TownFieldGenerator.T_FLAT)).is_equal(0)
	assert_int(S.block_kind_for_type(TownFieldGenerator.T_RIVER_S)).is_equal(S.KIND_RIVER)
	assert_int(S.block_kind_for_type(TownFieldGenerator.T_RIVER_S_BRIDGE)).is_equal(S.KIND_RIVER | S.KIND_BRIDGE)
	assert_int(S.block_kind_for_type(TownFieldGenerator.T_WF_H)).is_equal(S.KIND_RIVER | S.KIND_WATERFALL)
	assert_int(S.block_kind_for_type(69)).is_equal(S.KIND_RIVER | S.KIND_POOL)
	assert_int(S.block_kind_for_type(TownFieldGenerator.T_BEACH)).is_equal(S.KIND_MARINE)
	assert_int(S.block_kind_for_type(TownFieldGenerator.T_BEACH_RIVER)).is_equal(S.KIND_MARINE | S.KIND_RIVER)
	assert_int(S.block_kind_for_type(TownFieldGenerator.T_PORT)).is_equal(S.KIND_MARINE)
	assert_int(S.block_kind_for_type(TownFieldGenerator.T_OCEAN_2)).is_equal(S.KIND_MARINE | S.KIND_OFFING)
	assert_int(S.block_kind_for_type(TownFieldGenerator.T_ISLAND_LEFT)).is_equal(S.KIND_MARINE | S.KIND_ISLAND)
	assert_int(S.block_kind_for_type(TownFieldGenerator.T_LIGHTHOUSE)).is_equal(0)
	## The border river acre carries only `RIVER0`, not `RIVER`.
	assert_int(S.block_kind_for_type(TownFieldGenerator.T_BORDER_CLIFF_RIVER)).is_equal(0)


func test_each_block_kind_fishes_its_own_list() -> void:
	_at(6, 10, 12)
	_settle()
	var river: Array[int] = _types(S.make_range_data(S.KIND_RIVER, false, null, 0))
	var sea: Array[int] = _types(S.make_range_data(S.KIND_MARINE, false, null, 0))
	var pond: Array[int] = _types(S.make_range_data(0, false, null, 0))
	assert_array(sea).contains([36, 37])
	assert_array(sea).not_contains([2, 32])
	assert_array(river).contains([2])
	assert_array(river).not_contains([36, 32])
	assert_array(pond).contains([32])
	assert_array(pond).not_contains([2, 36])
	## A beach with a river mouth is marine first: the sea list, never the river list.
	var mouth: Array[int] = _types(S.make_range_data(S.KIND_MARINE | S.KIND_RIVER, false, null, 0))
	assert_array(mouth).is_equal(sea)


func test_offing_scales_the_sea_list_and_adds_the_whale() -> void:
	_at(6, 10, 12)
	_settle()
	var sea: Array = S.make_range_data(S.KIND_MARINE, false, null, 0)
	var offing: Array = S.make_range_data(S.KIND_MARINE | S.KIND_OFFING, false, null, 0)
	assert_float(_weight_of(offing, 36)).is_equal_approx(_weight_of(sea, 36) * 10.0, 0.001)
	assert_float(_weight_of(offing, S.TYPE_WHALE)).is_equal_approx(1.0, 0.001)
	assert_float(_weight_of(sea, S.TYPE_WHALE)).is_equal(0.0)


func test_island_uses_its_own_list() -> void:
	_at(1, 10, 12)
	_settle()
	var island: Array = S.make_range_data(S.KIND_MARINE | S.KIND_ISLAND, false, null, 0)
	assert_array(_types(island)).is_equal([36, 37, 38])
	assert_float(_weight_of(island, 38)).is_equal_approx(3.0, 0.001)


func test_tourney_swaps_pool_bridge_and_waterfall_acres_to_bass_three_times_in_four() -> void:
	_at(6, 3, 12)
	_settle()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var swapped := 0
	for _i: int in 400:
		if S.check_fishing_event(S.KIND_RIVER | S.KIND_BRIDGE, rng, 1):
			swapped += 1
	assert_int(swapped).is_between(260, 340)
	## Plain river acres never swap; nothing swaps without a tourney.
	for _i: int in 50:
		assert_bool(S.check_fishing_event(S.KIND_RIVER, rng, 1)).is_false()
		assert_bool(S.check_fishing_event(S.KIND_RIVER | S.KIND_POOL, rng, 0)).is_false()
	## The day slot is `f_bs_t1`: small 50, bass 40, large 10.
	S.ensure_loaded()
	var bass: Array = S._raw(S._event, int(FishData.TimeSlot.DAY))
	assert_array(_types(bass)).is_equal([5, 6, 7])
	assert_int(int(bass[0]["weight"])).is_equal(50)


# ---- coelacanth ---------------------------------------------------

func test_coelacanth_weighs_two_and_needs_rain_outside_the_day_slot() -> void:
	_at(6, 10, 2)
	_settle()
	var wet: Array = S.make_range_data(S.KIND_MARINE, true, null, 0)
	assert_float(_weight_of(wet, S.TYPE_COELACANTH)).is_equal_approx(2.0, 0.001)
	assert_float(_weight_of(S.make_range_data(S.KIND_MARINE, false, null, 0), 31)).is_equal(0.0)
	## 9am–3:59pm is `aSOG_TIME_2`: no coelacanth even in rain.
	_at(6, 10, 12)
	assert_float(_weight_of(S.make_range_data(S.KIND_MARINE, true, null, 0), 31)).is_equal(0.0)
	## Rivers never get it.
	_at(6, 10, 2)
	assert_float(_weight_of(S.make_range_data(S.KIND_RIVER, true, null, 0), 31)).is_equal(0.0)


# ---- the half-month ramp -------------------------------------------

func test_next_term_ramps_in_before_it_starts() -> void:
	## Saved: next is September first half (16), five days' lead → ramp from Aug 27.
	Game.gyoei_term = 16
	Game.gyoei_term_offset = 5
	_at(8, 27, 0)
	var info: Dictionary = S.chk_term_info(null)
	assert_float(float(info["term0_rate"])).is_equal(1.0)  ## midnight on the dot is not "over"
	_at(8, 27, 12)
	info = S.chk_term_info(null)
	assert_int(int(info["term0"])).is_equal(15)
	assert_int(int(info["term1"])).is_equal(16)
	assert_float(float(info["term0_rate"])).is_equal_approx(5.0 / 6.0, 0.0001)
	_at(8, 31, 12)
	info = S.chk_term_info(null)
	assert_float(float(info["term0_rate"])).is_equal_approx(1.0 / 6.0, 0.0001)
	## Sep 1: the ramp is over, the saved term moves on to Sep second half.
	_at(9, 1, 12)
	info = S.chk_term_info(null)
	assert_int(int(info["term0"])).is_equal(16)
	assert_float(float(info["term0_rate"])).is_equal(1.0)
	assert_int(Game.gyoei_term).is_equal(17)
	assert_int(Game.gyoei_term_offset).is_between(0, 5)


func test_ramp_blends_the_current_list_down_and_the_next_one_up() -> void:
	Game.gyoei_term = 16
	Game.gyoei_term_offset = 5
	_at(8, 28, 12)  ## second ramp day: current 4/6, next 2/6
	var pool: Array = S.make_range_data(0, false, null, 0)
	## Crawfish is 20 in both halves, so the two shares sum back to 20.
	assert_float(_weight_of(pool, 32)).is_equal_approx(20.0, 0.001)
	## Killifish (3) and frog (15) are August-only: they fade to 4/6.
	assert_float(_weight_of(pool, 34)).is_equal_approx(3.0 * 4.0 / 6.0, 0.001)
	assert_float(_weight_of(pool, 33)).is_equal_approx(15.0 * 4.0 / 6.0, 0.001)


func test_second_half_ramp_counts_back_from_the_fifteenth() -> void:
	Game.gyoei_term = 17  ## Sep second half
	Game.gyoei_term_offset = 0
	_at(9, 15, 12)
	var info: Dictionary = S.chk_term_info(null)
	assert_int(int(info["term0"])).is_equal(16)
	assert_int(int(info["term1"])).is_equal(17)
	assert_float(float(info["term0_rate"])).is_equal_approx(5.0 / 6.0, 0.0001)
	_at(9, 14, 12)
	assert_float(float(S.chk_term_info(null)["term0_rate"])).is_equal(1.0)


func test_a_stale_saved_term_resets_without_a_ramp() -> void:
	Game.gyoei_term = 5
	Game.gyoei_term_offset = 3
	_at(9, 3, 12)
	var info: Dictionary = S.chk_term_info(null)
	assert_float(float(info["term0_rate"])).is_equal(1.0)
	assert_int(Game.gyoei_term).is_equal(17)


func test_the_saved_term_survives_a_save() -> void:
	Game.gyoei_term = 17
	Game.gyoei_term_offset = 4
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	assert_int(Game.gyoei_term).is_equal(0)
	Game.apply_snapshot(snap)
	assert_int(Game.gyoei_term).is_equal(17)
	assert_int(Game.gyoei_term_offset).is_equal(4)


func test_december_ramps_into_january_across_the_year() -> void:
	Game.gyoei_term = 0
	Game.gyoei_term_offset = 2
	_at(12, 30, 12)  ## Jan 1 next year − 2 days = Dec 30
	var info: Dictionary = S.chk_term_info(null)
	assert_int(int(info["term0"])).is_equal(23)
	assert_int(int(info["term1"])).is_equal(0)
	assert_float(float(info["term0_rate"])).is_equal_approx(5.0 / 6.0, 0.0001)


# ---- the roll -----------------------------------------------------

func test_a_sub_area_the_acre_lacks_is_struck_and_rerolled() -> void:
	var pool: Array = [
		{"type_index": 1, "spawn_area": S.Area.POOL, "weight": 100.0},
		{"type_index": 0, "spawn_area": S.Area.RIVER, "weight": 1.0},
	]
	var rng := RandomNumberGenerator.new()
	for i: int in 50:
		rng.seed = i
		assert_int(S.get_idx(pool, S.KIND_RIVER, rng)).is_equal(1)
	var hits := 0
	for i: int in 50:
		rng.seed = i
		if S.get_idx(pool, S.KIND_RIVER | S.KIND_POOL, rng) == 0:
			hits += 1
	assert_int(hits).is_greater(40)
	## Nothing this acre can hold: no fish at all.
	assert_int(S.get_idx([pool[0]], S.KIND_RIVER, rng)).is_equal(-1)


func test_a_poor_town_rank_leaves_acres_empty() -> void:
	## `env_rate_table`: rank 0 scales every weight by 0.5 inside the walk but not the total,
	## so half the rolls land on nothing.
	var pool: Array = [{"type_index": 0, "spawn_area": S.Area.RIVER, "weight": 10.0}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var keep: int = Game.events.field_rank
	Game.events.field_rank = 0
	var empty := 0
	for _i: int in 400:
		if S.get_idx(pool, S.KIND_RIVER, rng) == -1:
			empty += 1
	Game.events.field_rank = keep
	assert_int(empty).is_between(160, 240)
	for _i: int in 50:
		assert_int(S.get_idx(pool, S.KIND_RIVER, rng)).is_equal(0)


func test_place_check_matches_the_us_rules() -> void:
	assert_bool(S.place_check(S.Area.WATERFALL, S.KIND_RIVER)).is_false()
	assert_bool(S.place_check(S.Area.WATERFALL, S.KIND_RIVER | S.KIND_WATERFALL)).is_true()
	assert_bool(S.place_check(S.Area.POOL, S.KIND_RIVER | S.KIND_BRIDGE)).is_false()
	## GAFE01: a river mouth only needs the RIVER bit (the AUS build also wants MARINE).
	assert_bool(S.place_check(S.Area.RIVER_MOUTH, S.KIND_MARINE)).is_false()
	assert_bool(S.place_check(S.Area.RIVER_MOUTH, S.KIND_MARINE | S.KIND_RIVER)).is_true()
	assert_bool(S.place_check(S.Area.SEA, 0)).is_true()


func test_species_units_follow_set_gyoei_data() -> void:
	## Inner 12×12 only.
	assert_bool(S.unit_accepts(0, 1, 8, S.ATTR_WATER, 0.0)).is_false()
	assert_bool(S.unit_accepts(0, 2, 8, S.ATTR_WATER, 0.0)).is_true()
	assert_bool(S.unit_accepts(0, 14, 8, S.ATTR_WATER, 0.0)).is_false()
	## Large char: the waterfall unit only.
	assert_bool(S.unit_accepts(S.TYPE_LARGE_CHAR, 8, 8, S.ATTR_WATER, 0.0)).is_false()
	assert_bool(S.unit_accepts(S.TYPE_LARGE_CHAR, 8, 8, S.ATTR_WATERFALL, 0.0)).is_true()
	## Sea fish: deep sea only (surface 20 GX, need 20 GX of water).
	assert_bool(S.unit_accepts(S.TYPE_SEA_BASS, 8, 8, S.ATTR_SEA, 0.0)).is_true()
	assert_bool(S.unit_accepts(S.TYPE_SEA_BASS, 8, 8, S.ATTR_SEA, 10.0)).is_false()
	assert_bool(S.unit_accepts(S.TYPE_SEA_BASS, 8, 8, S.ATTR_WATER, 0.0)).is_false()
	## Salmon: river water anywhere, sea only where deep.
	assert_bool(S.unit_accepts(S.TYPE_SALMON2, 8, 8, 16, 60.0)).is_true()
	assert_bool(S.unit_accepts(S.TYPE_SALMON2, 8, 8, S.ATTR_SEA, 10.0)).is_false()
	## River fish can sit on sea water if the list offers them there (default: any water).
	assert_bool(S.unit_accepts(2, 8, 8, S.ATTR_SEA, 10.0)).is_true()
	## Whale: units 5..10.
	assert_bool(S.unit_accepts(S.TYPE_WHALE, 4, 8, S.ATTR_SEA, 0.0)).is_false()
	assert_bool(S.unit_accepts(S.TYPE_WHALE, 5, 10, S.ATTR_SEA, 0.0)).is_true()


func test_large_char_spawns_at_the_foot_of_its_waterfall() -> void:
	assert_that(S.spawn_offset(S.TYPE_LARGE_CHAR, true)).is_equal(Vector2(0.5, 1.0))
	assert_that(S.spawn_offset(S.TYPE_LARGE_CHAR, false)).is_equal(Vector2(0.5, 0.5))
	assert_that(S.spawn_offset(2, true)).is_equal(Vector2.ZERO)


# ---- FishSchool ---------------------------------------------------

## Two acres side by side (32×16 cells), a river through both.
func _two_acre_school() -> Dictionary:
	var grid := WorldGrid.new()
	grid.configure(32, 16, 2.0, Vector3.ZERO)
	for x: int in 32:
		for z: int in range(6, 9):
			grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.WATER)
	var school := FishSchool.new()
	school.configure(grid, 0.0)
	school.seed_rng(3)
	return {"grid": grid, "school": school}


func _sense(grid: WorldGrid, cell: Vector2i) -> FishShadow.Sense:
	var sense := FishShadow.Sense.new()
	sense.player_position = grid.cell_to_world(cell)
	return sense


func test_one_attempt_per_acre_entry() -> void:
	_at(7, 10, 12)
	_settle()
	var w := _two_acre_school()
	var school: FishSchool = w["school"]
	var grid: WorldGrid = w["grid"]
	var sense := _sense(grid, Vector2i(4, 4))
	for _i: int in 200:
		school.tick(DecompTime.TICK_SEC * 4.0, sense)
	## However long the player stands there, one acre gives one fish at most.
	assert_int(school.shadow_count()).is_less_equal(1)


func test_an_acre_with_a_live_fish_does_not_restock() -> void:
	_at(7, 10, 12)
	_settle()
	var w := _two_acre_school()
	var school: FishSchool = w["school"]
	var first: FishShadow = null
	for i: int in 30:
		school.seed_rng(i)
		first = school.try_spawn_in_acre(Vector2i(1, 1), 0)
		if first != null:
			break
	assert_that(first).is_not_null()
	for i: int in 30:
		assert_that(school.try_spawn_in_acre(Vector2i(1, 1), 0)).is_null()
	## Fish spawn on a unit corner inside the acre's inner 12×12.
	var cell: Vector2i = (w["grid"] as WorldGrid).world_to_cell(first.position)
	assert_int(cell.x).is_between(2, 13)
	assert_int(cell.y).is_between(2, 13)


func test_at_most_two_shadows_across_acres() -> void:
	_at(7, 10, 12)
	_settle()
	var grid := WorldGrid.new()
	grid.configure(48, 16, 2.0, Vector3.ZERO)
	for x: int in 48:
		for z: int in range(6, 9):
			grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.WATER)
	var school := FishSchool.new()
	school.configure(grid, 0.0)
	for acre_x: int in [1, 2, 3]:
		for i: int in 40:
			school.seed_rng(i * 7 + acre_x)
			if school.try_spawn_in_acre(Vector2i(acre_x, 1), 0) != null:
				break
	assert_int(school.shadow_count()).is_equal(FishSchool.MAX_SHADOWS)


func test_a_fish_left_behind_is_culled_and_the_acre_restocks_on_return() -> void:
	_at(7, 10, 12)
	_settle()
	var w := _two_acre_school()
	var school: FishSchool = w["school"]
	var grid: WorldGrid = w["grid"]
	for i: int in 30:
		school.seed_rng(i)
		if school.try_spawn_in_acre(Vector2i(1, 1), 0) != null:
			break
	assert_int(school.shadow_count()).is_equal(1)
	var fish: FishShadow = school.shadows[0]
	## Still close (within 600 GX = 30 m) though in the other acre: kept.
	var near := FishShadow.Sense.new()
	near.player_position = fish.position + Vector3(20.0, 0.0, 0.0)
	school.auto_spawn = false
	school.tick(DecompTime.TICK_SEC, near)
	assert_int(school.shadow_count()).is_equal(1)
	## Past 600 GX and in another acre: gone.
	var far := FishShadow.Sense.new()
	far.player_position = fish.position + Vector3(31.0, 0.0, 0.0)
	school.tick(DecompTime.TICK_SEC, far)
	assert_int(school.shadow_count()).is_equal(0)
	assert_bool(school.acre_has_fish(Vector2i(1, 1))).is_false()


func test_empty_pond_in_winter_stocked_in_summer() -> void:
	var grid := WorldGrid.new()
	grid.configure(16, 16, 2.0, Vector3.ZERO)
	for z: int in range(5, 11):
		for x: int in range(5, 11):
			grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.WATER)
	var school := FishSchool.new()
	school.configure(grid, 0.0)
	_at(1, 10, 12)
	_settle()
	for i: int in 40:
		school.seed_rng(i)
		assert_that(school.try_spawn_in_acre(Vector2i(1, 1), 0)).is_null()
	_at(6, 10, 12)
	_settle()
	var seen: Dictionary = {}
	for i: int in 60:
		school.clear()
		school.seed_rng(i)
		var shadow: FishShadow = school.try_spawn_in_acre(Vector2i(1, 1), 0)
		if shadow != null:
			seen[shadow.fish.id] = true
	assert_bool(seen.is_empty()).is_false()
	for id: StringName in seen:
		assert_array([&"crawfish", &"frog", &"killifish"]).contains([id])


## The generated town: every acre fishes only what its block kind allows.
func test_generated_town_species_stay_in_their_acres() -> void:
	var data: WorldData = WorldGenerator.generate(42)
	data.bake()
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var school := FishSchool.new()
	school.configure(grid, 0.0, data)
	var sea_only := [S.TYPE_JELLYFISH, S.TYPE_SEA_BASS, S.TYPE_RED_SNAPPER, S.TYPE_BARRED_KNIFEJAW]
	var checked := 0
	for month: int in [3, 7, 9]:
		_at(month, 10, 6)
		_settle()
		for bz: int in range(VillagerWalk.FG_Z0, VillagerWalk.FG_Z1 + 1):
			for bx: int in range(VillagerWalk.FG_X0, VillagerWalk.FG_X1 + 1):
				var acre := Vector2i(bx, bz)
				var kind: int = school.block_kind(acre)
				for i: int in 6:
					school.clear()
					school.seed_rng(i + bx * 31 + bz * 131 + month)
					var shadow: FishShadow = school.try_spawn_in_acre(acre, 0)
					if shadow == null:
						continue
					checked += 1
					var t: int = FishData.TYPE_IDS.find(shadow.fish.id)
					if t in sea_only:
						assert_int(kind & S.KIND_MARINE).is_equal(S.KIND_MARINE)
					if t == S.TYPE_LARGE_CHAR:
						assert_int(kind & S.KIND_WATERFALL).is_equal(S.KIND_WATERFALL)
					if t in [1, 9, 10]:  ## brook trout, giant catfish, giant snakehead
						assert_int(kind & S.KIND_POOL).is_equal(S.KIND_POOL)
					if t in [32, 33]:  ## crawfish, frog: the pond list
						assert_int(kind & (S.KIND_RIVER | S.KIND_MARINE)).is_equal(0)
					## Spawn point inside the acre's inner units.
					var cell: Vector2i = grid.world_to_cell(shadow.position)
					assert_that(VillagerWalk.block_from_cell(cell)).is_equal(acre)
	assert_int(checked).is_greater(10)
