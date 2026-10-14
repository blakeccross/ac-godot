extends GdUnitTestSuite

## Shooting stars on the pond at the Meteor Shower (`ef_shooting_set`, `ef_shooting`).


func test_stars_come_fastest_at_half_past_seven() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for _i: int in 50:
		assert_int(MeteorShower.next_interval(17 * 3600, rng)).is_between(540, 660)
		assert_int(MeteorShower.next_interval(19 * 3600 + 1800, rng)).is_between(60, 180)
		assert_int(MeteorShower.next_interval(21 * 3600, rng)).is_between(540, 660)
	## Halfway up the ramp: 360 ± 60.
	assert_int(MeteorShower.next_interval(18 * 3600 + 2700, rng)).is_between(300, 420)


func test_streak_crosses_the_strip_around_frame_120() -> void:
	## The 32-row streak is in the strip's window (rows 0–32) only while the offset is
	## within ±32 texels.
	assert_float(MeteorShower.scroll_at(120)).is_equal(0.0)
	assert_bool(absf(MeteorShower.scroll_at(90)) > 32.0).is_true()
	assert_bool(absf(MeteorShower.scroll_at(150)) > 32.0).is_true()
	assert_bool(absf(MeteorShower.scroll_at(110)) < 32.0).is_true()
