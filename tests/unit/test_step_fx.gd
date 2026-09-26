class_name TestStepFx
extends GdUnitTestSuite

## Step / skid / tumble effect routing (`ef_*_asimoto`, `ef_tumble`, `ef_hanatiri`).


func after_test() -> void:
	Game.reset_session()


func test_flower_index_matches_decomp_item_order() -> void:
	## `item − FLOWER_PANSIES0`: pansy 0–2, cosmos 3–5, tulip 6–8; leaves are not grown.
	assert_int(StepFx.flower_index_for_visual(&"FLOWER_PANSIES0")).is_equal(0)
	assert_int(StepFx.flower_index_for_visual(&"FLOWER_COSMOS1")).is_equal(4)
	assert_int(StepFx.flower_index_for_visual(&"FLOWER_TULIP2")).is_equal(8)
	assert_int(StepFx.flower_index_for_visual(&"FLOWER_LEAVES_PANSIES0")).is_equal(-1)


func test_calc_adjust_is_clamped_linear() -> void:
	assert_float(FieldFx.calc_adjust(0, 2, 8, 1.0, 4.0)).is_equal(1.0)
	assert_float(FieldFx.calc_adjust(5, 2, 8, 1.0, 4.0)).is_equal_approx(2.5, 0.0001)
	assert_float(FieldFx.calc_adjust(9, 2, 8, 1.0, 4.0)).is_equal(4.0)


func test_rot_y_matches_heading_convention() -> void:
	## `eEL_VectorRoteteY`: +Z rotated by θ → (sin θ, 0, cos θ).
	var v: Vector3 = FieldFx.rot_y(Vector3(0, 0, 1), PI * 0.5)
	assert_vector(v).is_equal_approx(Vector3(1, 0, 0), Vector3(0.0001, 0.0001, 0.0001))


func test_destiny_lasts_only_the_day_received() -> void:
	## `Game_play_Reset_destiny`.
	Clock.apply_snapshot({"year": 2001, "month": 5, "day": 3, "hour": 12, "minute": 0})
	Game.set_destiny(Game.Destiny.BAD_LUCK)
	assert_int(Game.destiny()).is_equal(Game.Destiny.BAD_LUCK)
	Clock.apply_snapshot({"year": 2001, "month": 5, "day": 4, "hour": 9, "minute": 0})
	assert_int(Game.destiny()).is_equal(Game.Destiny.NORMAL)
