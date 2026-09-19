extends GdUnitTestSuite

## `ef_bush_happa.c` / `ef_bush_yuki.c` stepped on the 60 Hz effect tick.


func _leaf() -> TreeFx:
	var host: Node3D = auto_free(Node3D.new())
	add_child(host)
	var crown := Vector3(0.0, TreeFx.CROWN_GX * TreeFx.GX, 0.0)
	TreeFx.leaf(host, crown, PlantData.Family.HARDWOOD, false)
	return host.get_child(0) as TreeFx


func test_leaf_lives_80_ticks_then_frees() -> void:
	var fx: TreeFx = _leaf()
	assert_int(fx._timer).is_equal(TreeFx.LEAF_LIFE)
	for _i: int in TreeFx.LEAF_LIFE:
		fx._step()
	assert_int(fx._timer).is_equal(0)


func test_leaf_thrown_down_switches_to_the_falling_phase() -> void:
	var fx: TreeFx = _leaf()
	fx._velocity.y = -0.3
	fx._accel.y = 0.5 * (0.1 * -fx._velocity.y)
	var start_y: float = fx._pos_gx.y
	for _i: int in 60:
		fx._step()
	## `eBushHappa_mv`: once vy <= 0 the leaf sways (`effect_specific[2] = 1`) under a
	## fixed −0.05 GX/tick² pull and ends up below where it began.
	assert_bool(fx._falling).is_true()
	assert_float(fx._accel.y).is_equal_approx(-0.05, 0.0001)
	assert_float(fx._pos_gx.y).is_less(start_y)


func test_leaf_thrown_up_rises_first_then_falls() -> void:
	var fx: TreeFx = _leaf()
	fx._velocity.y = 0.4
	fx._accel.y = 0.5 * (0.1 * -fx._velocity.y)
	var start_y: float = fx._pos_gx.y
	for _i: int in 5:
		fx._step()
	## The launch pull is fixed at −0.05·vy = −0.02 GX/tick², so it climbs for ~20 ticks.
	assert_bool(fx._falling).is_false()
	assert_float(fx._pos_gx.y).is_greater(start_y)
	for _i: int in 40:
		fx._step()
	assert_bool(fx._falling).is_true()


func test_leaf_fades_over_its_last_28_ticks() -> void:
	var fx: TreeFx = _leaf()
	for _i: int in TreeFx.LEAF_LIFE - 14:
		fx._step()
	assert_int(fx._timer).is_equal(14)
	## `calc_adjust(timer, 0, 28, 0, 255)`: half opaque with 14 ticks left.
	assert_float(clampf(float(fx._timer) / TreeFx.LEAF_FADE_TICKS, 0.0, 1.0)).is_equal_approx(0.5, 0.001)


func test_snow_puff_drops_with_gravity_and_lives_60_ticks() -> void:
	var host: Node3D = auto_free(Node3D.new())
	add_child(host)
	TreeFx.snow(host, Vector3(0.0, 4.5, 0.0), false)
	var fx := host.get_child(0) as TreeFx
	assert_int(fx._timer).is_equal(TreeFx.SNOW_LIFE)
	assert_float(fx._accel.y).is_equal_approx(-0.125, 0.0001)
	for _i: int in TreeFx.SNOW_LIFE:
		fx._step()
	assert_int(fx._timer).is_equal(0)
