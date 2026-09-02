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
	assert_that(FieldCatalog.default_visual(&"hole")).is_equal(&"HOLE00")
	assert_bool(FieldCatalog.is_ground_decal(&"HOLE00")).is_true()
	assert_bool(FieldCatalog.is_ground_decal(&"obj_hole0")).is_true()
	assert_bool(FieldCatalog.is_ground_decal(&"TREE")).is_false()


func test_fg_item_trees_and_sign_reserves() -> void:
	## `m_name_table.h` tree families + SIGN00–SIGN20.
	assert_that(FgCatalog.placement_for_item(FgCatalog.ITEM_TREE)["visual"]).is_equal(&"TREE")
	assert_that(FgCatalog.placement_for_item(FgCatalog.ITEM_TREE_SAPLING)["visual"]).is_equal(&"TREE")
	assert_that(FgCatalog.placement_for_item(FgCatalog.ITEM_TREE_APPLE_FRUIT)["visual"]).is_equal(
		&"TREE_APPLE_FRUIT"
	)
	assert_that(FgCatalog.placement_for_item(FgCatalog.ITEM_CEDAR_TREE)["visual"]).is_equal(&"CEDAR_TREE")
	assert_that(FgCatalog.placement_for_item(FgCatalog.ITEM_TREE_PALM_FRUIT)["visual"]).is_equal(
		&"TREE_PALM_FRUIT"
	)
	assert_that(FgCatalog.placement_for_item(FgCatalog.ITEM_SIGN00)["kind"]).is_equal(&"reserve")
	assert_that(FgCatalog.placement_for_item(FgCatalog.ITEM_SIGN20)["kind"]).is_equal(&"reserve")
	var port_sign: Dictionary = FgCatalog.placement_for_item(FgCatalog.ITEM_PORT_SIGN)
	assert_that(port_sign["kind"]).is_equal(&"sign")
	assert_that(port_sign["visual"]).is_equal(&"DOCK_SIGN")
	var dock_paths: PackedStringArray = FieldCatalog.mesh_paths(&"DOCK_SIGN")
	if not dock_paths.is_empty():
		assert_str(dock_paths[0]).contains("attention")


func test_summer_tree_paths_when_assets_exist() -> void:
	Clock.apply_snapshot({ "year": 2001, "month": 7, "day": 1, "hour": 12, "minute": 0 })
	assert_str(FieldCatalog.season_letter()).is_equal("s")
	assert_str(FieldCatalog.acre_season_letter()).is_equal("s")
	var paths: PackedStringArray = FieldCatalog.mesh_paths(&"TREE_APPLE_FRUIT")
	if paths.is_empty():
		return
	assert_str(paths[0]).contains("obj_s_tree5")
	var sapling: PackedStringArray = FieldCatalog.mesh_paths(&"TREE_S0")
	if not sapling.is_empty():
		assert_str(sapling[0]).contains("obj_s_tree1")
	var stump: PackedStringArray = FieldCatalog.mesh_paths(&"TREE_STUMP004")
	if not stump.is_empty():
		assert_str(stump[0]).contains("obj_s_stump5")
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
	var manekin: PackedStringArray = FieldCatalog.mesh_paths(&"int_fmanekin")
	if not manekin.is_empty():
		assert_str(manekin[0]).contains("obj_shop_manekin")
	assert_int(FieldCatalog.cloth_index_from_item(6720)).is_equal(165)
	var room01: PackedStringArray = FieldCatalog.mesh_paths(&"room01")
	if not room01.is_empty():
		assert_str(room01[0]).contains("room01")
	var myhome: PackedStringArray = FieldCatalog.mesh_paths(&"rom_myhome1_floor")
	if not myhome.is_empty():
		assert_str(myhome[0]).contains("rom_myhome1_floor")


func test_seasonal_acre_and_tree_letters() -> void:
	## Acres only swap summer↔winter; trees also use autumn `f`.
	Clock.apply_snapshot({ "year": 2001, "month": 7, "day": 1, "hour": 12, "minute": 0 })
	assert_str(FieldCatalog.season_letter()).is_equal("s")
	assert_str(FieldCatalog.acre_season_letter()).is_equal("s")
	assert_str(FieldCatalog.seasonal_acre_id(&"grd_s_f_1")).is_equal("grd_s_f_1")
	assert_str(FieldCatalog.seasonal_acre_id(&"grd_w_r1_1")).is_equal("grd_s_r1_1")

	Clock.apply_snapshot({ "year": 2001, "month": 10, "day": 1, "hour": 12, "minute": 0 })
	assert_that(Clock.season()).is_equal(Clock.Season.AUTUMN)
	assert_str(FieldCatalog.season_letter()).is_equal("f")
	assert_str(FieldCatalog.acre_season_letter()).is_equal("s")
	assert_str(FieldCatalog.seasonal_acre_id(&"grd_s_f_1")).is_equal("grd_s_f_1")

	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 15, "hour": 12, "minute": 0 })
	assert_that(Clock.season()).is_equal(Clock.Season.WINTER)
	assert_str(FieldCatalog.season_letter()).is_equal("w")
	assert_str(FieldCatalog.acre_season_letter()).is_equal("w")
	assert_str(FieldCatalog.seasonal_acre_id(&"grd_s_f_1")).is_equal("grd_w_f_1")
	assert_str(FieldCatalog.seasonal_acre_id(&"grd_s_c1_1")).is_equal("grd_w_c1_1")

	var winter_paths: PackedStringArray = FieldCatalog.mesh_paths(&"grd_s_f_1")
	if not winter_paths.is_empty():
		## Prefer winter GLB when present; otherwise summer fallback.
		assert_bool(
			winter_paths[0].contains("grd_w_f_1") or winter_paths[0].contains("grd_s_f_1")
		).is_true()

	var tree_paths: PackedStringArray = FieldCatalog.mesh_paths(&"TREE")
	if not tree_paths.is_empty():
		assert_bool(
			tree_paths[0].contains("obj_w_tree5") or tree_paths[0].contains("obj_s_tree5")
		).is_true()


func test_season_role_for_label_matches_field_and_tree() -> void:
	assert_str(FieldCatalog.season_role_for_label("grass_tex_dummy")).is_equal("grass")
	assert_str(FieldCatalog.season_role_for_label("Earth_Tex")).is_equal("earth")
	assert_str(FieldCatalog.season_role_for_label("bush_a_tex_dummy")).is_equal("bush_a")
	assert_str(FieldCatalog.season_role_for_label("bush_b_tex_dummy")).is_equal("bush_b")
	assert_str(FieldCatalog.season_role_for_label("earth_tex_dummy")).is_equal("earth")
	assert_str(FieldCatalog.season_role_for_label("sand_tex_dummy")).is_equal("sand")
	assert_str(FieldCatalog.season_role_for_label("beach1_tex_dummy2")).is_equal("beach_wet")
	assert_str(FieldCatalog.season_role_for_label("beach2_tex_dummy2")).is_equal("")
	assert_str(FieldCatalog.season_role_for_label("river_tex_dummy")).is_equal("river_edge")
	assert_str(FieldCatalog.season_role_for_label("river_mFM_grd_water1_tex")).is_equal("")
	assert_str(FieldCatalog.season_role_for_label("stone_tex_dummy")).is_equal("stone")
	assert_str(FieldCatalog.season_role_for_label("obj_s_tree_leaf_tex")).is_equal("tree_leaf")
	assert_str(FieldCatalog.season_role_for_label("obj_w_tree_trunk_tex")).is_equal("tree_trunk")
	assert_str(FieldCatalog.season_role_for_label("river_water")).is_equal("")
	## Acre host node names alone do not identify grass — baked material names must.
	assert_str(FieldCatalog.season_role_for_label("grd_s_f_1")).is_equal("")


func test_season_role_from_extras() -> void:
	var mat := StandardMaterial3D.new()
	mat.set_meta("gltf_extras", { "field_role": "grass" })
	assert_str(FieldCatalog.season_role_from_extras(mat)).is_equal("grass")
	mat.set_meta("gltf_extras", { "water_kind": "river" })
	assert_str(FieldCatalog.season_role_from_extras(mat)).is_equal("")


func test_grass_pattern_texture_path_prefers_variant() -> void:
	FieldCatalog.set_grass_pattern(WorldData.GrassPattern.CIRCLE)
	var path := FieldCatalog.season_texture_path("grass")
	if path.is_empty():
		return
	assert_str(path.get_file()).is_equal("grass_2.png")
	FieldCatalog.set_grass_pattern(WorldData.GrassPattern.TRIANGLE)


func test_grass_pattern_labels() -> void:
	assert_str(WorldData.grass_pattern_label(WorldData.GrassPattern.TRIANGLE)).is_equal("triangle")
	assert_str(WorldData.grass_pattern_label(WorldData.GrassPattern.SQUARE)).is_equal("square")
	assert_str(WorldData.grass_pattern_label(WorldData.GrassPattern.CIRCLE)).is_equal("circle")


func test_season_texture_path_falls_back_to_summer_pack() -> void:
	## Without a seasons pack on disk, paths are empty. With only summer pack, autumn falls back.
	Clock.apply_snapshot({ "year": 2001, "month": 7, "day": 1, "hour": 12, "minute": 0 })
	var summer := FieldCatalog.season_texture_path("grass")
	Clock.apply_snapshot({ "year": 2001, "month": 10, "day": 1, "hour": 12, "minute": 0 })
	var autumn := FieldCatalog.season_texture_path("grass")
	if summer.is_empty():
		assert_str(autumn).is_equal("")
		return
	assert_str(summer).contains("/seasons/s/grass.png")
	## Autumn pack or summer fallback.
	assert_bool(autumn.contains("/seasons/f/grass.png") or autumn.contains("/seasons/s/grass.png")).is_true()


func test_is_seasonal_env_visual() -> void:
	assert_bool(FieldCatalog.is_seasonal_env_visual(&"obj_s_house1")).is_true()
	assert_bool(FieldCatalog.is_seasonal_env_visual(&"ROCK_A")).is_true()
	assert_bool(FieldCatalog.is_seasonal_env_visual(&"grd_s_f_1")).is_true()
	assert_bool(FieldCatalog.is_seasonal_env_visual(&"int_sum_chair01")).is_false()
	assert_bool(FieldCatalog.is_seasonal_env_visual(&"tol_axe_1")).is_false()
	assert_bool(FieldCatalog.is_seasonal_env_visual(&"room01")).is_false()


func test_winter_structure_and_rock_mesh_remap() -> void:
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 15, "hour": 12, "minute": 0 })
	assert_str(FieldCatalog.season_letter()).is_equal("w")
	for id: StringName in [&"obj_s_house1", &"obj_s_myhome1", &"obj_s_shop1", &"ROCK_A"]:
		var paths: PackedStringArray = FieldCatalog.mesh_paths(id)
		if paths.is_empty():
			continue
		var path := paths[0]
		if id == &"ROCK_A":
			assert_bool(path.contains("obj_w_stoneA") or path.contains("obj_s_stoneA")).is_true()
		else:
			var stem := String(id).substr(6)
			assert_bool(path.contains("obj_w_%s" % stem) or path.contains(String(id))).is_true()


func test_species_codes_map_to_disc_prefixes() -> void:
	assert_str(FieldCatalog.species_code(&"squirrel")).is_equal("squ")
	assert_str(FieldCatalog.species_code(&"cat")).is_equal("cat")
	assert_str(FieldCatalog.species_code(&"rabbit")).is_equal("rbt")
	assert_str(FieldCatalog.species_code(&"frog")).is_equal("flg")
	assert_str(FieldCatalog.species_code(&"goat")).is_equal("goa")
	assert_str(FieldCatalog.species_code(&"wolf")).is_equal("wol")
	assert_str(FieldCatalog.species_code(&"fox")).is_equal("rcc")
	assert_str(FieldCatalog.species_code(&"raccoon")).is_equal("rcc")
	assert_str(FieldCatalog.species_code(&"mouse")).is_equal("mus")
	assert_str(FieldCatalog.species_code(&"hedgehog")).is_equal("mos")
	assert_str(FieldCatalog.species_code(&"ostrich")).is_equal("ost")
	assert_str(FieldCatalog.species_code(&"eagle")).is_equal("pbr")
	assert_str(FieldCatalog.species_code(&"penguin")).is_equal("pgn")
	assert_str(FieldCatalog.species_code(&"octopus")).is_equal("oct")


func test_tool_mesh_paths_when_assets_exist() -> void:
	var axe: PackedStringArray = FieldCatalog.mesh_paths(&"tol_axe_1")
	if axe.is_empty():
		return
	assert_str(axe[0]).contains("tol_axe_1")
	assert_str(FieldCatalog.mesh_paths(&"tol_scoop_1")[0]).contains("tol_scoop_1")
	assert_str(FieldCatalog.mesh_paths(&"tol_net_1")[0]).contains("tol_net_1")
	assert_str(FieldCatalog.mesh_paths(&"tol_sao_1")[0]).contains("tol_sao_1")
	## The bobber is a `tol_` item even though it is a world actor, not a held tool.
	assert_str(FieldCatalog.mesh_paths(&"tol_uki_1")[0]).contains("tol_uki_1")


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
	if not FieldCatalog.mesh_paths(&"grd_s_e2_1").is_empty():
		assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_BORDER_CLIFF_LEFT, 0))).is_equal(
			"grd_s_e2_1"
		)
		assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_BORDER_CLIFF_RIGHT, 0))).is_equal(
			"grd_s_e3_1"
		)
		assert_str(
			String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_BORDER_CLIFF_LEFT_TRANSITION, 0))
		).is_equal("grd_s_e2_c1_1")
		assert_str(
			String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_BORDER_CLIFF_OCEAN_LEFT, 0))
		).is_equal("grd_s_e2_m_1")
		assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_BORDER_CLIFF_TOP, 0))).is_equal(
			"grd_s_e1_1"
		)
	if not FieldCatalog.mesh_paths(&"grd_s_o_1").is_empty():
		assert_str(String(FieldCatalog.ocean_visual_for_beach(&"grd_s_m_3"))).is_equal("grd_s_o_3")
		assert_str(String(FieldCatalog.ocean_visual_for_beach(&"grd_s_e2_m_1"))).is_equal("grd_s_e2_o_1")
		assert_str(String(FieldCatalog.ocean_visual_for_beach(&"grd_s_m_r1_2"))).is_equal("grd_s_o_r1_2")
		assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_OCEAN_6, 0))).is_equal(
			"grd_s_o_i_1"
		)
		assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_ISLAND_LEFT, 0))).starts_with(
			"grd_s_il_"
		)
	if not FieldCatalog.mesh_paths(&"grd_s_c7_r1_1").is_empty():
		assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_RIV_CLIFF_BL, 0))).starts_with("grd_s_c7_r1_")
	if not FieldCatalog.mesh_paths(&"grd_s_c7_r3_1").is_empty():
		assert_str(String(FieldCatalog.acre_for_block_type(TownFieldGenerator.T_WF_W_BL, 0))).starts_with("grd_s_c7_r3_")
	assert_float(FieldCatalog.actor_uniform_scale()).is_equal_approx(0.5, 0.0001)
	assert_float(FieldCatalog.actor_uniform_scale_for(&"int_ari_isu01")).is_equal_approx(5.0, 0.0001)
	assert_float(FieldCatalog.actor_draw_scale(&"int_ari_isu01")).is_equal_approx(0.1, 0.0001)
	assert_float(FieldCatalog.acre_uniform_scale()).is_equal_approx(3.125, 0.0001)
	assert_float(FieldCatalog.acre_uniform_scale() / FieldCatalog.actor_uniform_scale()).is_equal_approx(6.25, 0.0001)
	assert_float(FieldCatalog.interior_uniform_scale(&"room01")).is_equal_approx(50.0, 0.0001)
	assert_float(FieldCatalog.interior_uniform_scale(&"rom_myhome1_floor")).is_equal_approx(3.125, 0.0001)
	assert_float(FieldCatalog.train_window_uniform_scale()).is_equal_approx(50.0, 0.0001)
	assert_float(FieldCatalog.interior_ground_y_offset(&"room01")).is_equal_approx(0.0, 0.0001)
	assert_bool(FieldCatalog.interior_uses_acre_verts(&"rom_shop1f")).is_true()
	assert_bool(FieldCatalog.interior_uses_acre_verts(&"room01")).is_false()
	assert_float(FieldCatalog.ACRE_STEP_METERS).is_equal(6.0)


func test_height_counts_match_gx() -> void:
	## Land datum 4 × 10 GX × 0.05 m = 2 m, cancelled so grass sits at acre base.
	assert_float(FieldCatalog.counts_to_y(4, 0)).is_equal(0.0)
	assert_float(FieldCatalog.counts_to_y(16, 0)).is_equal(6.0)
	assert_float(FieldCatalog.counts_to_y(0, 0)).is_equal(-2.0)
	assert_bool(FieldCatalog.is_water_attr(18)).is_true()
	assert_bool(FieldCatalog.is_water_attr(24)).is_true()
	assert_bool(FieldCatalog.is_water_attr(0)).is_false()
	assert_bool(FieldCatalog.is_water_attr(11)).is_false()
	assert_bool(FieldCatalog.is_water_attr(36)).is_false()
	assert_bool(FieldCatalog.is_water_attr(44)).is_false()
	assert_bool(FieldCatalog.is_water_attr(32)).is_false()
	assert_bool(FieldCatalog.is_wave_attr(11)).is_true()
	assert_bool(FieldCatalog.is_wave_attr(25)).is_true()
	assert_bool(FieldCatalog.is_wave_attr(36)).is_true()
	assert_bool(FieldCatalog.is_wave_attr(38)).is_true()
	assert_bool(FieldCatalog.is_wave_attr(22)).is_false()
	assert_bool(FieldCatalog.is_wave_attr(24)).is_false()
	assert_bool(FieldCatalog.is_sand_attr(22)).is_true()
	assert_bool(FieldCatalog.is_sand_attr(11)).is_false()
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
					var attr: int = int(unit["a"])
					var cell: Vector2i = origin + Vector2i(ux, uz)
					var terrain: WorldGrid.Terrain = data.terrain_at(cell)
					assert_that(terrain == WorldGrid.Terrain.WATER).is_equal(
						FieldCatalog.is_water_attr(attr)
					)
					if FieldCatalog.is_wave_attr(attr):
						assert_that(terrain).is_equal(WorldGrid.Terrain.SAND)
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


func test_border_edge_and_track_tunnel_keep_collision() -> void:
	## Border cliffs / track tunnels are authored with many HEIGHT_MAX cells; they are
	## not TRACKS dummy fillers and must still load for rim walls.
	if FieldCatalog.mesh_paths(&"grd_s_e2_t_1").is_empty():
		return
	assert_bool(FieldCatalog.has_acre_collision(&"grd_s_e2_t_1")).is_true()
	assert_bool(FieldCatalog.has_acre_collision(&"grd_s_e3_t_1")).is_true()
	assert_bool(FieldCatalog.has_acre_collision(&"grd_s_e2_1")).is_true()
	assert_bool(FieldCatalog.is_border_edge_acre("grd_s_e2_t_1")).is_true()
	## Tunnel corridor stays below HEIGHT_MAX.
	var walk := 0
	for uz: int in 16:
		for ux: int in 16:
			if int(FieldCatalog.unit_at(&"grd_s_e2_t_1", ux, uz)["c"]) < FieldCatalog.HEIGHT_MAX:
				walk += 1
	assert_int(walk).is_greater(0)


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


func test_gyroid_mesh_paths_when_converted() -> void:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(&"int_hnw001")
	if paths.is_empty():
		return
	assert_str(paths[0]).contains("int_hnw001")


func test_beach_marine_visual_ids() -> void:
	assert_bool(FieldCatalog.is_beach_marine_visual(&"grd_s_m_1")).is_true()
	assert_bool(FieldCatalog.is_beach_marine_visual(&"grd_s_m_r1_b_3")).is_true()
	assert_bool(FieldCatalog.is_beach_marine_visual(&"grd_s_e2_m_1")).is_true()
	assert_bool(FieldCatalog.is_beach_marine_visual(&"grd_s_o_2")).is_false()
	assert_bool(FieldCatalog.is_beach_marine_visual(&"grd_s_e2_o_1")).is_false()
	assert_bool(FieldCatalog.is_beach_marine_visual(&"grd_s_mh_1")).is_false()
	assert_bool(FieldCatalog.is_beach_marine_visual(&"grd_s_r1_1")).is_false()
	assert_bool(FieldCatalog.is_open_ocean_visual(&"grd_s_o_2")).is_true()
	assert_bool(FieldCatalog.is_open_ocean_visual(&"grd_s_e2_o_1")).is_true()
	assert_bool(FieldCatalog.is_open_ocean_visual(&"grd_s_m_1")).is_false()
	assert_bool(FieldCatalog.is_open_ocean_visual(&"grd_s_r1_1")).is_false()
	assert_bool(FieldCatalog.is_ocean_acre_visual(&"grd_s_m_1")).is_true()
	assert_bool(FieldCatalog.is_ocean_acre_visual(&"grd_s_o_2")).is_true()
	assert_bool(FieldCatalog.is_ocean_acre_visual(&"grd_s_r1_1")).is_false()


func test_water_wave_cos_matches_decomp() -> void:
	## `aFD_MakeMarinScrollInfo`: 300-frame cosine; tile1_scroll = 32*(1-cos).
	## After marin<<1 + two_tex_scroll_dolphin<<1, ΔT texels = tile1_scroll (0..64).
	assert_float(GeneratedVisual.water_wave_cos(0.0)).is_equal_approx(1.0, 0.0001)
	assert_float(GeneratedVisual.water_wave_cos(150.0)).is_equal_approx(-1.0, 0.0001)
	assert_float(GeneratedVisual.water_wave_cos(300.0)).is_equal_approx(1.0, 0.0001)
	assert_float(32.0 * (1.0 - GeneratedVisual.water_wave_cos(0.0))).is_equal_approx(0.0, 0.0001)
	assert_float(32.0 * (1.0 - GeneratedVisual.water_wave_cos(150.0))).is_equal_approx(64.0, 0.0001)
	## Phase −1.2: ENV is (144,128,96) when beach_cos = 1, not at frame 0.
	var dark_frame: float = 1.2 / TAU * 300.0
	var dark: Color = GeneratedVisual.beach_env_srgb(dark_frame)
	assert_float(dark.r).is_equal_approx(144.0 / 255.0, 0.002)
	assert_float(dark.g).is_equal_approx(128.0 / 255.0, 0.002)
	assert_float(dark.b).is_equal_approx(96.0 / 255.0, 0.002)
	var light: Color = GeneratedVisual.beach_env_srgb(dark_frame + 150.0)
	assert_float(light.r).is_equal_approx(186.0 / 255.0, 0.002)
	assert_float(light.g).is_equal_approx(164.0 / 255.0, 0.002)
	assert_float(light.b).is_equal_approx(124.0 / 255.0, 0.002)
	## Frame 0 is ocean-cos=1; beach lags 1.2 rad so it is not the dark ENV.
	var at_zero: Color = GeneratedVisual.beach_env_srgb(0.0)
	var beach_cos0: float = cos(-1.2)
	assert_float(at_zero.r).is_equal_approx((165.0 - 21.0 * beach_cos0) / 255.0, 0.002)
	assert_float(at_zero.r).is_not_equal(144.0 / 255.0)


func test_marine_acre_applies_beach_wet_shader() -> void:
	if FieldCatalog.mesh_paths(&"grd_s_m_1").is_empty():
		return
	var host := Node3D.new()
	auto_free(host)
	add_child(host)
	var vis: Node3D = GeneratedVisual.attach(host, &"grd_s_m_1")
	assert_that(vis).is_not_null()
	var hits: Dictionary = _beach_wet_hits(vis)
	assert_bool(hits["found"]).is_true()
	assert_bool(hits["sand_prim"]).is_true()


func _beach_wet_hits(node: Node) -> Dictionary:
	var found := false
	var sand_prim := false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var n: int = mi.mesh.get_surface_count() if mi.mesh != null else 1
		for i: int in n:
			var mat: Material = mi.get_surface_override_material(i)
			if mat is ShaderMaterial and (mat as ShaderMaterial).has_meta("beach_wet"):
				found = true
				var prim: Variant = (mat as ShaderMaterial).get_shader_parameter("prim_color")
				if prim is Color:
					var c: Color = prim
					if is_equal_approx(c.r, 206.0 / 255.0) and is_equal_approx(c.g, 189.0 / 255.0):
						sand_prim = true
	for child in node.get_children():
		var sub: Dictionary = _beach_wet_hits(child)
		found = found or bool(sub["found"])
		sand_prim = sand_prim or bool(sub["sand_prim"])
	return {"found": found, "sand_prim": sand_prim}
