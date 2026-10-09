class_name TestImpactStar
extends GdUnitTestSuite

## `ef_impact_star` timing, and the reflect knock-back speed.


func test_star_shrinks_then_fades() -> void:
	assert_float(ImpactStar.scale_at(40, 0.004, 0.01)).is_equal_approx(0.01, 0.0001)
	assert_float(ImpactStar.scale_at(26, 0.004, 0.01)).is_equal_approx(0.004, 0.0001)
	assert_float(ImpactStar.scale_at(10, 0.004, 0.01)).is_equal_approx(0.004, 0.0001)
	assert_float(ImpactStar.alpha_at(40)).is_equal(1.0)
	assert_float(ImpactStar.alpha_at(5)).is_equal_approx(0.5, 0.001)


func test_stars_fly_up_and_away() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var host := Node3D.new()
	add_child(host)
	for i: int in 2:
		var star: ImpactStar = ImpactStar.spawn(host, Vector3.ZERO, 0.0, i, rng)
		assert_float(star.vel_gx.y).is_greater(0.0)
		## Thrown back toward the player (−z of a south-facing strike).
		assert_float(star.vel_gx.z).is_less(0.0)
	host.queue_free()


func test_knock_back_speed_is_the_decomps() -> void:
	assert_float(ToolUse.REFLECT_STEP_BACK).is_equal(4.8)
