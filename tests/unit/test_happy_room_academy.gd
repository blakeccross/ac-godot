extends GdUnitTestSuite

## `m_mark_room.c` / `m_mark_room_ovl.c`.

const HRA := preload("res://scripts/systems/happy_room_academy.gd")


func _first(pred: Callable) -> int:
	var ftr: Array = HRA.data()["ftr"]
	for i: int in ftr.size():
		if pred.call(ftr[i]):
			return i
	return -1


func _piece(idx: int, unit: Vector2i, facing: int = 0) -> HRA.Piece:
	var p := HRA.Piece.new()
	p.index = idx
	p.unit = unit
	p.facing = facing
	p.layer = 0
	p.units = [unit]
	return p


func test_origin_points_luck_and_facing_the_wall() -> void:
	if not HRA.available():
		return
	var d: Dictionary = HRA.data()
	## A plain piece: its origin's points, plus the default wall and floor.
	var plain: int = _first(func(r: Array) -> bool: return int(r[2]) == 0 and int(r[3]) == 0 and int(r[0]) == HRA.SERIES_OTHER)
	var lucky: int = _first(func(r: Array) -> bool: return int(r[3]) != 0)
	var faced: int = _first(func(r: Array) -> bool: return int(r[2]) != 0 and int(r[3]) == 0 and int(r[0]) == HRA.SERIES_OTHER)
	var birth: Array = d["birth_points"]
	var room_base: int = int(birth[int(d["wall_from"][0])]) + int(birth[int(d["floor_from"][0])])
	var r0: Dictionary = HRA.score_floor([_piece(plain, Vector2i(2, 2))], 0, 0, 0, HRA.FULL)
	assert_int(int(r0["points"])).is_equal(int(birth[int(d["ftr"][plain][4])]) + room_base)
	if lucky >= 0:
		var r1: Dictionary = HRA.score_floor([_piece(lucky, Vector2i(2, 2))], 0, 0, 0, HRA.EVAL_LUCKY)
		assert_int(int(r1["points"])).is_equal(777)
	if faced >= 0:
		## Facing north against the north wall (unit row 1).
		var bad: Dictionary = HRA.score_floor([_piece(faced, Vector2i(2, 1), 2)], 0, 0, 0, HRA.EVAL_DIRECTION)
		assert_int(int(bad["bits"]) & HRA.BIT_BAD_DIRECTION).is_not_equal(0)
		var ok: Dictionary = HRA.score_floor([_piece(faced, Vector2i(2, 1), 0)], 0, 0, 0, HRA.EVAL_DIRECTION)
		assert_int(int(ok["bits"]) & HRA.BIT_BAD_DIRECTION).is_equal(0)


func test_pieces_outside_the_room_do_not_count() -> void:
	if not HRA.available():
		return
	var plain: int = _first(func(r: Array) -> bool: return int(r[0]) == HRA.SERIES_OTHER)
	## Small house: units 1–4 only.
	var r: Dictionary = HRA.score_floor([_piece(plain, Vector2i(5, 2))], 0, 0, 0, HRA.EVAL_LUCKY | HRA.EVAL_DIRECTION)
	assert_int(int(r["points"])).is_equal(0)


func test_letters_reward_first_then_grade() -> void:
	if not HRA.available():
		return
	var hra := HRA.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_int(int(hra.decide_letter(75000, 0, 1, rng)[0])).is_equal(HRA.REWARD0_LETTER)
	hra.reward0 = true
	assert_int(int(hra.decide_letter(75000, 0, 1, rng)[0])).is_equal(0x47)
	assert_int(int(hra.decide_letter(0, 0, 1, rng)[0])).is_equal(0x42)
	assert_int(int(hra.decide_letter(5000, 0, 0, rng)[0])).is_equal(0x43)
	assert_int(int(hra.decide_letter(5000, 0, 3, rng)[0])).is_equal(0x220)


func test_welcome_then_score_only_on_a_later_day_after_a_change() -> void:
	if not HRA.available():
		return
	var hra := HRA.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var house := House.new()
	var room := Room.new()
	var day1 := Vector3i(2001, 7, 15)
	var first: MailData = hra.mark(house, room, null, day1, false, "Pat", rng)
	assert_object(first).is_not_null()
	assert_bool(hra.member).is_true()
	## Same day: nothing more.
	assert_object(hra.mark(house, room, null, day1, false, "Pat", rng)).is_null()
	## A change dated day 2 waits for day 3.
	hra.report_change(2001, 7, 16)
	assert_object(hra.mark(house, room, null, Vector3i(2001, 7, 16), false, "Pat", rng)).is_null()
	var graded: MailData = hra.mark(house, room, null, Vector3i(2001, 7, 17), false, "Pat", rng)
	assert_object(graded).is_not_null()
	assert_bool(hra.updated).is_false()
	assert_int(graded.paper_type).is_equal(HRA.PAPER)


func test_first_job_skips_the_academy() -> void:
	var hra := HRA.new()
	var rng := RandomNumberGenerator.new()
	assert_object(hra.mark(House.new(), Room.new(), null, Vector3i(2001, 7, 15), true, "Pat", rng)).is_null()
	assert_bool(hra.member).is_false()
