class_name TestStatueSparkle
extends GdUnitTestSuite

## `ef_douzou_light` timing, size and placement (`StatueSparkle`).


func test_it_swells_then_shrinks_over_24_ticks() -> void:
	var peak: float = StatueSparkle.PEAK[0]
	assert_float(StatueSparkle.scale_at(24, peak)).is_equal_approx(0.0, 1e-6)
	assert_float(StatueSparkle.scale_at(12, peak)).is_equal_approx(peak, 1e-6)
	assert_float(StatueSparkle.scale_at(0, peak)).is_equal_approx(0.0, 1e-6)
	assert_float(StatueSparkle.scale_at(18, peak)).is_equal_approx(peak * 0.5, 1e-6)


func test_gold_glints_more_often_and_higher_than_jade() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 50:
		var gold: int = StatueSparkle.next_wait(0, rng)
		assert_int(gold).is_between(5, 15)
		var jade: int = StatueSparkle.next_wait(3, rng)
		assert_int(jade).is_between(30, 90)
		var at: Vector3 = StatueSparkle.offset_gx(0, rng)
		assert_float(at.y).is_between(68.0 - 21.0, 68.0 + 21.0)
		assert_float(at.z).is_equal(14.0)


func test_a_glint_frees_itself() -> void:
	var rng := RandomNumberGenerator.new()
	var fx := StatueSparkle.spawn(self, Vector3.ZERO, 1, rng)
	assert_object(fx).is_not_null()
	for i: int in StatueSparkle.LIFE:
		fx._process(DecompTime.TICK_SEC)
	assert_bool(fx.is_queued_for_deletion()).is_true()
