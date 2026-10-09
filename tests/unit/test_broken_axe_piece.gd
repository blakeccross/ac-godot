class_name TestBrokenAxePiece
extends GdUnitTestSuite

## `ef_break_axe`: the halves of a broken axe.


func _piece(which: int, ground: float, water: bool = false) -> BrokenAxePiece:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var p := BrokenAxePiece.new()
	p.setup(which, Vector3.ZERO, 0.0, rng)
	p.ground_gx = func(_at: Vector3) -> float: return ground
	p.water_at = func(_at: Vector3) -> bool: return water
	add_child(p)
	return p


func test_they_fly_up_and_back_over_the_shoulder() -> void:
	var p := _piece(0, 0.0)
	## Facing +z, thrown behind (−z) and up.
	assert_float(p.vel.z).is_less(0.0)
	assert_float(p.vel.y).is_greater(3.9)
	assert_float(p.pos_gx.y).is_equal(34.0)
	assert_int(p.timer).is_between(70, 88)
	p.free()


func test_they_bounce_on_the_ground_and_settle() -> void:
	var p := _piece(1, 0.0)
	var bounced := false
	for i: int in 70:
		var vy: float = p.vel.y
		p.step()
		p.timer -= 1
		if vy < 0.0 and p.vel.y > 0.0:
			bounced = true
		assert_float(p.pos_gx.y).is_greater_equal(BrokenAxePiece.LIFT[1] - 0.001)
	assert_bool(bounced).is_true()
	p.free()


func test_in_water_they_sink() -> void:
	var p := _piece(0, 0.0, true)
	for i: int in 60:
		p.step()
		p.timer -= 1
	assert_float(p.pos_gx.y).is_less(BrokenAxePiece.LIFT[0])
	p.free()


func test_they_fade_over_the_last_30_ticks() -> void:
	assert_float(BrokenAxePiece.alpha_at(40)).is_equal(1.0)
	assert_float(BrokenAxePiece.alpha_at(15)).is_equal(0.5)
	assert_float(BrokenAxePiece.alpha_at(0)).is_equal(0.0)
