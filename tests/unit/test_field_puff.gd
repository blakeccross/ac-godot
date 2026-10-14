class_name TestFieldPuff
extends GdUnitTestSuite

## `FieldPuff`: dust, steam and smoke as one-shot particle puffs on closed-form paths.

const GX := FieldCatalog.GX_TO_METERS


func _style(kind: FieldFx.Kind, yaw: float = 0.0, a0: int = 0, a1: int = 0) -> FieldPuff.Style:
	var at: Array[Vector3] = [Vector3.ZERO]
	return FieldPuff.style_for(kind, yaw, a0, a1, at)


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
	var closed: Vector3 = FieldPuff.offset_at(s, 0.5) / GX
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
	assert_vector(FieldPuff.offset_at(s, s.hold)).is_equal(Vector3.ZERO)
	assert_float(FieldPuff.offset_at(s, s.hold + 0.2).z).is_greater(0.0)


func test_smoke_climbs_fast_then_slow() -> void:
	var s := _style(FieldFx.Kind.KISHA_KEMURI)
	var early: float = FieldPuff.offset_at(s, 10.0 / 60.0).y
	var later: float = FieldPuff.offset_at(s, 40.0 / 60.0).y - FieldPuff.offset_at(s, 30.0 / 60.0).y
	## First 10 ticks climb more than 10 ticks after the boost has gone.
	assert_float(early).is_greater(later * 2.0)


func test_a_puff_frees_itself() -> void:
	var host := Node3D.new()
	add_child(host)
	var puff: FieldPuff = FieldPuff.spawn(host, FieldFx.Kind.DUST, Vector3.ZERO, 0.0, 0, 8)
	assert_object(puff).is_not_null()
	assert_bool(puff.emitting).is_true()
	assert_bool(puff.one_shot).is_true()
	## `FieldFx.spawn` hands puffs over and returns nothing.
	assert_object(FieldFx.spawn(host, FieldFx.Kind.STEAM, Vector3.ZERO, 0.0)).is_null()
	assert_int(host.get_child_count()).is_equal(2)
	host.queue_free()
