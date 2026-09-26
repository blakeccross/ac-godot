class_name TestBugGround
extends GdUnitTestSuite

## `aINS_BGcheck` (`mCoBG_AdjustActorY`) — insects stand on the ground every frame, not only
## while a program happens to ask. Ground here is a sampler, not a town.

var _rng: RandomNumberGenerator = null


func before_test() -> void:
	BugCatalog.reload()
	Clock.reset_to_default()
	Clock.paused = true
	_rng = RandomNumberGenerator.new()
	_rng.seed = 11


func _sense(height: Callable) -> BugActor.Sense:
	var s := BugActor.Sense.new()
	s.ground = func(p: Vector3) -> Dictionary:
		var g: float = float(height.call(p))
		return {"ground_y": g, "water": false, "water_y": g + BugActor.WATER_DEPTH_GX}
	return s


func _hopper(at_gx: Vector3) -> BugActor:
	return BugActor.create(
		BugCatalog.get_bug(&"grasshopper"), BugData.Habitat.GROUND, at_gx * BugActor.GX_M, _rng
	)


func test_waiting_grasshopper_stays_on_the_ground() -> void:
	## Gravity keeps pulling while it waits (up to ~720 frames); only the BG check holds it up.
	var s := _sense(func(_p: Vector3) -> float: return 0.0)
	var a := _hopper(Vector3(100.0, 0.0, 100.0))
	for _i: int in 900:
		a.frame(s)
		assert_float(a.pos.y).is_greater_equal(-0.001)
	assert_bool(a.bg_on_ground).is_true()


func test_hops_never_end_a_frame_under_a_slope() -> void:
	## Ground rising 0.5 GX per GX northward (−Z), like a terrace ramp.
	var slope := func(p: Vector3) -> float: return maxf(0.0, -p.z * 0.5)
	var s := _sense(slope)
	s.player_position = Vector3(100.0, 0.0, 140.0) * BugActor.GX_M
	var a := _hopper(Vector3(100.0, 0.0, 100.0))
	var lowest: float = 0.0
	for _i: int in 2000:
		a.frame(s)
		lowest = minf(lowest, a.pos.y - float(slope.call(a.pos)))
	assert_float(lowest).is_greater_equal(-0.001)


func test_grounded_insect_follows_ground_down_a_gentle_slope() -> void:
	## `old_on_ground && old_ground_y > ground_y`: a step no larger than the XZ move sticks.
	var s := _sense(func(p: Vector3) -> float: return -p.x * 0.2)
	var a := _hopper(Vector3(0.0, 0.0, 0.0))
	a.frame(s)
	assert_bool(a.bg_on_ground).is_true()
	a.pos = Vector3(2.0, 0.0, 0.0)  ## moved 2 GX; ground now 0.4 lower
	a.last_pos = Vector3(0.0, 0.0, 0.0)
	a.pos_speed.y = 0.0
	a._bg_check(s)
	assert_bool(a.bg_on_ground).is_true()
	assert_float(a.pos.y).is_equal_approx(-0.4, 0.0001)


func test_no_ground_sampler_means_no_collision() -> void:
	## Program unit tests without a town keep their own flat-plane clamps.
	var a := _hopper(Vector3(0.0, 5.0, 0.0))
	a.bg_type = 2
	a._bg_check(BugActor.Sense.new())
	assert_float(a.pos.y).is_equal(5.0)
	assert_bool(a.bg_on_ground).is_false()
