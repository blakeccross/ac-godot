extends GdUnitTestSuite

## Water you can hear (`aFD_OperateWaterSound`).


func _layout(visual: String, type: int) -> WorldData:
	var data := WorldData.new()
	data.acre_visuals = PackedStringArray()
	data.acre_types = PackedByteArray()
	data.acre_visuals.resize(TownFieldGenerator.BLOCK_TOTAL)
	data.acre_types.resize(TownFieldGenerator.BLOCK_TOTAL)
	var i: int = 2 * TownFieldGenerator.BLOCK_X + 2
	data.acre_visuals[i] = visual
	data.acre_types[i] = type
	return data


func test_river_sources_come_from_the_acre_data() -> void:
	if not ResourceLoader.exists(FieldCatalog.acre_grid_path("grd_s_r1_p_1")):
		return
	var data := _layout("grd_s_r1_p_1", 0)
	var srcs: Array = FieldAmbience.block_sources(data, Vector2i(2, 2))
	assert_int(srcs.size()).is_greater(0)
	## [1, 5, 1]: unit (5, 1) of acre (2, 2), unit centre.
	assert_that(srcs[0][1]).is_equal(Vector3(2 * 640 + 5 * 40 + 20, 0, 2 * 640 + 1 * 40 + 20))
	var near: Array[Vector3] = FieldAmbience.nearest_two(data, Vector2i(2, 2), FieldAmbience.KIND_RIVER, 9, srcs[0][1])
	assert_int(near.size()).is_equal(2)
	assert_that(near[0]).is_equal(srcs[0][1])


func test_beach_and_frogs() -> void:
	var data := _layout("", TownFieldGenerator.T_BEACH)
	assert_bool(FieldAmbience.is_marine(data, Vector2i(2, 2))).is_true()
	assert_bool(FieldAmbience.is_marine(data, Vector2i(2, 3))).is_false()
	assert_bool(FieldAmbience.frogs_sing(6, 19)).is_true()
	assert_bool(FieldAmbience.frogs_sing(6, 12)).is_false()
	assert_bool(FieldAmbience.frogs_sing(10, 19)).is_false()
