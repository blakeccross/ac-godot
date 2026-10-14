class_name TestMotion
extends GdUnitTestSuite

## `Motion`: delta-based smoothing and chance give the same result at any frame rate.


func test_damp_halves_the_gap_each_half_life() -> void:
	assert_float(Motion.damp(0.0, 10.0, 0.2, 0.2)).is_equal_approx(5.0, 0.0001)
	assert_float(Motion.damp(0.0, 10.0, 0.2, 0.4)).is_equal_approx(7.5, 0.0001)
	## No time, no movement; no half-life, straight there.
	assert_float(Motion.damp(3.0, 10.0, 0.2, 0.0)).is_equal(3.0)
	assert_float(Motion.damp(3.0, 10.0, 0.0, 0.016)).is_equal(10.0)


func test_damp_does_not_depend_on_the_frame_rate() -> void:
	var one_step: float = Motion.damp(0.0, 1.0, 0.1, 0.3)
	var many: float = 0.0
	for _i: int in 30:
		many = Motion.damp(many, 1.0, 0.1, 0.01)
	assert_float(many).is_equal_approx(one_step, 0.0001)
	var v_one: Vector3 = Motion.damp_vec3(Vector3.ZERO, Vector3(4.0, 0.0, -2.0), 0.1, 0.3)
	var v_many: Vector3 = Vector3.ZERO
	for _i: int in 3:
		v_many = Motion.damp_vec3(v_many, Vector3(4.0, 0.0, -2.0), 0.1, 0.1)
	assert_vector(v_many).is_equal_approx(v_one, Vector3.ONE * 0.0001)


func test_damp_angle_takes_the_short_way() -> void:
	## From just under +π to just over −π is a small step across the seam, not a full turn.
	var a: float = Motion.damp_angle(PI - 0.1, -PI + 0.1, 0.1, 0.1)
	assert_float(absf(angle_difference(a, PI))).is_less(0.11)


func test_fraction_half_life_matches_the_tick_curve() -> void:
	## `MLib.HALF_FRACTION` per tick closes half the gap every two ticks.
	var half_life: float = Motion.half_life_from_fraction(MLib.HALF_FRACTION)
	assert_float(half_life).is_equal_approx(2.0 * DecompTime.TICK_SEC, 0.00001)
	## 45 ticks of the old per-tick `add_calc` land where one second-based `damp` does.
	var ticked: float = 0.0
	for _i: int in 45:
		ticked += (100.0 - ticked) * 0.1
	var damped: float = Motion.damp(0.0, 100.0, Motion.half_life_from_fraction(0.1), 45.0 * DecompTime.TICK_SEC)
	assert_float(damped).is_equal_approx(ticked, 0.001)


func test_happens_keeps_its_rate_at_any_frame_rate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	## Twice a second for 100 s: about 200 hits whether stepped at 60 or 10 Hz.
	for hz: float in [60.0, 10.0]:
		var hits: int = 0
		for _i: int in int(100.0 * hz):
			if Motion.happens(2.0, 1.0 / hz, rng):
				hits += 1
		assert_int(hits).override_failure_message("%d hits at %d Hz" % [hits, int(hz)]).is_between(170, 230)
	assert_bool(Motion.happens(0.0, 1.0, rng)).is_false()
	assert_bool(Motion.happens(5.0, 0.0, rng)).is_false()


func test_rate_from_chance_round_trips_a_per_tick_roll() -> void:
	## A 1-in-60 roll every tick is a little under once a second.
	var rate: float = Motion.rate_from_chance(1.0 / 60.0)
	assert_float(rate).is_equal_approx(1.008, 0.001)
	assert_float(1.0 - exp(-rate * DecompTime.TICK_SEC)).is_equal_approx(1.0 / 60.0, 0.000001)
	assert_float(Motion.rate_from_chance(0.0)).is_equal(0.0)
