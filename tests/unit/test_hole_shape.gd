class_name TestHoleShape
extends GdUnitTestSuite

## `mCoBG_GetHoleNumber_ClData`: the unit's heights less their lowest pick the hole mesh.


func _unit(row: PackedInt32Array, lift: int = 0, slate: int = 0) -> Dictionary:
	return {"c": row[0] + lift, "nw": row[1] + lift, "sw": row[2] + lift, "se": row[3] + lift, "ne": row[4] + lift, "s": slate}


func test_every_pattern_picks_its_own_row() -> void:
	for n: int in HoleShape.PATTERNS.size():
		assert_int(HoleShape.number_for_counts(_unit(HoleShape.PATTERNS[n]))).is_equal(n)


func test_height_above_the_floor_does_not_matter() -> void:
	assert_int(HoleShape.number_for_counts(_unit(HoleShape.PATTERNS[7], 4))).is_equal(7)
	assert_int(HoleShape.number_for_counts(_unit(HoleShape.PATTERNS[0], 6))).is_equal(0)


func test_slate_and_unlisted_shapes_get_no_hole() -> void:
	assert_int(HoleShape.number_for_counts(_unit(HoleShape.PATTERNS[0], 0, 1))).is_equal(-1)
	assert_int(HoleShape.number_for_counts(_unit(PackedInt32Array([3, 0, 0, 0, 0])))).is_equal(-1)


func test_visual_names() -> void:
	assert_that(HoleShape.visual_for(0)).is_equal(&"HOLE00")
	assert_that(HoleShape.visual_for(13)).is_equal(&"HOLE13")
