extends GdUnitTestSuite

## Town map FG grid + decomp type remap (`m_map_ovl`).


func test_fg_acre_types_are_5x6_from_generated_town() -> void:
	var data: WorldData = WorldGenerator.generate(12345)
	var fg: PackedByteArray = TownMap.fg_acre_types(data)
	assert_int(fg.size()).is_equal(30)
	assert_int(int(fg[0])).is_not_equal(0) ## not border cliff top
	## Player house acre is absolute (3,2) → FG (2,1) → index 1*5+2.
	assert_int(int(data.acre_types[2 * 7 + 3])).is_equal(TownFieldGenerator.T_PLAYER_HOUSE)
	assert_int(int(fg[1 * 5 + 2])).is_equal(TownFieldGenerator.T_PLAYER_HOUSE)


func test_fg_from_block_clamps_to_playable() -> void:
	assert_that(TownMap.fg_from_block(Vector2i(3, 2))).is_equal(Vector2i(2, 1))
	assert_that(TownMap.fg_from_block(Vector2i(0, 1))).is_equal(Vector2i(-1, -1))
	assert_that(TownMap.block_from_fg(Vector2i(2, 1))).is_equal(Vector2i(3, 2))


func test_acre_code_uses_letter_number() -> void:
	assert_str(TownMap.acre_code(Vector2i(2, 1))).is_equal("B-3")
	assert_str(TownMap.acre_code(Vector2i(0, 0))).is_equal("A-1")
	assert_str(TownMap.acre_code(Vector2i(4, 5))).is_equal("F-5")


func test_decomp_block_type_remaps_compact_ids() -> void:
	assert_int(TownMap.decomp_block_type(TownFieldGenerator.T_FLAT)).is_equal(39)
	assert_int(TownMap.decomp_block_type(TownFieldGenerator.T_MUSEUM)).is_equal(84)
	assert_int(TownMap.decomp_block_type(TownFieldGenerator.T_NEEDLEWORK)).is_equal(85)
	assert_int(TownMap.decomp_block_type(TownFieldGenerator.T_PORT)).is_equal(100)
	assert_int(TownMap.decomp_block_type(TownFieldGenerator.T_BORDER_CLIFF_OCEAN_LEFT)).is_equal(80)


func test_tile_path_uses_palette_for_beach() -> void:
	TownMap.ensure_tables()
	var flat_path: String = TownMap.tile_path_for_type(TownFieldGenerator.T_FLAT)
	var beach_path: String = TownMap.tile_path_for_type(TownFieldGenerator.T_BEACH)
	assert_str(flat_path).contains("f_p0")
	assert_str(beach_path).contains("m_p1")


func test_label_for_station_and_shop() -> void:
	var data: WorldData = WorldGenerator.generate(12345)
	var station_fg: Vector2i = TownMap.fg_from_block(Vector2i(3, 1))
	assert_str(TownMap.label_for_acre(data, station_fg)).is_equal("Station")
	## Shop is on tracks row bz=1 somewhere in generated towns — find it.
	var found_shop := false
	for bz: int in range(1, 7):
		for bx: int in range(1, 6):
			if int(data.acre_types[bz * 7 + bx]) == TownFieldGenerator.T_TRACKS_SHOP:
				assert_str(TownMap.label_for_acre(data, TownMap.fg_from_block(Vector2i(bx, bz)))).is_equal("Shop")
				found_shop = true
	assert_bool(found_shop).is_true()


func test_cursor_pulse_tables_match_decomp_length() -> void:
	assert_float(TownMap.cursor_green(0)).is_equal(0.0)
	assert_float(TownMap.cursor_green(9)).is_equal(1.0)
	assert_float(TownMap.cursor_scale(9)).is_equal(1.1)
	assert_float(TownMap.cursor_green(18)).is_equal(0.0)


func test_compose_fg_texture_is_seamless_atlas() -> void:
	if not TownMap.assets_ready():
		return
	var data: WorldData = WorldGenerator.generate(12345)
	var types: PackedByteArray = TownMap.fg_acre_types(data)
	var atlas: Texture2D = TownMap.compose_fg_texture(types)
	assert_that(atlas).is_not_null()
	assert_int(atlas.get_width()).is_equal(5 * TownMap.NATIVE_TILE_PX)
	assert_int(atlas.get_height()).is_equal(6 * TownMap.NATIVE_TILE_PX)
