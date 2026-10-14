extends GdUnitTestSuite

## Building clocks (`ac_house_clock`): hands follow `rad_hour` / `rad_min`.


func test_hands_turn_with_the_hour_and_minute() -> void:
	var a: Vector2 = HouseClock.hand_angles(15, 0)
	assert_float(a.x).is_equal_approx(TAU / 4.0, 0.0001)
	assert_float(a.y).is_equal_approx(0.0, 0.0001)
	var b: Vector2 = HouseClock.hand_angles(0, 30)
	assert_float(b.x).is_equal_approx(TAU / 24.0, 0.0001)
	assert_float(b.y).is_equal_approx(PI, 0.0001)


func test_the_post_office_and_police_box_have_their_clocks() -> void:
	assert_object(HouseClock.POST_OFFICE_GX).is_equal(Vector3(120.0, 55.0, 135.0))
	assert_object(HouseClock.POLICE_BOX_GX).is_equal(Vector3(200.0, 0.0, 30.0))
