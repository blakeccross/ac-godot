class_name TestFieldParticle
extends GdUnitTestSuite

## `FieldParticle`: dust, steam and smoke as one-shot particle puffs on closed-form paths.

const GX := FieldCatalog.GX_TO_METERS


func _style(kind: FieldFx.Kind, yaw: float = 0.0, a0: int = 0, a1: int = 0, ground: Callable = Callable()) -> FieldParticle.Style:
	var at: Array[Vector3] = [Vector3.ZERO]
	return FieldParticle.style_for(kind, yaw, a0, a1, at, ground)


static func _floor(_at: Vector3) -> float:
	return -0.5


func test_the_path_matches_the_decomp_tick_loop() -> void:
	## `eSteam_mv`: vel += acc; pos += vel; vel *= √0.8, every tick for 30 ticks.
	var s := _style(FieldFx.Kind.STEAM)
	var v: Vector3 = s.launch / (GX * 60.0)
	var a: Vector3 = s.accel / (GX * 3600.0)
	var pos := Vector3.ZERO
	for _i: int in 30:
		v += a
		pos += v
		v *= sqrt(0.8)
	var closed: Vector3 = FieldParticle.offset_at(s, 0.5) / GX
	## Within a GX or so of the tick loop over the whole puff.
	assert_vector(closed).is_equal_approx(pos, Vector3.ONE * 1.5)


func test_dust_is_pushed_along_the_heading() -> void:
	var north := _style(FieldFx.Kind.DUST, 0.0, 0, 8)
	var east := _style(FieldFx.Kind.DUST, PI * 0.5, 0, 8)
	## arg1 8 kicks back (−z) 2 GX a tick; turned a quarter it kicks along −x.
	assert_float(north.launch.z).is_less(0.0)
	assert_float(east.launch.x).is_less(0.0)
	assert_float(absf(east.launch.z)).is_less(0.001)
	assert_float(north.lifetime).is_equal_approx(18.0 / 60.0, 0.0001)
	assert_int(north.tile0.size()).is_equal(FieldFx.DUST_TILES.size())


func test_tumble_dust_holds_then_moves() -> void:
	var s := _style(FieldFx.Kind.TUMBLE_DUST, 0.0, 0, 7)
	assert_float(s.hold).is_equal_approx(6.0 / 60.0, 0.0001)
	assert_vector(FieldParticle.offset_at(s, s.hold)).is_equal(Vector3.ZERO)
	assert_float(FieldParticle.offset_at(s, s.hold + 0.2).z).is_greater(0.0)


func test_smoke_climbs_fast_then_slow() -> void:
	var s := _style(FieldFx.Kind.KISHA_KEMURI)
	var early: float = FieldParticle.offset_at(s, 10.0 / 60.0).y
	var later: float = FieldParticle.offset_at(s, 40.0 / 60.0).y - FieldParticle.offset_at(s, 30.0 / 60.0).y
	## First 10 ticks climb more than 10 ticks after the boost has gone.
	assert_float(early).is_greater(later * 2.0)


func test_a_puff_frees_itself() -> void:
	var host := Node3D.new()
	add_child(host)
	var puff: FieldParticle = FieldParticle.spawn(host, FieldFx.Kind.DUST, Vector3.ZERO, 0.0, 0, 8)
	assert_object(puff).is_not_null()
	assert_bool(puff.emitting).is_true()
	assert_bool(puff.one_shot).is_true()
	## `FieldFx.spawn` hands puffs over and returns nothing.
	assert_object(FieldFx.spawn(host, FieldFx.Kind.STEAM, Vector3.ZERO, 0.0)).is_null()
	assert_int(host.get_child_count()).is_equal(2)
	host.queue_free()


func test_a_drop_lands_on_the_ground_and_splats_there() -> void:
	## Flicked up at 2–3.5 GX a tick under −0.375 it comes down 3 GX above the ground and
	## stays there for its splat.
	var s := _style(FieldFx.Kind.MIZUTAMA, 0.0, 0, 0x0000, _floor)
	assert_float(s.land_time).is_greater(0.0)
	var landed: Vector3 = FieldParticle.offset_at(s, s.land_time)
	assert_float(landed.y).is_equal_approx(-0.5 + 3.0 * GX, 0.02)
	assert_vector(FieldParticle.offset_at(s, s.land_time + 0.1)).is_equal_approx(landed, Vector3.ONE * 0.0001)
	assert_float(s.lifetime).is_equal_approx(s.land_time + FieldParticle.SPLAT_TIME, 0.0001)
	## Its splat frames count from the landing.
	assert_int(s.tile0[0]).is_equal(0)
	assert_int(s.tile0[6]).is_equal(3)


func test_kicks_lie_tilted_on_the_ground() -> void:
	var sand := _style(FieldFx.Kind.SAND, 0.0, 1)
	assert_bool(sand.billboard).is_false()
	assert_float(sand.tilt).is_equal_approx(deg_to_rad(-45.0), 0.0001)
	assert_int(sand.mode).is_equal(3)
	## A frame every four ticks: 0, 0, 1, 1, 2, 2, 3, 3.
	assert_that(Array(sand.tile0)).is_equal([0, 0, 1, 1, 2, 2, 3, 3])
	var splash := _style(FieldFx.Kind.SIBUKI, 0.0, 0)
	## Hidden its first two steps, then four frames.
	assert_float(splash.alphas[0]).is_equal(0.0)
	assert_float(splash.alphas[2]).is_equal(1.0)
	assert_float(splash.lifetime).is_equal_approx(12.0 / 60.0, 0.0001)
	## Every table the same length.
	for st: FieldParticle.Style in [sand, splash, _style(FieldFx.Kind.KASAMIZUTAMA)]:
		var n: int = st.tile0.size()
		assert_int(st.tile1.size()).is_equal(n)
		assert_int(st.lods.size()).is_equal(n)
		assert_int(st.alphas.size()).is_equal(n)
		assert_int(st.sizes.size()).is_equal(n)
