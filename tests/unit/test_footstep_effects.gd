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


func test_a_dig_clod_grows_tips_and_is_thrown_up() -> void:
	## `eDig_Hole_ct` / `_mv`, arg1 0: 36 ticks, grows for six to 0.0065, launched at tick 8
	## (1 GX up, falling 0.1), fading over the last ten.
	var host := Node3D.new()
	add_child(host)
	var clod: FieldEffects = FieldEffects.spawn(host, FieldEffects.Kind.DIG_CLOD, Vector3.ZERO, 0.0, 0, 0)
	assert_object(clod).is_not_null()
	assert_float(clod.lifetime).is_equal_approx(36.0 / 60.0, 0.0001)
	assert_float(clod.track_scale[6]).is_equal_approx(6.0 * FieldEffects.CLOD_GROW, 0.00001)
	## Still before the launch, then rising, then back down below where it started.
	assert_float(clod.track_pos[8].y).is_equal_approx(clod.track_pos[0].y, 0.0001)
	assert_float(clod.track_pos[14].y).is_greater(clod.track_pos[8].y)
	assert_float(clod.track_pos[36].y).is_less(clod.track_pos[8].y)
	assert_float(clod.track_alpha[36]).is_equal(0.0)
	assert_float(clod.track_rot[30].x).is_greater(clod.track_rot[8].x)
	## A fill clod (arg1 3) stops moving after 30 ticks and shrinks away.
	var fill: FieldEffects = FieldEffects.spawn(host, FieldEffects.Kind.DIG_CLOD, Vector3.ZERO, 0.0, 0, 3)
	assert_float(fill.lifetime).is_equal_approx(58.0 / 60.0, 0.0001)
	assert_vector(fill.track_pos[40]).is_equal_approx(fill.track_pos[31], Vector3.ONE * 0.0001)
	assert_float(fill.track_scale[58]).is_less(fill.track_scale[40])
	host.queue_free()


func test_wood_chips_fly_back_over_the_shoulder_and_bounce() -> void:
	## `eKikuzu_ct`: thrown back (facing + 180° + up to 80°), 60–78 ticks; on flat ground at
	## the start height they land and stay above it.
	var host := Node3D.new()
	add_child(host)
	var chip: FieldEffects = FieldEffects.spawn(host, FieldEffects.Kind.KIKUZU, Vector3.ZERO, 0.0, 0, 0,
		func(_p: Vector3) -> float: return -0.5)
	assert_object(chip).is_not_null()
	assert_float(chip.lifetime * 60.0).is_between(59.9, 78.1)
	var last: Vector3 = chip.track_pos[chip.track_pos.size() - 1] - chip.track_pos[0]
	## Facing +Z: it ends up behind (−Z).
	assert_float(last.z).is_less(0.0)
	var floor_y: float = -0.5 + 3.0 * FieldCatalog.GX_TO_METERS
	assert_float(chip.track_pos[chip.track_pos.size() - 1].y).is_greater_equal(floor_y - 0.3)
	host.queue_free()


func test_mud_and_fishing_drops_are_particles() -> void:
	var at: Array[Vector3] = [Vector3.ZERO]
	## `eDig_Mud_ct`: arg1 0 lives 32 ticks and steps through four frames.
	var mud: FieldParticle.Style = FieldParticle.style_for(FieldEffects.Kind.DIG_MUD, 0.0, 0, 0, at)
	assert_float(mud.lifetime).is_equal_approx(32.0 / 60.0, 0.0001)
	assert_int(mud.tile0[0]).is_equal(0)
	assert_int(mud.tile0[mud.tile0.size() - 1]).is_equal(3)
	## A drop off a hooked fish comes back down to the water it left.
	var drop: FieldParticle.Style = FieldParticle.style_for(FieldEffects.Kind.TURI_SUITEKI, 0.0, 0, 4, at)
	var end: Vector3 = FieldParticle.offset_at(drop, drop.lifetime)
	assert_float(end.y).is_equal_approx(0.0, 0.002)
	assert_float(FieldParticle.offset_at(drop, drop.lifetime * 0.5).y).is_greater(0.0)
