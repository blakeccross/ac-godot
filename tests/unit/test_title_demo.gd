class_name TestTitleDemo
extends GdUnitTestSuite

## `m_trademark.c` / `m_titledemo.c` rules. Data-dependent cases only run when
## `python3 tools/build_assets.py --kind title` has produced `demos.json`.


func before_test() -> void:
	TitleDemo.reset_rotation()


func after_test() -> void:
	TitleDemo.reset_rotation()


func test_demos_rotate_one_to_five_and_wrap() -> void:
	var seen: Array[int] = []
	for i: int in 7:
		seen.append(TitleDemo.next_demo_index())
	assert_array(seen).is_equal([0, 1, 2, 3, 4, 0, 1])


func test_trade_days_match_the_decomp_table() -> void:
	var first: Dictionary = TitleDemo.trade_day(0)
	assert_int(int(first["month"])).is_equal(4)
	assert_int(int(first["day"])).is_equal(6)
	assert_int(int(first["hour"])).is_equal(13)
	assert_str(String(first["weather"])).is_equal("sakura")
	assert_str(String(TitleDemo.trade_day(1)["weather"])).is_equal("rain")
	assert_int(int(TitleDemo.trade_day(2)["hour"])).is_equal(6)
	assert_str(String(TitleDemo.trade_day(4)["weather"])).is_equal("snow")
	assert_int(int(TitleDemo.trade_day(4)["month"])).is_equal(2)


func test_fourteen_fixed_villagers_with_real_catalog_entries() -> void:
	assert_int(TitleDemo.NPCS.size()).is_equal(14)
	for row: Dictionary in TitleDemo.NPCS:
		var id: StringName = row["id"] as StringName
		assert_bool(ResourceLoader.exists("res://data/villagers/%s.tres" % id)).is_true()
		## Homes sit inside the 5x6 town interior.
		assert_int(int(row["bx"])).is_between(1, 5)
		assert_int(int(row["bz"])).is_between(1, 6)
		assert_int(int(row["ux"])).is_between(0, 15)
		assert_int(int(row["uz"])).is_between(0, 15)


func test_start_lockout_and_end_thresholds() -> void:
	assert_bool(TitleDemo.button_ok(3529)).is_true()
	assert_bool(TitleDemo.button_ok(3530)).is_false()
	assert_bool(TitleDemo.is_over(3599)).is_false()
	assert_bool(TitleDemo.is_over(3600)).is_true()
	assert_int(TitleDemo.ticks_for(1.0)).is_equal(60)
	assert_int(TitleDemo.ticks_for(0.999)).is_equal(59)


func test_gx_maps_through_the_border_block_into_the_town() -> void:
	var town := WorldData.new()
	town.columns = 80
	town.rows = 96
	town.cell_size = 2.0
	## Default spawn (2240, 1600): (1600, 960) GX past the border = (80 m, 48 m) into a town
	## whose origin is (−80, −96).
	var p: Vector3 = TitleDemo.gx_to_world(town, Vector3(2240.0, 0.0, 1600.0))
	assert_float(p.x).is_equal_approx(0.0, 0.001)
	assert_float(p.z).is_equal_approx(-48.0, 0.001)
	## The town's near corner is exactly one border block in.
	var corner: Vector3 = TitleDemo.gx_to_world(town, Vector3(640.0, 0.0, 640.0))
	assert_vector(corner).is_equal_approx(town.origin(), Vector3.ONE * 0.001)


func test_random_identity_is_deterministic_and_in_range() -> void:
	var a := RandomNumberGenerator.new()
	a.seed = 7
	var b := RandomNumberGenerator.new()
	b.seed = 7
	var first: Dictionary = TitleDemo.random_identity(a)
	assert_dict(first).is_equal(TitleDemo.random_identity(b))
	assert_int(int(first["face"])).is_between(0, IntroSequence.FACE_TYPE_NUM - 1)
	assert_bool(TitleDemo.SHIRT_IDS.has(first["cloth"] as StringName)).is_true()
	assert_bool(
		first["gender"] == IntroSequence.GENDER_MALE or first["gender"] == IntroSequence.GENDER_FEMALE
	).is_true()


func test_tools_map_to_project_items() -> void:
	for word: int in TitleDemo.TOOLS:
		var id: StringName = TitleDemo.TOOLS[word] as StringName
		assert_bool(ResourceLoader.exists("res://data/items/%s.tres" % id)).is_true()


func test_extracted_demos_when_present() -> void:
	if not TitleDemo.has_data():
		return
	## `pact4` is the axe demo, `pact2` the rod, `pact1` the umbrella (no item yet).
	assert_str(String(TitleDemo.tool_item_id(4))).is_equal("axe")
	assert_str(String(TitleDemo.tool_item_id(2))).is_equal("fishing_rod")
	assert_str(String(TitleDemo.tool_item_id(1))).is_equal("")
	assert_str(String(TitleDemo.tool_item_id(0))).is_equal("")
	## Head table = door data (m_trademark.c): demo 1 spawns at (2180, 200, 824).
	assert_vector(TitleDemo.spawn_gx(0)).is_equal(Vector3(2180.0, 200.0, 824.0))
	assert_vector(TitleDemo.spawn_gx(1)).is_equal(Vector3(3218.0, 40.0, 3074.0))
	## 0xB77D = 258.03° (the header comment).
	assert_float(rad_to_deg(TitleDemo.spawn_yaw(0))).is_equal_approx(258.03, 0.01)
	## Every recording covers the full 60 s at 30 Hz.
	for i: int in TitleDemo.DEMO_COUNT:
		assert_int(TitleDemo.keys_for(i).size()).is_greater_equal(1800)


func test_only_demo_one_has_the_parked_train() -> void:
	## `mTRC_go_process`: the train control runs for `mEv_TITLEDEMO_START1` only.
	assert_bool(TitleDemo.has_parked_train(0)).is_true()
	for i: int in range(1, TitleDemo.DEMO_COUNT):
		assert_bool(TitleDemo.has_parked_train(i)).is_false()


func test_decomp_block_types_map_to_generator_ids() -> void:
	## Ocean-side border cliffs are compacted; the plain rail acre (`NONE` in `data_combi`) is
	## the generator's dump-rail type; everything else keeps its decomp id.
	assert_int(TitleDemo.block_type_from_decomp(80, 6)).is_equal(
		TownFieldGenerator.T_BORDER_CLIFF_OCEAN_LEFT
	)
	assert_int(TitleDemo.block_type_from_decomp(81, 6)).is_equal(
		TownFieldGenerator.T_BORDER_CLIFF_OCEAN_RIGHT
	)
	assert_int(TitleDemo.block_type_from_decomp(255, 1)).is_equal(TownFieldGenerator.T_TRACKS_DUMP)
	assert_int(TitleDemo.block_type_from_decomp(255, 3)).is_equal(TownFieldGenerator.T_NONE)
	assert_int(TitleDemo.block_type_from_decomp(11, 1)).is_equal(TownFieldGenerator.T_TRACKS_STATION)
	assert_int(TitleDemo.block_type_from_decomp(57, 3)).is_equal(57)


func test_extracted_acres_fill_the_seven_by_ten_grid() -> void:
	var acres: Dictionary = TitleDemo.acres()
	if acres.is_empty():
		return
	var types: PackedByteArray = acres["types"]
	var visuals: PackedStringArray = acres["visuals"]
	assert_int(types.size()).is_equal(TownFieldGenerator.BLOCK_TOTAL)
	assert_int(visuals.size()).is_equal(TownFieldGenerator.BLOCK_TOTAL)
	assert_int(types[1 * TownFieldGenerator.BLOCK_X + 3]).is_equal(TownFieldGenerator.T_TRACKS_STATION)
	assert_int(types[8 * TownFieldGenerator.BLOCK_X]).is_equal(TownFieldGenerator.T_NONE)


func test_scripted_a_only_allows_tool_and_pickup_verbs() -> void:
	for verb: StringName in [
		Interaction.PICK_UP, Interaction.SHAKE, Interaction.CHOP, Interaction.CAST, Interaction.HOOK
	]:
		assert_bool(TitleDemo.allows_verb(verb)).is_true()
	## The demo must never talk, walk into a building, sit, or shop.
	for verb: StringName in [
		Interaction.TALK, Interaction.ENTER, Interaction.SIT, Interaction.SHOP, Interaction.BUY,
		Interaction.DONATE, Interaction.OPEN,
	]:
		assert_bool(TitleDemo.allows_verb(verb)).is_false()
