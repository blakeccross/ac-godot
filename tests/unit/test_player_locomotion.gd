class_name TestPlayerLocomotion
extends GdUnitTestSuite

## A physics step at 60 Hz.
const FRAME := 1.0 / 60.0


func _frames(motor: PlayerLocomotion, n: int, wish: Vector3, stick: float, dash := false) -> void:
	_run(motor, n * FRAME, FRAME, wish, stick, dash)


func _run(
	motor: PlayerLocomotion, seconds: float, step: float, wish: Vector3, stick: float, dash := false
) -> void:
	var left: float = seconds
	while left > 0.00001:
		var dt: float = minf(step, left)
		motor.advance(dt, wish, stick, dash, false)
		left -= dt


func test_stick_percent_is_raw_radius_above_dead_zone() -> void:
	## `mCon_calc`: 0 at/below 9.9 / 61, otherwise t / 61 (not rescaled from the dead zone).
	assert_float(PlayerLocomotion.stick_percent(0.16)).is_equal(0.0)
	assert_float(PlayerLocomotion.stick_percent(0.17)).is_equal_approx(0.17, 0.0001)
	assert_float(PlayerLocomotion.stick_percent(1.4)).is_equal(1.0)


func test_wait_then_walk_then_accelerates() -> void:
	## WAIT sees the stick and starts WALK; from then the walk speeds up at ACCEL m/s².
	var motor := PlayerLocomotion.new()
	_frames(motor, 1, Vector3.BACK, 1.0)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.WALK)
	assert_float(motor.speed).is_equal(0.0)
	_run(motor, 0.1, FRAME, Vector3.BACK, 1.0)
	assert_float(motor.speed).is_equal_approx(PlayerLocomotion.ACCEL * 0.1, 0.01)


func test_full_stick_walk_settles_in_run_not_dash() -> void:
	var motor := PlayerLocomotion.new()
	_run(motor, 1.0, FRAME, Vector3.BACK, 1.0)
	assert_float(motor.speed).is_equal_approx(PlayerLocomotion.WALK_SPEED, 0.0001)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.RUN)


func test_dash_button_reaches_dash() -> void:
	var motor := PlayerLocomotion.new()
	_run(motor, 1.0, FRAME, Vector3.BACK, 1.0, true)
	assert_float(motor.speed).is_equal_approx(PlayerLocomotion.RUN_SPEED, 0.0001)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.DASH)


func test_release_brakes_in_walk_and_waits_only_at_zero() -> void:
	var motor := PlayerLocomotion.new()
	_run(motor, 1.0, FRAME, Vector3.BACK, 1.0)
	var start: float = motor.speed
	_run(motor, 0.1, FRAME, Vector3.ZERO, 0.0)
	assert_float(motor.speed).is_equal_approx(start - PlayerLocomotion.DECEL * 0.1, 0.01)
	assert_that(motor.gait()).is_not_equal(PlayerLocomotion.Gait.WAIT)
	_run(motor, 1.0, FRAME, Vector3.ZERO, 0.0)
	assert_float(motor.speed).is_equal(0.0)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.WAIT)


func test_walk_and_stop_agree_at_60_and_15_hz() -> void:
	## A start, cruise and stop land within a centimetre whatever the step; a sharp turn,
	## which one 15 Hz step covers in full, within a few.
	var fine := PlayerLocomotion.new()
	var coarse := PlayerLocomotion.new()
	for m: PlayerLocomotion in [fine, coarse]:
		var step: float = FRAME if m == fine else 1.0 / 15.0
		_run(m, 1.0, step, Vector3.BACK, 1.0)
		_run(m, 1.0, step, Vector3.ZERO, 0.0)
	assert_that(coarse.gait()).is_equal(PlayerLocomotion.Gait.WAIT)
	assert_float(fine.position.distance_to(coarse.position)).is_less(0.01)
	for m: PlayerLocomotion in [fine, coarse]:
		var step: float = FRAME if m == fine else 1.0 / 15.0
		_run(m, 1.0, step, Vector3.RIGHT, 1.0)
		_run(m, 1.0, step, Vector3.BACK, 1.0)
	assert_float(fine.position.distance_to(coarse.position)).is_less(0.08)
	assert_float(absf(angle_difference(fine.facing, coarse.facing))).is_less(0.01)


func test_run_drops_to_walk_below_gauge() -> void:
	var motor := PlayerLocomotion.new()
	_frames(motor, 60, Vector3.BACK, 1.0)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.RUN)
	_frames(motor, 60, Vector3.BACK, 0.5)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.WALK)


func test_clip_rate_formula_and_floor() -> void:
	var motor := PlayerLocomotion.new()
	_frames(motor, 60, Vector3.BACK, 1.0, true)
	assert_float(motor.anim_rate).is_equal_approx(0.59999996, 0.0001)
	## Pinned against a wall: rate × √0 → floored at 0.22, gauge < 3.525 → walk.
	motor.wall_ratio = 0.0
	_frames(motor, 2, Vector3.BACK, 1.0, true)
	assert_float(motor.anim_rate).is_equal_approx(PlayerLocomotion.ANIM_RATE_MIN, 0.0001)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.WALK)


func test_dash_lean_reaches_twenty_degrees() -> void:
	var motor := PlayerLocomotion.new()
	_run(motor, 2.0, FRAME, Vector3.BACK, 1.0, true)
	assert_float(motor.lean).is_equal_approx(deg_to_rad(20.0), 0.01)


func test_dash_reversal_skids_then_waits_facing_new_way() -> void:
	var motor := PlayerLocomotion.new()
	_frames(motor, 60, Vector3.BACK, 1.0, true)
	## The trigger frame still runs `Movement_Walk` (one turn step), then skids.
	_frames(motor, 1, Vector3.FORWARD, 1.0, true)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.TURN_DASH)
	var heading: float = motor.facing
	## Skid keeps sliding along the old heading while the body turns.
	_frames(motor, 3, Vector3.FORWARD, 1.0, true)
	assert_float(motor.facing).is_equal_approx(heading, 0.0001)
	assert_float(absf(angle_difference(motor.body_yaw, heading))).is_greater(0.01)
	_frames(motor, 60, Vector3.ZERO, 0.0)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.WAIT)
	assert_float(absf(angle_difference(motor.facing, PI))).is_less(0.001)


func test_short_angle3_turns_positive_way_only() -> void:
	## Target just below the value → goes almost a full turn the positive way.
	var v: float = MathUtil.short_angle3(0.1, 0.0, MathUtil.HALF_FRACTION, PI, 0.0)
	assert_float(v).is_greater(0.1)


func test_uphill_divides_target_speed() -> void:
	var motor := PlayerLocomotion.new()
	## Ground rising 0.5 m per metre along +Z (the stick direction).
	motor.ground_sampler = func(p: Vector3) -> float: return p.z * 0.5
	_run(motor, 1.5, FRAME, Vector3.BACK, 1.0)
	assert_float(motor.speed).is_equal_approx(PlayerLocomotion.WALK_SPEED / 1.25, 0.001)


func test_locked_action_brakes() -> void:
	var motor := PlayerLocomotion.new()
	_frames(motor, 60, Vector3.BACK, 1.0)
	var before: float = motor.speed
	motor.advance(FRAME, Vector3.BACK, 1.0, true, true)
	assert_float(motor.speed).is_less(before)


func test_full_stick_turn_mod() -> void:
	assert_float(PlayerLocomotion.turn_mod(1.0)).is_equal(0.5)
	assert_float(PlayerLocomotion.turn_mod(0.05)).is_equal(0.01)


func test_facing_point_is_along_plus_z_at_zero_yaw() -> void:
	var motor := PlayerLocomotion.new()
	motor.facing = 0.0
	var point: Vector3 = motor.facing_point(Vector3.ZERO, 2.0)
	assert_vector(point).is_equal(Vector3(0.0, 0.0, 2.0))


func test_axis_percent_zeroes_each_axis_inside_dead_zone() -> void:
	## `move_pX` / `move_pY`: a small diagonal registers radially but reads 0 per axis.
	assert_float(PlayerLocomotion.axis_percent(0.13)).is_equal(0.0)
	assert_float(PlayerLocomotion.stick_percent(Vector2(0.13, 0.13).length())).is_greater(0.0)
	var motor := PlayerLocomotion.new()
	motor.axes_active = false
	_frames(motor, 3, Vector3.BACK, 0.18)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.WAIT)


func test_bad_luck_dash_trips_then_gets_up() -> void:
	var motor := PlayerLocomotion.new()
	_frames(motor, 60, Vector3.BACK, 1.0, true)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.DASH)
	motor.bad_luck = true
	motor.tumble_roll = func() -> bool: return true
	_frames(motor, 1, Vector3.BACK, 1.0, true)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.TUMBLE)
	motor.tumble_roll = Callable()
	## Brakes at TUMBLE_BRAKE regardless of the stick; waits for the clip to end.
	var before: float = motor.speed
	_run(motor, 0.1, FRAME, Vector3.BACK, 1.0, true)
	assert_float(motor.speed).is_equal_approx(before - PlayerLocomotion.TUMBLE_BRAKE * 0.1, 0.01)
	_frames(motor, 60, Vector3.BACK, 1.0, true)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.TUMBLE)
	motor.clip_done = true
	_frames(motor, 1, Vector3.ZERO, 0.0)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.TUMBLE_GETUP)
	motor.clip_done = true
	_frames(motor, 1, Vector3.ZERO, 0.0)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.WAIT)


func test_no_trip_without_bad_luck_or_on_slopes() -> void:
	var motor := PlayerLocomotion.new()
	_frames(motor, 60, Vector3.BACK, 1.0, true)
	motor.tumble_roll = func() -> bool: return true
	_frames(motor, 5, Vector3.BACK, 1.0, true)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.DASH)
	motor.bad_luck = true
	motor.flat_sampler = func(_p: Vector3) -> bool: return false
	_frames(motor, 5, Vector3.BACK, 1.0, true)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.DASH)


func test_bad_luck_dash_trips_about_once_in_ten_seconds() -> void:
	## 1 in 600 a tick is a trip every ten seconds of flat-out dashing on average.
	var trips := 0
	for i: int in 200:
		var motor := PlayerLocomotion.new()
		_run(motor, 1.0, FRAME, Vector3.BACK, 1.0, true)
		motor.bad_luck = true
		_run(motor, 1.0, 0.05, Vector3.BACK, 1.0, true)
		if motor.gait() == PlayerLocomotion.Gait.TUMBLE:
			trips += 1
	## Expect about 200 × (1 − e^−0.1) ≈ 19.
	assert_int(trips).is_between(6, 40)
