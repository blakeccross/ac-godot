class_name TestAcreWade
extends GdUnitTestSuite

## Acre-border wall, wade trigger / end / curve (`m_player_common.c_inc`) and the outdoor
## camera box and easing (`m_camera2.c`).


const GX := FieldCatalog.GX_TO_METERS
const EPS := 0.0001


## A `TownSpace` field position from decomp GX.
static func _at(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z) * GX


func _land_ok(_d: AcreWade.Dir) -> bool:
	return true


func _land_no(_d: AcreWade.Dir) -> bool:
	return false


func test_the_wall_keeps_the_player_18_gx_inside_the_acre() -> void:
	var old := _at(1900.0, 0.0, 1000.0)
	## Block (2, 1): x 1280..1920 GX. Stepping east past the edge stops 18 short.
	var held: Vector3 = AcreWade.confine(old, _at(1930.0, 0.0, 1000.0))
	assert_float(held.x).is_equal_approx((1920.0 - 18.0) * GX, EPS)
	held = AcreWade.confine(_at(1300.0, 0.0, 660.0), _at(1290.0, 0.0, 650.0))
	assert_float(held.x).is_equal_approx((1280.0 + 18.0) * GX, EPS)
	assert_float(held.z).is_equal_approx((640.0 + 18.0) * GX, EPS)
	## Inside the acre nothing changes.
	var inside := _at(1600.0, 0.0, 1000.0)
	var step := _at(5.0, 0.0, 5.0)
	assert_vector(AcreWade.confine(inside, inside + step)).is_equal(inside + step)


func test_wading_needs_the_stick_the_facing_and_the_edge() -> void:
	var at_east := _at(1920.0 - 18.0, 0.0, 1000.0)
	var ok := Callable(self, "_land_ok")
	assert_int(AcreWade.direction(at_east, PI * 0.5, Vector2(1.0, 0.0), ok)).is_equal(AcreWade.Dir.RIGHT)
	## Stick too soft.
	assert_int(AcreWade.direction(at_east, PI * 0.5, Vector2(0.6, 0.0), ok)).is_equal(AcreWade.Dir.NONE)
	## Facing 45° off straight across.
	assert_int(AcreWade.direction(at_east, deg_to_rad(45.0), Vector2(1.0, 0.0), ok)).is_equal(AcreWade.Dir.NONE)
	## Not at the edge yet.
	assert_int(AcreWade.direction(at_east - _at(10.0, 0.0, 0.0), PI * 0.5, Vector2(1.0, 0.0), ok)).is_equal(AcreWade.Dir.NONE)
	## Landing blocked.
	assert_int(AcreWade.direction(at_east, PI * 0.5, Vector2(1.0, 0.0), Callable(self, "_land_no"))).is_equal(AcreWade.Dir.NONE)


func test_north_and_south_use_the_stick_y_and_facing() -> void:
	var ok := Callable(self, "_land_ok")
	var at_north := _at(1500.0, 0.0, 640.0 + 18.0)
	assert_int(AcreWade.direction(at_north, PI, Vector2(0.0, 1.0), ok)).is_equal(AcreWade.Dir.UP)
	assert_int(AcreWade.direction(at_north, -PI + 0.2, Vector2(0.0, 1.0), ok)).is_equal(AcreWade.Dir.UP)
	var at_south := _at(1500.0, 0.0, 1280.0 - 18.0)
	assert_int(AcreWade.direction(at_south, 0.1, Vector2(0.0, -1.0), ok)).is_equal(AcreWade.Dir.DOWN)


func test_wade_ends_18_gx_into_the_next_acre() -> void:
	var from := _at(1902.0, 0.0, 700.0)
	var end: Vector3 = AcreWade.end_pos(from, AcreWade.Dir.RIGHT)
	assert_float(end.x).is_equal_approx((1920.0 + 18.0) * GX, 0.001)
	## Cross coordinate kept 18 GX clear of the side edges (block z 640..1280 GX).
	assert_float(end.z).is_equal_approx(700.0 * GX, EPS)
	end = AcreWade.end_pos(_at(1902.0, 0.0, 645.0), AcreWade.Dir.RIGHT)
	assert_float(end.z).is_equal_approx((640.0 + 18.0) * GX, 0.001)
	end = AcreWade.end_pos(_at(1500.0, 0.0, 658.0), AcreWade.Dir.UP)
	assert_float(end.z).is_equal_approx((640.0 - 18.0) * GX, 0.001)


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
	## Block (2, 3): x 1280..1920, z 1920..2560 GX → box x 1390..1810, z 2070..2465.
	var player := _at(1900.0, 0.0, 2000.0)
	var goal: Vector3 = AcreCamera.goal(player + _at(0.0, 40.0, 0.0), player)
	assert_float(goal.x).is_equal_approx(1810.0 * GX, EPS)
	assert_float(goal.z).is_equal_approx(2070.0 * GX, EPS)
	assert_float(goal.y).is_equal_approx(40.0 * GX, EPS)
	var mid := _at(1600.0, 0.0, 2300.0)
	assert_vector(AcreCamera.goal(mid, mid)).is_equal(mid)


func test_wade_camera_jumps_to_the_next_box() -> void:
	## Leaving block (2, 3) east: goal x = old box x_max + 220 GX = next box x_min.
	var player := _at(1902.0, 0.0, 2300.0)
	var goal: Vector3 = AcreCamera.wade_goal(_at(1938.0, 40.0, 2300.0), player)
	assert_float(goal.x).is_equal_approx((1810.0 + 220.0) * GX, EPS)
	assert_float(goal.x).is_equal_approx(float(AcreCamera.box(Vector2i(3, 3))["x_min"]), EPS)
	## Leaving south lands on the next box's north edge.
	goal = AcreCamera.wade_goal(_at(1600.0, 40.0, 2578.0), _at(1600.0, 0.0, 2542.0))
	assert_float(goal.z).is_equal_approx(float(AcreCamera.box(Vector2i(2, 4))["z_min"]), EPS)


func test_add_calc_matches_the_decomp_steps() -> void:
	## 13.4% of the gap, capped at 8.75 GX, at least 0.25 GX, never overshooting.
	assert_float(AcreCamera.add_calc(0.0, 10.0 * GX)).is_equal_approx(1.3397461 * GX, EPS)
	assert_float(AcreCamera.add_calc(0.0, 1000.0 * GX)).is_equal_approx(8.75 * GX, EPS)
	assert_float(AcreCamera.add_calc(0.0, 1.0 * GX)).is_equal_approx(0.25 * GX, EPS)
	assert_float(AcreCamera.add_calc(0.0, 0.1 * GX)).is_equal_approx(0.1 * GX, EPS)


func test_camera_pitch_eases_toward_the_swing() -> void:
	## `add_calc_short_angle2(…, 0.0513, 11000, 100)`: 5% of the gap a tick, never under 100
	## units a tick.
	var goal: float = -250.0 * TAU / 65536.0
	var p: float = AcreCamera.follow_pitch(0.0, goal, 1.0 / 60.0)
	assert_float(p).is_less(0.0)
	assert_float(p).is_greater(goal)
	## A small gap closes at the 100-unit floor, then lands.
	for i: int in 10:
		p = AcreCamera.follow_pitch(p, goal, 1.0 / 60.0)
	assert_float(p).is_equal_approx(goal, 0.0001)


func test_camera_centre_follows_the_same_at_any_frame_rate() -> void:
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var goal := _at(300.0, 0.0, -40.0)
	## A far goal: x moves at the 8.75 GX-a-tick cap.
	assert_float(AcreCamera.follow(a, goal, 1.0 / 60.0).x).is_equal_approx(8.75 * GX, EPS)
	for _i: int in 30:
		a = AcreCamera.follow(a, goal, 1.0 / 60.0)
	for _i: int in 8:
		b = AcreCamera.follow(b, goal, 1.0 / 16.0)
	## Where the cap hands over to the eased gap differs a little with the step: within
	## 5 GX (25 cm), and both settle on the goal.
	assert_vector(b).is_equal_approx(a, Vector3.ONE * 5.0 * GX)
	for _i: int in 90:
		a = AcreCamera.follow(a, goal, 1.0 / 60.0)
	for _i: int in 24:
		b = AcreCamera.follow(b, goal, 1.0 / 16.0)
	assert_vector(a).is_equal_approx(goal, Vector3.ONE * EPS)
	assert_vector(b).is_equal_approx(goal, Vector3.ONE * EPS)


func test_camera_pitch_morph_lands_with_the_wade() -> void:
	for hz: float in [60.0, 15.0]:
		var p := 0.0
		var goal := -0.02
		var t := 0.0
		while t < AcreWade.DURATION:
			p = AcreCamera.morph_pitch(p, goal, AcreWade.DURATION - t, 1.0 / hz)
			t += 1.0 / hz
		assert_float(p).is_equal_approx(goal, 0.000001)


func test_a_pushed_snowball_wades_only_square_on() -> void:
	## `Player_actor_CheckCondition_forWadeSnowball`: 5°, not the walk's 40°.
	var at_east := _at(1920.0 - 18.0, 0.0, 1000.0)
	var ok := Callable(self, "_land_ok")
	var narrow: float = AcreWade.SNOWBALL_ANGLE_RANGE
	assert_int(AcreWade.direction(at_east, deg_to_rad(93.0), Vector2(1.0, 0.0), ok, 0.0, false, narrow)).is_equal(AcreWade.Dir.RIGHT)
	assert_int(AcreWade.direction(at_east, deg_to_rad(100.0), Vector2(1.0, 0.0), ok, 0.0, false, narrow)).is_equal(AcreWade.Dir.NONE)
	## The same lean walks across without a ball.
	assert_int(AcreWade.direction(at_east, deg_to_rad(100.0), Vector2(1.0, 0.0), ok)).is_equal(AcreWade.Dir.RIGHT)
