extends GdUnitTestSuite

## `ef_bush_happa.c` / `ef_bush_yuki.c`: leaves and snow puffs from a shaken tree, on `delta`.

const GX := FieldCatalog.GX_TO_METERS


func _leaf() -> TreeEffects:
	var host: Node3D = auto_free(Node3D.new())
	add_child(host)
	var crown := Vector3(0.0, TreeEffects.CROWN_GX * TreeEffects.GX, 0.0)
	TreeEffects.leaf(host, crown, PlantData.Family.HARDWOOD, false)
	return host.get_child(0) as TreeEffects


## Steps `fx` for `seconds` at `hz` updates a second.
func _run(fx: TreeEffects, seconds: float, hz: float = 60.0) -> void:
	for _i: int in roundi(seconds * hz):
		fx.step(1.0 / hz)


## Launches `fx` as a leaf going `vy` GX a tick upward, like `eBushHappa_ct`.
func _throw(fx: TreeEffects, vy_gx_per_tick: float) -> void:
	fx.velocity = Vector3(0.0, vy_gx_per_tick * GX * 60.0, 0.0)
	fx.acceleration = Vector3(0.0, 0.5 * (0.1 * -vy_gx_per_tick) * GX * 3600.0, 0.0)
	fx.falling = false


func test_leaf_lives_80_ticks_then_frees() -> void:
	var fx: TreeEffects = _leaf()
	assert_float(fx.time_left).is_equal_approx(80.0 / 60.0, 0.0001)
	_run(fx, TreeEffects.LEAF_LIFE - 0.1)
	assert_float(fx.time_left).is_greater(0.0)
	_run(fx, 0.2)
	assert_float(fx.time_left).is_less_equal(0.0)
	fx._process(0.0)
	assert_bool(fx.is_queued_for_deletion()).is_true()


func test_leaf_thrown_down_switches_to_the_falling_phase() -> void:
	var fx: TreeEffects = _leaf()
	_throw(fx, -0.3)
	var start_y: float = fx.drift_position.y
	_run(fx, 1.0)
	## `eBushHappa_mv`: once it is falling it sways under a fixed −0.05 GX/tick² pull and
	## ends up below where it began.
	assert_bool(fx.falling).is_true()
	assert_float(fx.acceleration.y).is_equal_approx(-TreeEffects.LEAF_FALL_GRAVITY, 0.0001)
	assert_float(fx.drift_position.y).is_less(start_y)


func test_leaf_thrown_up_rises_first_then_falls() -> void:
	var fx: TreeEffects = _leaf()
	_throw(fx, 0.4)
	var start_y: float = fx.drift_position.y
	_run(fx, 5.0 / 60.0)
	## Braked at a twentieth of its launch climb, it rises for about a third of a second.
	assert_bool(fx.falling).is_false()
	assert_float(fx.drift_position.y).is_greater(start_y)
	_run(fx, 40.0 / 60.0)
	assert_bool(fx.falling).is_true()


func test_leaf_fades_over_its_last_28_ticks() -> void:
	var fx: TreeEffects = _leaf()
	_run(fx, TreeEffects.LEAF_LIFE - 14.0 / 60.0)
	## Half opaque with 14 ticks left.
	assert_float(fx.opacity()).is_equal_approx(0.5, 0.01)
	assert_float(TreeEffects.LEAF_FADE_TIME).is_equal_approx(28.0 / 60.0, 0.0001)


func test_leaf_lands_in_the_same_place_at_any_frame_rate() -> void:
	var a: TreeEffects = _leaf()
	var b: TreeEffects = _leaf()
	for fx: TreeEffects in [a, b]:
		fx.drift_position = Vector3.ZERO
		_throw(fx, 0.3)
		fx.velocity.x = 1.0 * GX * 60.0
	_run(a, 1.0, 60.0)
	_run(b, 1.0, 15.0)
	assert_bool(a.falling and b.falling).is_true()
	assert_vector(b.drift_position).is_equal_approx(a.drift_position, Vector3.ONE * 0.01)


func test_snow_puff_drops_with_gravity_and_lives_60_ticks() -> void:
	var host: Node3D = auto_free(Node3D.new())
	add_child(host)
	TreeEffects.snow(host, Vector3(0.0, 4.5, 0.0), false)
	var fx := host.get_child(0) as TreeEffects
	assert_float(fx.time_left).is_equal_approx(1.0, 0.0001)
	## −0.125 GX/tick².
	assert_float(fx.acceleration.y).is_equal_approx(-0.125 * GX * 3600.0, 0.0001)
	_run(fx, 0.5)
	assert_float(fx.opacity()).is_greater(0.0)
	_run(fx, 0.6)
	assert_float(fx.time_left).is_less_equal(0.0)
	assert_float(fx.opacity()).is_equal(0.0)
