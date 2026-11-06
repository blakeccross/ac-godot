class_name TestFurnitureClock
extends GdUnitTestSuite

## Furniture clocks: hands to the time, pendulum ticks, the pigeon's pops.


func _clock_piece(visual: StringName) -> Node3D:
	var node := auto_free(load("res://features/house/furniture.tscn").instantiate()) as Node3D
	node.set("data", null)  ## the scene's own piece would bring its own model
	node.set("visual_id", visual)
	add_child(node)
	return node


func test_the_pigeon_pops_the_hours_and_one_on_the_half() -> void:
	assert_int(FurnitureClock.pops_at(0, 0)).is_equal(12)
	assert_int(FurnitureClock.pops_at(12, 0)).is_equal(12)
	assert_int(FurnitureClock.pops_at(13, 0)).is_equal(1)
	assert_int(FurnitureClock.pops_at(23, 0)).is_equal(11)
	assert_int(FurnitureClock.pops_at(5, 30)).is_equal(1)
	assert_int(FurnitureClock.pops_at(5, 15)).is_equal(0)


func test_hands_follow_the_time_on_a_real_clock_model() -> void:
	var was_hour: int = Clock.hour
	var was_min: int = Clock.minute
	Clock.hour = 3
	Clock.minute = 0
	var piece: Node3D = _clock_piece(&"int_kon_grclock")
	var clock: FurnitureClock = piece.get_node_or_null("FurnitureClock") as FurnitureClock
	assert_object(clock).is_not_null()
	var skeleton: Skeleton3D = FurnitureClock._find_skeleton(piece)
	var hour: int = skeleton.find_bone("int_kon_grclock_short_model")
	var at_three: Quaternion = skeleton.get_bone_pose_rotation(hour)
	Clock.hour = 6
	clock._turn_hands()
	var at_six: Quaternion = skeleton.get_bone_pose_rotation(hour)
	assert_float(at_three.angle_to(at_six)).is_equal_approx(PI / 2.0, 0.01)  ## three hours: a quarter turn
	Clock.hour = was_hour
	Clock.minute = was_min


func test_a_piece_without_hands_gets_no_clock() -> void:
	var piece: Node3D = _clock_piece(&"int_sum_chair01")
	assert_object(piece.get_node_or_null("FurnitureClock")).is_null()


func test_the_pendulum_clocks_are_the_ones_that_tick() -> void:
	assert_bool(FurnitureClock.TICKS.has(&"int_sum_oldclk01")).is_true()
	assert_bool(FurnitureClock.TICKS.has(&"int_kon_grclock")).is_false()
	assert_array(FurnitureClock.TICK_FRAMES).is_equal([15, 45])
