class_name TestFieldCatalog
extends GdUnitTestSuite

## Decomp FG/BG names map to generated meshes when the local pipeline exists.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true


func after_test() -> void:
	Clock.reset_to_default()
	Clock.paused = false


func test_default_visuals_use_decomp_names() -> void:
	assert_that(FieldCatalog.default_visual(&"tree")).is_equal(&"TREE_APPLE_FRUIT")
	assert_that(FieldCatalog.default_visual(&"house")).is_equal(&"obj_s_house1")
	assert_that(FieldCatalog.default_visual(&"shop")).is_equal(&"obj_s_shop1")
	assert_that(FieldCatalog.default_visual(&"sign")).is_equal(&"SIGNBOARD")
	assert_that(FieldCatalog.default_visual(&"flower")).is_equal(&"FLOWER_PANSIES0")
	assert_that(FieldCatalog.default_visual(&"rock")).is_equal(&"ROCK_A")


func test_summer_tree_paths_when_assets_exist() -> void:
	Clock.apply_snapshot({ "year": 2001, "month": 7, "day": 1, "hour": 12, "minute": 0 })
	assert_str(FieldCatalog.season_letter()).is_equal("s")
	var paths: PackedStringArray = FieldCatalog.mesh_paths(&"TREE_APPLE_FRUIT")
	if paths.is_empty():
		return
	assert_str(paths[0]).contains("obj_s_tree5")
	assert_str(FieldCatalog.mesh_paths(&"obj_s_house1")[0]).contains("obj_s_house1")
	for id: StringName in [
		&"obj_s_myhome1",
		&"obj_s_museum",
		&"obj_s_tailor",
		&"obj_s_yubinkyoku",
		&"obj_s_kouban",
		&"obj_s_shrine",
		&"obj_s_station1",
	]:
		var structure: PackedStringArray = FieldCatalog.mesh_paths(id)
		if structure.is_empty():
			continue
		assert_str(structure[0]).contains(String(id))
	assert_str(FieldCatalog.mesh_paths(&"grd_s_f_1")[0]).contains("grd_s_f_1")
	assert_str(FieldCatalog.villager_path(&"squirrel")).contains("squ_1")
	assert_str(FieldCatalog.item_albedo(&"apple")).contains("obj_item_apple_tex")


func test_acre_block_types_map_to_grd_families() -> void:
	if FieldCatalog.mesh_paths(&"grd_s_f_1").is_empty():
		return
	assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_FLAT, 0))).is_equal("grd_s_f_1")
	assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_PLAYER_HOUSE, 0))).is_equal("grd_s_f_mh_1")
	assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_TRACKS_SHOP, 0))).is_equal("grd_s_t_sh_1")
	assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_RIVER_S, 0))).is_equal("grd_s_r1_1")
	if not FieldCatalog.mesh_paths(&"grd_s_r1_b_1").is_empty():
		assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_RIVER_S_BRIDGE, 0))).is_equal(
			"grd_s_r1_b_1"
		)
	if not FieldCatalog.mesh_paths(&"grd_s_m_r1_b_1").is_empty():
		assert_str(
			String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_BEACH_RIVER_BRIDGE, 0))
		).is_equal("grd_s_m_r1_b_1")
	assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_BEACH, 0))).is_equal("grd_s_m_1")
	assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_NEEDLEWORK, 0))).is_equal(
		"grd_s_m_ta_1"
	)
	assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_PORT, 0))).is_equal("grd_s_m_wf_1")
	if not FieldCatalog.mesh_paths(&"grd_s_c7_r1_1").is_empty():
		assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_RIV_CLIFF_BL, 0))).starts_with("grd_s_c7_r1_")
	if not FieldCatalog.mesh_paths(&"grd_s_c7_r3_1").is_empty():
		assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_WF_W_BL, 0))).starts_with("grd_s_c7_r3_")
	assert_float(FieldCatalog.actor_uniform_scale()).is_equal_approx(0.5, 0.0001)
	assert_float(FieldCatalog.acre_uniform_scale()).is_equal_approx(3.125, 0.0001)
	assert_float(FieldCatalog.acre_uniform_scale() / FieldCatalog.actor_uniform_scale()).is_equal_approx(6.25, 0.0001)
	assert_float(FieldCatalog.ACRE_STEP_METERS).is_equal(6.0)


func test_height_counts_match_gx() -> void:
	## Land datum 4 × 10 GX × 0.05 m = 2 m, cancelled so grass sits at acre base.
	assert_float(FieldCatalog.counts_to_y(4, 0)).is_equal(0.0)
	assert_float(FieldCatalog.counts_to_y(16, 0)).is_equal(6.0)
	assert_float(FieldCatalog.counts_to_y(0, 0)).is_equal(-2.0)
	assert_bool(FieldCatalog.is_water_attr(18)).is_true()
	assert_bool(FieldCatalog.is_water_attr(0)).is_false()
	assert_bool(FieldCatalog.is_water_attr(44)).is_false()
	assert_bool(FieldCatalog.is_water_attr(32)).is_false()
	assert_bool(FieldCatalog.is_bridge_attr(32)).is_true()
	assert_bool(FieldCatalog.is_stone_bridge_attr(32)).is_true()
	assert_bool(FieldCatalog.is_wood_bridge_attr(32)).is_false()
	assert_bool(FieldCatalog.is_wood_bridge_attr(27)).is_true()
	assert_bool(FieldCatalog.is_bridge_attr(18)).is_false()
	assert_bool(FieldCatalog.is_plantable_attr(0)).is_true()
	assert_bool(FieldCatalog.is_plantable_attr(6)).is_true()
	assert_bool(FieldCatalog.is_plantable_attr(7)).is_false()
	assert_bool(FieldCatalog.is_plantable_attr(23)).is_false()


func test_south_river_r1_1_water_is_west_of_center() -> void:
	## Geometric paint used x=6..9. `grd_s_r1_1` water at z=8 is x=2..4 (`data_bgd`).
	if not FieldCatalog.has_acre_collision(&"grd_s_r1_1"):
		return
	assert_bool(FieldCatalog.is_water_attr(int(FieldCatalog.unit_at(&"grd_s_r1_1", 3, 8)["a"]))).is_true()
	assert_bool(FieldCatalog.is_water_attr(int(FieldCatalog.unit_at(&"grd_s_r1_1", 8, 8)["a"]))).is_false()


func test_generated_water_matches_catalog_attrs() -> void:
	var data: WorldData = WorldGenerator.generate(12345)
	var checked := 0
	for bz: int in range(1, 7):
		for bx: int in range(1, 6):
			var visual := StringName(data.acre_visuals[bz * 7 + bx])
			if not FieldCatalog.has_acre_collision(visual):
				continue
			var origin := Vector2i((bx - 1) * 16, (bz - 1) * 16)
			for uz: int in 16:
				for ux: int in 16:
					var unit: Dictionary = FieldCatalog.unit_at(visual, ux, uz)
					var want_water: bool = FieldCatalog.is_water_attr(int(unit["a"]))
					var cell: Vector2i = origin + Vector2i(ux, uz)
					assert_that(data.terrain_at(cell) == WorldGrid.Terrain.WATER).is_equal(want_water)
					checked += 1
	if checked == 0:
		return
	assert_int(checked).is_greater(0)


func test_height_max_filler_tables_are_skipped() -> void:
	## Dummy TRACKS combos reuse `grd_s_c1_3` / `grd_s_r1_3` with HEIGHT_MAX floors.
	## Picking those boxed the acre in ~13 m walls. Skip them; keep real field tables.
	for type: int in [
		TownFieldGenerator.T_FLAT,
		TownFieldGenerator.T_CLIFF_H,
		TownFieldGenerator.T_RIVER_S,
		TownFieldGenerator.T_CLIFF_TR,
	]:
		for variant: int in 12:
			var visual: StringName = FieldCatalog.acre_for_block_type(type, variant)
			if visual == &"" or not FieldCatalog.has_acre_collision(visual):
				continue
			var n_max := 0
			for uz: int in 16:
				for ux: int in 16:
					if int(FieldCatalog.unit_at(visual, ux, uz)["c"]) >= FieldCatalog.HEIGHT_MAX:
						n_max += 1
			assert_int(n_max).is_less_equal(128)


func test_bridge_block_types_pick_data_combi_bgs() -> void:
	## Same `*_BRIDGE` type; stone vs wood is the BG row (`bridge_1` vs `bridge_2`).
	assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_RIVER_S_BRIDGE, 0))).is_equal(
		"grd_s_r1_b_1"
	)
	assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_BEACH_RIVER_BRIDGE, 0))).is_equal(
		"grd_s_m_r1_b_1"
	)
	assert_bool(FieldCatalog.is_stone_bridge_visual(&"grd_s_r1_b_1")).is_true()
	assert_bool(FieldCatalog.is_stone_bridge_visual(&"grd_s_r1_b_2")).is_false()
	assert_bool(FieldCatalog.is_stone_bridge_visual(&"grd_s_r1_b_3")).is_false()
	assert_bool(FieldCatalog.is_stone_bridge_visual(&"grd_s_r3_b_3")).is_true()
	assert_bool(FieldCatalog.is_stone_bridge_visual(&"grd_s_m_r1_b_3")).is_true()
	var used := PackedStringArray(["grd_s_r1_b_1"])
	assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_RIVER_S_BRIDGE, 0, used))).is_equal(
		"grd_s_r1_b_2"
	)
