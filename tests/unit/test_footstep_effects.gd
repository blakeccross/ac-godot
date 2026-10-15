class_name TestFootstepEffects
extends GdUnitTestSuite

## Step / skid / tumble effect routing (`ef_*_asimoto`, `ef_tumble`, `ef_hanatiri`).


func after_test() -> void:
	Game.reset_session()


func test_flower_index_matches_decomp_item_order() -> void:
	## `item − FLOWER_PANSIES0`: pansy 0–2, cosmos 3–5, tulip 6–8; leaves are not grown.
	assert_int(FootstepEffects.flower_index_for_visual(&"FLOWER_PANSIES0")).is_equal(0)
	assert_int(FootstepEffects.flower_index_for_visual(&"FLOWER_COSMOS1")).is_equal(4)
	assert_int(FootstepEffects.flower_index_for_visual(&"FLOWER_TULIP2")).is_equal(8)
	assert_int(FootstepEffects.flower_index_for_visual(&"FLOWER_LEAVES_PANSIES0")).is_equal(-1)


func test_calc_adjust_is_clamped_linear() -> void:
	assert_float(FieldEffects.calc_adjust(0, 2, 8, 1.0, 4.0)).is_equal(1.0)
	assert_float(FieldEffects.calc_adjust(5, 2, 8, 1.0, 4.0)).is_equal_approx(2.5, 0.0001)
	assert_float(FieldEffects.calc_adjust(9, 2, 8, 1.0, 4.0)).is_equal(4.0)


func test_rot_y_matches_heading_convention() -> void:
	## `eEL_VectorRoteteY`: +Z rotated by θ → (sin θ, 0, cos θ).
	var v: Vector3 = FieldEffects.rot_y(Vector3(0, 0, 1), PI * 0.5)
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
	var ring: FieldEffects = FieldEffects.spawn(host, FieldEffects.Kind.HAMON, Vector3.ZERO, 0.0, 3, 0)
	assert_object(ring).is_not_null()
	assert_float(ring.lifetime).is_equal_approx(32.0 / 60.0, 0.0001)
	assert_float(ring.ring_alpha).is_equal(150.0)
	var half: float = 16.0 / 60.0
	assert_float(ring.ring_scale(half)).is_between(0.0011, 0.02)
	assert_float(ring.ring_scale(10.0)).is_equal_approx(0.02, 0.0001)
	assert_float(ring.ring_opacity(half)).is_equal_approx(150.0 / 255.0 * 0.5, 0.001)
	assert_float(ring.ring_offset(half).z / FieldCatalog.GX_TO_METERS).is_equal_approx(16.0 * 0.125, 0.0001)
	## The big ones (arg 0) start brighter; arg 4 is the slow 52-tick one.
	var big: FieldEffects = FieldEffects.spawn(host, FieldEffects.Kind.HAMON, Vector3.ZERO, 0.0, 0, 0)
	assert_float(big.ring_alpha).is_equal(200.0)
	var slow: FieldEffects = FieldEffects.spawn(host, FieldEffects.Kind.HAMON, Vector3.ZERO, 0.0, 4, 0)
	assert_float(slow.lifetime).is_equal_approx(52.0 / 60.0, 0.0001)
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
	var was: StringName = Game.town.weather
	Game.town.weather = &"rain"
	var spray: FieldEffects = FieldEffects.spawn(host, FieldEffects.Kind.KASAMIZU, Vector3.ZERO, 0.0)
	assert_float(spray.lifetime).is_equal_approx(24.0 / 60.0, 0.0001)
	assert_vector(spray.origin / FieldCatalog.GX_TO_METERS).is_equal_approx(Vector3(0.0, 45.0, -20.0), Vector3.ONE * 0.001)
	for i: int in 13:
		spray.emit_drop()
	assert_int(host.get_child_count()).is_equal(1 + 12)
	assert_object(host.get_child(1) as FieldParticle).is_not_null()
	var at: Array[Vector3] = [Vector3.ZERO]
	var drop: FieldParticle.Style = FieldParticle.style_for(FieldEffects.Kind.KASAMIZUTAMA, 0.0, 0, 0, at)
	assert_float(drop.lifetime).is_equal_approx(20.0 / 60.0, 0.0001)
	assert_float(drop.accel.y).is_equal_approx(-0.105 * FieldCatalog.GX_TO_METERS * 3600.0, 0.0001)
	assert_float(drop.launch.length()).is_equal_approx(2.5 * FieldCatalog.GX_TO_METERS * 60.0, 0.0001)
	Game.town.weather = &"clear"
	var dry: FieldEffects = FieldEffects.spawn(host, FieldEffects.Kind.KASAMIZU, Vector3.ZERO, 0.0)
	var before: int = host.get_child_count()
	for i: int in 12:
		dry.emit_drop()
	assert_int(host.get_child_count()).is_equal(before)
	Game.town.weather = was
	host.queue_free()
