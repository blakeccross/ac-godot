class_name TestAcreWade
extends GdUnitTestSuite

## Acre-border wall, wade trigger / end / curve (`m_player_common.c_inc`) and the outdoor
## camera box and easing (`m_camera2.c`).


func _land_ok(_d: AcreWade.Dir) -> bool:
	return true


func _land_no(_d: AcreWade.Dir) -> bool:
	return false


func test_the_wall_keeps_the_player_18_gx_inside_the_acre() -> void:
	var old := Vector3(1900.0, 0.0, 1000.0)
	## Block (2, 1): x 1280..1920. Stepping east past the edge stops 18 short.
	var held: Vector3 = AcreWade.confine(old, Vector3(1930.0, 0.0, 1000.0))
	assert_float(held.x).is_equal(1920.0 - 18.0)
	held = AcreWade.confine(Vector3(1300.0, 0.0, 660.0), Vector3(1290.0, 0.0, 650.0))
	assert_float(held.x).is_equal(1280.0 + 18.0)
	assert_float(held.z).is_equal(640.0 + 18.0)
	## Inside the acre nothing changes.
	var inside := Vector3(1600.0, 0.0, 1000.0)
	assert_vector(AcreWade.confine(inside, inside + Vector3(5.0, 0.0, 5.0))).is_equal(inside + Vector3(5.0, 0.0, 5.0))


func test_wading_needs_the_stick_the_facing_and_the_edge() -> void:
	var at_east := Vector3(1920.0 - 18.0, 0.0, 1000.0)
	var ok := Callable(self, "_land_ok")
	assert_int(AcreWade.direction(at_east, PI * 0.5, Vector2(1.0, 0.0), ok)).is_equal(AcreWade.Dir.RIGHT)
	## Stick too soft.
	assert_int(AcreWade.direction(at_east, PI * 0.5, Vector2(0.6, 0.0), ok)).is_equal(AcreWade.Dir.NONE)
	## Facing 45° off straight across.
	assert_int(AcreWade.direction(at_east, deg_to_rad(45.0), Vector2(1.0, 0.0), ok)).is_equal(AcreWade.Dir.NONE)
	## Not at the edge yet.
	assert_int(AcreWade.direction(at_east - Vector3(10.0, 0.0, 0.0), PI * 0.5, Vector2(1.0, 0.0), ok)).is_equal(AcreWade.Dir.NONE)
	## Landing blocked.
	assert_int(AcreWade.direction(at_east, PI * 0.5, Vector2(1.0, 0.0), Callable(self, "_land_no"))).is_equal(AcreWade.Dir.NONE)


func test_north_and_south_use_the_stick_y_and_facing() -> void:
	var ok := Callable(self, "_land_ok")
	var at_north := Vector3(1500.0, 0.0, 640.0 + 18.0)
	assert_int(AcreWade.direction(at_north, PI, Vector2(0.0, 1.0), ok)).is_equal(AcreWade.Dir.UP)
	assert_int(AcreWade.direction(at_north, -PI + 0.2, Vector2(0.0, 1.0), ok)).is_equal(AcreWade.Dir.UP)
	var at_south := Vector3(1500.0, 0.0, 1280.0 - 18.0)
	assert_int(AcreWade.direction(at_south, 0.1, Vector2(0.0, -1.0), ok)).is_equal(AcreWade.Dir.DOWN)


func test_wade_ends_18_gx_into_the_next_acre() -> void:
	var from := Vector3(1902.0, 0.0, 700.0)
	var end: Vector3 = AcreWade.end_pos(from, AcreWade.Dir.RIGHT)
	assert_float(end.x).is_equal_approx(1920.0 + 18.00001, 0.001)
	## Cross coordinate kept 18 clear of the side edges (block z 640..1280).
	assert_float(end.z).is_equal(700.0)
	end = AcreWade.end_pos(Vector3(1902.0, 0.0, 645.0), AcreWade.Dir.RIGHT)
	assert_float(end.z).is_equal_approx(640.0 + 18.00001, 0.001)
	end = AcreWade.end_pos(Vector3(1500.0, 0.0, 658.0), AcreWade.Dir.UP)
	assert_float(end.z).is_equal_approx(640.0 - 18.00001, 0.001)


func test_wade_curve_eases_in_and_out_over_36_ticks() -> void:
	assert_float(AcreWade.percent(0.0)).is_equal(0.0)
	assert_float(AcreWade.percent(36.0)).is_equal(1.0)
	var prev := 0.0
	for t: int in range(1, 37):
		var p: float = AcreWade.percent(float(t))
		assert_float(p).is_greater_equal(prev)
		prev = p
	## Fast early, long brake: well past half by a third of the way.
	assert_float(AcreWade.percent(12.0)).is_greater(0.5)
	assert_float(AcreWade.percent(35.0)).is_greater(0.99)


func test_camera_centre_is_held_inside_the_acre_box() -> void:
	## Block (2, 3): x 1280..1920, z 1920..2560 → box x 1390..1810, z 2070..2465.
	var player := Vector3(1900.0, 0.0, 2000.0)
	var goal: Vector3 = AcreCamera.goal(player + Vector3(0.0, 40.0, 0.0), player)
	assert_float(goal.x).is_equal(1810.0)
	assert_float(goal.z).is_equal(2070.0)
	assert_float(goal.y).is_equal(40.0)
	var mid := Vector3(1600.0, 0.0, 2300.0)
	assert_vector(AcreCamera.goal(mid, mid)).is_equal(mid)


func test_wade_camera_jumps_to_the_next_box() -> void:
	## Leaving block (2, 3) east: goal x = old box x_max + 220 = next box x_min.
	var player := Vector3(1902.0, 0.0, 2300.0)
	var goal: Vector3 = AcreCamera.wade_goal(Vector3(1938.0, 40.0, 2300.0), player)
	assert_float(goal.x).is_equal(1810.0 + 220.0)
	assert_float(goal.x).is_equal(float(AcreCamera.box(Vector2i(3, 3))["x_min"]))
	## Leaving south lands on the next box's north edge.
	goal = AcreCamera.wade_goal(Vector3(1600.0, 40.0, 2578.0), Vector3(1600.0, 0.0, 2542.0))
	assert_float(goal.z).is_equal(float(AcreCamera.box(Vector2i(2, 4))["z_min"]))


func test_add_calc_matches_the_decomp_steps() -> void:
	## 13.4% of the gap, capped at 8.75, at least 0.25, never overshooting.
	assert_float(AcreCamera.add_calc(0.0, 10.0)).is_equal_approx(1.3397461, 0.0001)
	assert_float(AcreCamera.add_calc(0.0, 1000.0)).is_equal(8.75)
	assert_float(AcreCamera.add_calc(0.0, 1.0)).is_equal(0.25)
	assert_float(AcreCamera.add_calc(0.0, 0.1)).is_equal(0.1)


func test_camera_pitch_eases_toward_the_swing() -> void:
	## `add_calc_short_angle2(…, 0.0513, 11000, 100)`: 5% of the gap, never under 100 units.
	var goal: float = -250.0 * TAU / 65536.0
	var p: float = AcreCamera.ease_pitch(0.0, goal)
	assert_float(p).is_less(0.0)
	assert_float(p).is_greater(goal)
	## A small gap closes by the 100-unit floor, then lands.
	for i: int in 10:
		p = AcreCamera.ease_pitch(p, goal)
	assert_float(p).is_equal_approx(goal, 0.0001)


func test_camera_pitch_morph_lands_with_the_wade() -> void:
	var p := 0.0
	var goal := -0.02
	for t: int in int(AcreWade.TICKS):
		p = AcreCamera.morph_pitch(p, goal, AcreWade.TICKS - float(t))
	assert_float(p).is_equal_approx(goal, 0.000001)
