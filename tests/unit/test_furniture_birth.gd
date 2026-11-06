class_name TestFurnitureBirth
extends GdUnitTestSuite

## `aMR_FtrBirth` / `aMR_FtrBye`: a piece drops in hidden-then-squashing and shrinks away.


func _piece() -> Node3D:
	var piece := auto_free(Node3D.new()) as Node3D
	add_child(piece)
	return piece


func _ticks(fx: FurnitureBirth, count: int) -> void:
	for _i: int in count:
		fx._process(1.0 / DecompTime.TICK_HZ)


func test_a_new_piece_waits_out_of_sight_then_bounces_to_rest() -> void:
	var piece: Node3D = _piece()
	var fx: FurnitureBirth = FurnitureBirth.birth(piece, [])
	assert_bool(piece.visible).is_false()
	_ticks(fx, FurnitureBirth.WAIT_TICKS - 2)
	assert_bool(piece.visible).is_false()
	_ticks(fx, 2)
	assert_bool(piece.visible).is_true()
	## First tick: counter 6000 → sin 0.575 rad × 0.5 = 0.27 taller, as much narrower.
	assert_float(piece.scale.y).is_greater(1.2)
	assert_float(piece.scale.x).is_less(0.8)
	_ticks(fx, 400)
	assert_vector(piece.scale).is_equal_approx(Vector3.ONE, Vector3.ONE * 0.001)
	assert_bool(is_instance_valid(fx) and fx.is_queued_for_deletion()).is_true()


func test_the_swing_dies_down_by_the_decomps_modifier_steps() -> void:
	## 0.5 → 0.2 → 0.08 → 0.032 → 0.0128, under 0.02 after four turns.
	var m: float = FurnitureBirth.BIRTH_MODIFIER
	var turns: int = 0
	while absf(m) >= FurnitureBirth.MODIFIER_END:
		m *= FurnitureBirth.MODIFIER_DECAY
		turns += 1
	assert_int(turns).is_equal(4)


func test_a_lifted_piece_shrinks_a_twelfth_a_tick_and_is_gone() -> void:
	var piece: Node3D = _piece()
	var fx: FurnitureBirth = FurnitureBirth.bye(piece, Vector3.ZERO)
	_ticks(fx, 1)
	assert_float(piece.scale.x).is_equal_approx(11.0 / 12.0, 0.001)
	_ticks(fx, 20)
	assert_bool(piece.is_queued_for_deletion()).is_true()


func test_the_counter_wraps_like_an_s16() -> void:
	assert_int(FurnitureBirth._wrap(32768)).is_equal(-32768)
	assert_int(FurnitureBirth._wrap(-32769)).is_equal(32767)
	assert_int(FurnitureBirth._wrap(100)).is_equal(100)
