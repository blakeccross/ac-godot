extends GdUnitTestSuite

## Sports Fair games (`ac_tunahiki_*`).


var _tug: TugOfWar


func before_test() -> void:
	## Out of the tree, so only the test steps it.
	_tug = auto_free(TugOfWar.new())


func test_teams_face_each_other_from_their_units() -> void:
	assert_int(TugOfWar.dir_of(1)).is_equal(1)
	assert_int(TugOfWar.dir_of(2)).is_equal(1)
	assert_int(TugOfWar.dir_of(3)).is_equal(-1)
	assert_int(TugOfWar.dir_of(4)).is_equal(-1)
	assert_object(TugOfWar.puller_offset(1)).is_equal(Vector2(85.0, 5.0))
	assert_object(TugOfWar.puller_offset(3)).is_equal(Vector2(-95.0, -5.0))


func test_the_rope_moves_only_while_they_heave_and_stays_within_ten() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_tug.next_speed = 20.0
	_tug.advance(TugOfWar.HEAVE_AT - 0.01, rng)
	assert_float(_tug.rope_base).is_equal(0.0)
	_tug.advance(0.02, rng)
	assert_bool(_tug.shake).is_true()
	## 20 a frame for 0.01 s: 0.15 GX.
	assert_float(_tug.rope_base).is_equal_approx(20.0 * TugOfWar.PULL_RATE * 0.01, 0.0001)
	for i: int in 2000:
		_tug.advance(1.0 / 30.0, rng)
		assert_float(absf(_tug.rope_base)).is_less_equal(TugOfWar.LIMIT_GX)


func test_one_long_step_heaves_eases_and_rolls_the_next_pull() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_tug.next_speed = 20.0
	## A 0.9 s hitch passes both marks: the rope moves for exactly the 0.6 s heave.
	_tug.advance(0.9, rng)
	assert_bool(_tug.shake).is_false()
	assert_float(_tug.rope_base).is_equal_approx(20.0 * TugOfWar.PULL_RATE * 0.6, 0.0001)
	assert_float(_tug.time).is_equal_approx(0.9, 0.0001)


func test_a_side_being_dragged_hangs_on_and_a_winning_side_throws_its_weight() -> void:
	_tug.rope_base = -8.0
	_tug.next_speed = 5.0
	assert_str(_tug.clip_for(1)).is_equal(TugOfWar.CLIP_YURI)
	assert_str(_tug.clip_for(-1)).is_equal(TugOfWar.CLIP_AIKO)
	_tug.next_speed = -5.0
	assert_str(_tug.clip_for(-1)).is_equal(TugOfWar.CLIP_FURI)
	_tug.rope_base = 2.0
	assert_str(_tug.clip_for(1)).is_equal(TugOfWar.CLIP_AIKO)


func test_ball_toss_teams_and_spots_round_their_basket() -> void:
	assert_int(BallToss.team_of(1)).is_equal(0)
	assert_int(BallToss.team_of(2)).is_equal(0)
	assert_int(BallToss.team_of(3)).is_equal(1)
	assert_int(BallToss.team_of(4)).is_equal(1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i: int in 50:
		var spot: Vector2 = BallToss.next_spot(Vector2(100.0, 100.0), Vector2(180.0, 100.0), rng)
		var d: float = spot.distance_to(Vector2(100.0, 100.0))
		assert_float(d).is_between(70.0, 90.0)
	var rise: float = BallToss.launch_rise(rng)
	assert_float(rise).is_between(deg_to_rad(67.5), deg_to_rad(84.0))
	assert_float(BallToss.launch_speed(rng)).is_between(4.9, 6.4)


func test_the_foot_race_warms_up_lines_up_races_and_swaps_pairs() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var race := FootRace.join(host)
	assert_that(FootRace.join(host)).is_same(race)
	var timer := race.get_node("PhaseTimer") as Timer
	## `aTKC_*`: 240, 115 and 600 frames at 30 fps.
	assert_int(race.phase).is_equal(FootRace.Phase.WARMUP)
	assert_float(timer.wait_time).is_equal_approx(240.0 * DecompTime.FRAME_SEC, 0.001)
	assert_bool(race.racing(1)).is_true()
	assert_bool(race.racing(3)).is_false()
	timer.timeout.emit()
	assert_int(race.phase).is_equal(FootRace.Phase.READY)
	assert_float(timer.wait_time).is_equal_approx(115.0 * DecompTime.FRAME_SEC, 0.001)
	timer.timeout.emit()
	assert_int(race.phase).is_equal(FootRace.Phase.RACE)
	race.cross(1)
	assert_int(race.phase).is_equal(FootRace.Phase.RACE)
	race.cross(0)
	assert_int(race.finish[1]).is_equal(1)
	assert_int(race.finish[0]).is_equal(2)
	assert_int(race.phase).is_equal(FootRace.Phase.GOAL)
	assert_float(timer.wait_time).is_equal_approx(600.0 * DecompTime.FRAME_SEC, 0.001)
	timer.timeout.emit()
	assert_int(race.phase).is_equal(FootRace.Phase.WARMUP)
	assert_bool(race.racing(3)).is_true()
	assert_bool(race.racing(1)).is_false()
	## The last runner out frees it.
	race.leave()
	assert_bool(race.is_queued_for_deletion()).is_false()
	race.leave()
	assert_bool(race.is_queued_for_deletion()).is_true()


func test_legs_go_round_the_shrine_and_four_laps_finish() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var race := FootRace.join(host)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var angle: float = 0.0
	var legs: int = 0
	while not race.done_laps(1) and legs < 200:
		var leg: Array = race.next_leg(1, angle, rng)
		var r: float = (leg[0] as Vector2).length()
		assert_float(r).is_between(125.0, 145.0)
		assert_float(float(leg[1]) - angle).is_between(FootRace.LEG_ANGLE, FootRace.LEG_ANGLE * 2.0)
		angle = float(leg[1])
		legs += 1
	assert_bool(race.done_laps(1)).is_true()
	assert_int(legs).is_between(30, 70)
