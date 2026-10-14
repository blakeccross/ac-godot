class_name TestStatueSparkle
extends GdUnitTestSuite

## `ef_douzou_light` timing, size and placement (`StatueSparkle`).


func test_it_swells_then_shrinks_over_24_ticks() -> void:
	assert_float(StatueSparkle.LIFETIME).is_equal_approx(24.0 / 60.0, 1e-6)
	var fx := StatueSparkle.spawn(self, Vector3.ZERO, 0, RandomNumberGenerator.new())
	await get_tree().create_timer(StatueSparkle.HALF_LIFE * 0.5).timeout
	assert_float(fx.size).is_between(0.0001, StatueSparkle.PEAK[0])
	await get_tree().create_timer(StatueSparkle.HALF_LIFE).timeout
	assert_float(fx.size).is_less(StatueSparkle.PEAK[0])


func test_gold_glints_more_often_and_higher_than_jade() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 50:
		var gold: float = StatueSparkle.next_wait(0, rng)
		assert_float(gold).is_between(5.0 / 60.0, 15.0 / 60.0)
		var jade: float = StatueSparkle.next_wait(3, rng)
		assert_float(jade).is_between(0.5, 1.5)
		var at: Vector3 = StatueSparkle.offset_gx(0, rng)
		assert_float(at.y).is_between(68.0 - 21.0, 68.0 + 21.0)
		assert_float(at.z).is_equal(14.0)


func test_a_glint_frees_itself() -> void:
	var rng := RandomNumberGenerator.new()
	var fx := StatueSparkle.spawn(self, Vector3.ZERO, 1, rng)
	assert_object(fx).is_not_null()
	await get_tree().create_timer(StatueSparkle.LIFETIME + 0.15).timeout
	assert_bool(is_instance_valid(fx)).is_false()
