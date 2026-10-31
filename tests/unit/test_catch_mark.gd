class_name TestCatchMark
extends GdUnitTestSuite

## `eYajirushi`: the arrow over an ant, a mosquito or a killifish held up for the report.


func test_only_the_tiny_catches_get_the_arrow() -> void:
	assert_bool(CatchMark.marks_insect(38)).is_true()
	assert_bool(CatchMark.marks_insect(39)).is_true()
	assert_bool(CatchMark.marks_insect(0)).is_false()
	assert_bool(CatchMark.marks_fish(&"killifish")).is_true()
	assert_bool(CatchMark.marks_fish(&"sea_bass")).is_false()


func test_the_ant_and_mosquito_are_those_type_indices() -> void:
	assert_int((load("res://data/creatures/ant.tres") as BugData).type_index).is_equal(38)
	assert_int((load("res://data/creatures/mosquito.tres") as BugData).type_index).is_equal(39)


func test_it_fades_in_over_three_ticks_and_out_over_six() -> void:
	var host: Node3D = auto_free(Node3D.new())
	add_child(host)
	var mark: CatchMark = CatchMark.appear(host, func() -> Vector3: return Vector3(1.0, 2.0, 3.0))
	assert_float(_alpha(mark)).is_equal(0.0)
	mark._process(1.5 / DecompTime.TICK_HZ)
	assert_float(_alpha(mark)).is_equal_approx(0.5, 0.001)
	mark._process(2.0 / DecompTime.TICK_HZ)
	assert_float(_alpha(mark)).is_equal(1.0)
	mark._process(60.0 / DecompTime.TICK_HZ)
	assert_float(_alpha(mark)).is_equal(1.0)
	assert_vector(mark.global_position).is_equal_approx(Vector3(1.0, 2.0, 3.0), Vector3.ONE * 0.001)
	mark.finish()
	mark._process(3.0 / DecompTime.TICK_HZ)
	assert_float(_alpha(mark)).is_equal_approx(0.5, 0.001)
	mark._process(4.0 / DecompTime.TICK_HZ)
	assert_bool(mark.is_queued_for_deletion()).is_true()


func _alpha(mark: CatchMark) -> float:
	if mark._mats.is_empty():
		return 0.0
	return (mark._mats[0].get_shader_parameter(&"prim_color") as Color).a
