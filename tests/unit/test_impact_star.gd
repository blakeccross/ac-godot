class_name TestImpactStar
extends GdUnitTestSuite

## `ef_impact_star` timing, and the reflect knock-back speed.


func test_star_shrinks_then_fades() -> void:
	## Full size at launch, shrunk after 14 ticks (0.23 s), and stays shrunk.
	assert_float(ImpactStar.size_at(0.0, 0.004, 0.01)).is_equal_approx(0.01, 0.0001)
	assert_float(ImpactStar.size_at(ImpactStar.SHRINK_TIME, 0.004, 0.01)).is_equal_approx(0.004, 0.0001)
	assert_float(ImpactStar.size_at(0.5, 0.004, 0.01)).is_equal_approx(0.004, 0.0001)
	## Opaque until the last 10 ticks, half faded 5 ticks from the end.
	assert_float(ImpactStar.opacity_at(0.0)).is_equal(1.0)
	assert_float(ImpactStar.opacity_at(ImpactStar.LIFETIME - 5.0 / 60.0)).is_equal_approx(0.5, 0.001)
	assert_float(ImpactStar.opacity_at(ImpactStar.LIFETIME)).is_equal(0.0)


func test_stars_fly_up_and_away() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var host := Node3D.new()
	add_child(host)
	for i: int in 2:
		var star: ImpactStar = ImpactStar.spawn(host, Vector3(1.0, 0.0, 2.0), 0.0, i, rng)
		assert_float(star.velocity.y).is_greater(0.0)
		## Thrown back toward the player (−z of a south-facing strike).
		assert_float(star.velocity.z).is_less(0.0)
		star.age = 0.3
		assert_float(star.position.y).is_greater(0.0)
		assert_float(star.position.z).is_less(2.0)
	host.queue_free()


func test_flight_matches_the_decomp_distance_and_frame_rate() -> void:
	## The decomp moved 6 GX then slowed by √0.85, once a tick for 40 ticks.
	var v_tick := Vector3(0.0, 6.0 * FieldCatalog.GX_TO_METERS, 0.0)
	var ticked := Vector3.ZERO
	for _i: int in 40:
		ticked += v_tick
		v_tick *= sqrt(0.85)
	var v := Vector3(0.0, ImpactStar.LAUNCH_SPEED, 0.0)
	var flown: Vector3 = ImpactStar.offset_at(v, ImpactStar.LIFETIME)
	assert_float(flown.y).is_equal_approx(ticked.y, ticked.y * 0.05)
	## Closed form: the same height whenever it is sampled.
	assert_float(ImpactStar.offset_at(v, 0.25).y).is_less(flown.y)
	assert_float(ImpactStar.offset_at(v, ImpactStar.LIFETIME).y).is_equal(flown.y)


func test_star_frees_itself_after_its_lifetime() -> void:
	var host := Node3D.new()
	add_child(host)
	var star: ImpactStar = ImpactStar.spawn(host, Vector3.ZERO, 0.0, 0, RandomNumberGenerator.new())
	await get_tree().create_timer(ImpactStar.LIFETIME + 0.2).timeout
	assert_bool(is_instance_valid(star)).is_false()
	host.queue_free()
