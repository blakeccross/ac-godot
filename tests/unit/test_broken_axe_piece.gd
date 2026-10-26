class_name TestBrokenAxePiece
extends GdUnitTestSuite

## `ef_break_axe`: the halves of a broken axe, on `delta` in metres.

const GX := FieldCatalog.GX_TO_METERS


func _piece(which: int, ground: float, water: bool = false) -> BrokenAxePiece:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var p := BrokenAxePiece.new()
	p.setup(which, Vector3.ZERO, 0.0, rng)
	p.ground_at = func(_at: Vector3) -> float: return ground
	p.water_at = func(_at: Vector3) -> bool: return water
	add_child(p)
	return p


func _run(p: BrokenAxePiece, seconds: float, hz: float = 60.0) -> void:
	for _i: int in roundi(seconds * hz):
		p.advance(1.0 / hz)


func test_they_fly_up_and_back_over_the_shoulder() -> void:
	var p := _piece(0, 0.0)
	## Facing +z, thrown behind (−z) and up at 4–5 GX a tick.
	assert_float(p.vel.z).is_less(0.0)
	assert_float(p.vel.y).is_greater(3.9 * GX * 60.0)
	assert_float(p.pos.y).is_equal_approx(34.0 * GX, 0.0001)
	assert_float(p.lifetime).is_between(70.0 / 60.0, 88.0 / 60.0)
	p.free()


func test_they_bounce_on_the_ground_and_settle() -> void:
	var p := _piece(1, 0.0)
	var bounced := false
	for i: int in 70:
		var vy: float = p.vel.y
		p.advance(1.0 / 60.0)
		if vy < 0.0 and p.vel.y > 0.0:
			bounced = true
		assert_float(p.pos.y).is_greater_equal(BrokenAxePiece.LIFT[1] - 0.001)
	assert_bool(bounced).is_true()
	p.free()


func test_the_first_bounce_is_the_same_at_any_frame_rate() -> void:
	var a := _piece(1, 0.0)
	var b := _piece(1, 0.0)
	## Past its first bounce (about 0.65 s in): it lands at the same moment either way.
	_run(a, 1.0, 60.0)
	_run(b, 1.0, 15.0)
	assert_vector(b.pos).is_equal_approx(a.pos, Vector3.ONE * 0.02)
	a.free()
	b.free()


func test_in_water_they_sink() -> void:
	var p := _piece(0, 0.0, true)
	_run(p, 1.0)
	assert_float(p.pos.y).is_less(BrokenAxePiece.LIFT[0])
	p.free()


func test_they_fade_over_the_last_30_ticks() -> void:
	assert_float(BrokenAxePiece.alpha_at(40.0 / 60.0)).is_equal(1.0)
	assert_float(BrokenAxePiece.alpha_at(15.0 / 60.0)).is_equal_approx(0.5, 0.0001)
	assert_float(BrokenAxePiece.alpha_at(0.0)).is_equal(0.0)


## The halves fly on `AXE_BREAK1`'s frame 15 and the sting swells on `HATI2`'s frame 21, as
## clip events on the player's body clips rather than counted frames.
func test_break_and_sting_are_clip_events() -> void:
	var player: Player = auto_free(load("res://scenes/actors/player.gd").new())
	var marks: Dictionary = player._clip_marks()
	assert_that(marks.get(AxeWear.ANIM_BREAK)).contains([[AxeWear.PIECES_FRAME, &"fx_axe_pieces"]])
	assert_that(marks.get(&"ply_1_hati2")).contains([[Player.STUNG_SWELL_FRAME, &"sting_swell"]])
