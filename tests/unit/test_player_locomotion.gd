class_name TestPlayerLocomotion
extends GdUnitTestSuite

## One decomp frame is 1/60 s; `tick` steps whole frames.
const FRAME := DecompTime.TICK_SEC
const GX := DecompTime.FRAME_HZ * PlayerLocomotion.UNIT_METERS


func _frames(motor: PlayerLocomotion, n: int, wish: Vector3, stick: float, dash := false) -> void:
	for _i: int in n:
		motor.tick(FRAME, wish, stick, dash, false)


func test_meter_scale_matches_tile_ratio() -> void:
	assert_float(PlayerLocomotion.WALK_SPEED).is_equal_approx(7.3125, 0.0001)
	assert_float(PlayerLocomotion.RUN_SPEED).is_equal_approx(11.25, 0.0001)


func test_stick_percent_is_raw_radius_above_dead_zone() -> void:
	## `mCon_calc`: 0 at/below 9.9 / 61, otherwise t / 61 (not rescaled from the dead zone).
	assert_float(PlayerLocomotion.stick_percent(0.16)).is_equal(0.0)
	assert_float(PlayerLocomotion.stick_percent(0.17)).is_equal_approx(0.17, 0.0001)
	assert_float(PlayerLocomotion.stick_percent(1.4)).is_equal(1.0)


func test_wait_then_walk_then_one_accel_step() -> void:
	## Frame 1: WAIT sees the stick and requests WALK. Frame 2: walk accelerates 0.609.
	var motor := PlayerLocomotion.new()
	_frames(motor, 1, Vector3.BACK, 1.0)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.WALK)
	assert_float(motor.speed_gx).is_equal(0.0)
	_frames(motor, 1, Vector3.BACK, 1.0)
	assert_float(motor.speed_gx).is_equal_approx(PlayerLocomotion.ORIG_ACCEL, 0.0001)


func test_full_stick_walk_settles_in_run_not_dash() -> void:
	var motor := PlayerLocomotion.new()
	_frames(motor, 60, Vector3.BACK, 1.0)
	assert_float(motor.speed_gx).is_equal_approx(PlayerLocomotion.ORIG_WALK, 0.0001)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.RUN)


func test_dash_button_reaches_dash() -> void:
	var motor := PlayerLocomotion.new()
	_frames(motor, 60, Vector3.BACK, 1.0, true)
	assert_float(motor.speed_gx).is_equal_approx(PlayerLocomotion.ORIG_RUN, 0.0001)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.DASH)


func test_release_brakes_in_walk_and_waits_only_at_zero() -> void:
	var motor := PlayerLocomotion.new()
	_frames(motor, 60, Vector3.BACK, 1.0)
	var start: float = motor.speed_gx
	_frames(motor, 1, Vector3.ZERO, 0.0)
	assert_float(motor.speed_gx).is_equal_approx(start - PlayerLocomotion.ORIG_DECEL, 0.0001)
	assert_that(motor.gait()).is_not_equal(PlayerLocomotion.Gait.WAIT)
	_frames(motor, 40, Vector3.ZERO, 0.0)
	assert_float(motor.speed_gx).is_equal(0.0)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.WAIT)


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
	_frames(motor, 120, Vector3.BACK, 1.0, true)
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
	var v: float = MLib.short_angle3(0.1, 0.0, 0.29289321881, PI, 0.0)
	assert_float(v).is_greater(0.1)


func test_uphill_divides_target_speed() -> void:
	var motor := PlayerLocomotion.new()
	## Ground rising 0.5 m per metre along +Z (the stick direction).
	motor.ground_sampler = func(p: Vector3) -> float: return p.z * 0.5
	_frames(motor, 80, Vector3.BACK, 1.0)
	assert_float(motor.speed_gx).is_equal_approx(PlayerLocomotion.ORIG_WALK / 1.25, 0.001)


func test_locked_action_brakes() -> void:
	var motor := PlayerLocomotion.new()
	_frames(motor, 60, Vector3.BACK, 1.0)
	var before: float = motor.speed_gx
	motor.tick(FRAME, Vector3.BACK, 1.0, true, true)
	assert_float(motor.speed_gx).is_less(before)


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
	## Brakes 0.175 / frame regardless of the stick; waits for the clip to end.
	var before: float = motor.speed_gx
	_frames(motor, 1, Vector3.BACK, 1.0, true)
	assert_float(motor.speed_gx).is_equal_approx(before - PlayerLocomotion.ORIG_TUMBLE_BRAKE, 0.0001)
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
