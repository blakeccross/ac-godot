class_name TestPlayerLocomotion
extends GdUnitTestSuite

const DT := 1.0 / 30.0


func test_meter_scale_matches_tile_ratio() -> void:
	assert_float(PlayerLocomotion.WALK_SPEED).is_equal_approx(7.3125, 0.0001)
	assert_float(PlayerLocomotion.RUN_SPEED).is_equal_approx(11.25, 0.0001)
	assert_float(PlayerLocomotion.WALK_SPEED / PlayerLocomotion.RUN_SPEED).is_equal_approx(
		4.875 / 7.5, 0.0001
	)


func test_one_frame_accel_from_rest() -> void:
	var motor := PlayerLocomotion.new()
	motor.tick(DT, Vector3.BACK, 1.0, false, false)
	assert_float(motor.planar_speed).is_equal_approx(PlayerLocomotion.ACCEL * DT, 0.0001)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.WALK)


func test_reaches_walk_cap_without_dash() -> void:
	var motor := PlayerLocomotion.new()
	for _i: int in 30:
		motor.tick(DT, Vector3.BACK, 1.0, false, false)
	assert_float(motor.planar_speed).is_equal_approx(PlayerLocomotion.WALK_SPEED, 0.05)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.RUN)


func test_dash_uses_run_cap() -> void:
	var motor := PlayerLocomotion.new()
	for _i: int in 40:
		motor.tick(DT, Vector3.BACK, 1.0, true, false)
	assert_float(motor.planar_speed).is_equal_approx(PlayerLocomotion.RUN_SPEED, 0.05)
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.DASH)


func test_release_decelerates() -> void:
	var motor := PlayerLocomotion.new()
	motor.planar_speed = PlayerLocomotion.WALK_SPEED
	motor.tick(DT, Vector3.ZERO, 0.0, false, false)
	assert_float(motor.planar_speed).is_equal_approx(
		PlayerLocomotion.WALK_SPEED - PlayerLocomotion.DECEL * DT, 0.0001
	)


func test_locked_action_brakes() -> void:
	var motor := PlayerLocomotion.new()
	motor.planar_speed = PlayerLocomotion.WALK_SPEED
	motor.tick(DT, Vector3.BACK, 1.0, true, true)
	assert_float(motor.planar_speed).is_less(PlayerLocomotion.WALK_SPEED)


func test_reverse_zeros_speed_until_facing_catches_up() -> void:
	var motor := PlayerLocomotion.new()
	motor.facing = 0.0
	motor.planar_speed = PlayerLocomotion.WALK_SPEED
	motor.tick(DT, Vector3.FORWARD, 1.0, false, false)
	assert_float(motor.planar_speed).is_less(PlayerLocomotion.WALK_SPEED)
	assert_float(absf(motor.facing)).is_greater(0.01)


func test_analog_scales_walk_cap() -> void:
	var motor := PlayerLocomotion.new()
	for _i: int in 40:
		motor.tick(DT, Vector3.BACK, 0.5, false, false)
	assert_float(motor.planar_speed).is_equal_approx(PlayerLocomotion.WALK_SPEED * 0.5, 0.08)


func test_full_stick_turn_mod() -> void:
	assert_float(PlayerLocomotion.turn_mod(1.0)).is_equal(0.5)
	assert_float(PlayerLocomotion.turn_mod(0.05)).is_equal(0.01)


func test_idle_gait() -> void:
	var motor := PlayerLocomotion.new()
	assert_that(motor.gait()).is_equal(PlayerLocomotion.Gait.WAIT)


func test_facing_point_is_along_plus_z_at_zero_yaw() -> void:
	var motor := PlayerLocomotion.new()
	motor.facing = 0.0
	var point: Vector3 = motor.facing_point(Vector3.ZERO, 2.0)
	assert_vector(point).is_equal(Vector3(0.0, 0.0, 2.0))
