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


func test_water_ring_grows_fades_and_drifts() -> void:
	## `eTH_ct` / `eTH_mv`: arg 3 is a 32-tick ring easing out to 0.02, alpha 150 → 0,
	## drifting 0.125 GX a tick along the flow.
	var host := Node3D.new()
	add_child(host)
	var ring: FieldFx = FieldFx.spawn(host, FieldFx.Kind.HAMON, Vector3.ZERO, 0.0, 3, 0)
	assert_object(ring).is_not_null()
	assert_int(ring.timer).is_equal(32)
	assert_float(ring.spec[3]).is_equal(150.0)
	for i: int in 16:
		ring._move()
		ring.timer -= 1
	assert_float(ring.scale_gx.x).is_greater(0.001)
	assert_float(ring.scale_gx.x).is_less_equal(0.02)
	## `*_mv` runs before `timer--`: the 16th move still saw 17 ticks left.
	assert_float(ring.spec[0]).is_equal_approx(150.0 * 17.0 / 32.0, 0.01)
	assert_float(ring.pos_gx.z).is_equal_approx(16.0 * 0.125, 0.0001)
	## The big ones (arg 0) start brighter; arg 4 is the slow 52-tick one.
	var big: FieldFx = FieldFx.spawn(host, FieldFx.Kind.HAMON, Vector3.ZERO, 0.0, 0, 0)
	assert_float(big.spec[3]).is_equal(200.0)
	var slow: FieldFx = FieldFx.spawn(host, FieldFx.Kind.HAMON, Vector3.ZERO, 0.0, 4, 0)
	assert_int(slow.timer).is_equal(52)
	host.queue_free()


func test_a_fleeing_shadow_rings_by_size() -> void:
	## `aGYO_KAGE` at `delete_timer == 96`.
	var puff := FishSchool.Puff.new()
	puff.size = FishData.SizeClass.XS
	assert_int(puff.kage_ripple()).is_equal(2)
	puff.size = FishData.SizeClass.M
	assert_int(puff.kage_ripple()).is_equal(1)
	puff.size = FishData.SizeClass.L
	assert_int(puff.kage_ripple()).is_equal(0)
	puff.size = FishData.SizeClass.XXL
	assert_int(puff.kage_ripple()).is_equal(-1)


func test_umbrella_twirl_sprays_only_in_rain() -> void:
	## `eKasamizu_mv`: a drop every other tick of its 24 while it rains, from 45 GX up and
	## 20 behind the twirler.
	var host := Node3D.new()
	add_child(host)
	var was: StringName = Game.weather
	Game.weather = &"rain"
	var spray: FieldFx = FieldFx.spawn(host, FieldFx.Kind.KASAMIZU, Vector3.ZERO, 0.0)
	assert_int(spray.timer).is_equal(24)
	assert_float(spray.pos_gx.y).is_equal(45.0)
	assert_float(spray.pos_gx.z).is_equal(-20.0)
	for i: int in 24:
		spray._move()
	assert_int(host.get_child_count()).is_equal(1 + 12)
	var drop := host.get_child(1) as FieldFx
	assert_int(drop.timer).is_equal(20)
	assert_float(drop.acc.y).is_equal_approx(-0.105, 0.00001)
	assert_float(drop.vel.length()).is_equal_approx(2.5, 0.0001)
	Game.weather = &"clear"
	var dry: FieldFx = FieldFx.spawn(host, FieldFx.Kind.KASAMIZU, Vector3.ZERO, 0.0)
	var before: int = host.get_child_count()
	for i: int in 24:
		dry._move()
	assert_int(host.get_child_count()).is_equal(before)
	Game.weather = was
	host.queue_free()
