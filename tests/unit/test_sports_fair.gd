extends GdUnitTestSuite

## Sports Fair games (`ac_tunahiki_*`).


func before_test() -> void:
	TugOfWar.reset()


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
	TugOfWar.next_speed = 20.0
	for i: int in TugOfWar.HEAVE_FRAME - 1:
		TugOfWar.step(rng)
	assert_float(TugOfWar.rope_base).is_equal(0.0)
	TugOfWar.step(rng)
	assert_bool(TugOfWar.shake).is_true()
	for i: int in 2000:
		TugOfWar.step(rng)
		assert_float(absf(TugOfWar.rope_base)).is_less_equal(TugOfWar.LIMIT_GX)


func test_a_side_being_dragged_hangs_on_and_a_winning_side_throws_its_weight() -> void:
	TugOfWar.rope_base = -8.0
	TugOfWar.next_speed = 5.0
	assert_str(TugOfWar.clip_for(1)).is_equal(TugOfWar.CLIP_YURI)
	assert_str(TugOfWar.clip_for(-1)).is_equal(TugOfWar.CLIP_AIKO)
	TugOfWar.next_speed = -5.0
	assert_str(TugOfWar.clip_for(-1)).is_equal(TugOfWar.CLIP_FURI)
	TugOfWar.rope_base = 2.0
	assert_str(TugOfWar.clip_for(1)).is_equal(TugOfWar.CLIP_AIKO)


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
	FootRace.reset()
	assert_bool(FootRace.racing(1)).is_true()
	assert_bool(FootRace.racing(3)).is_false()
	for i: int in FootRace.WARMUP_FRAMES:
		FootRace.step()
	assert_int(FootRace.phase).is_equal(FootRace.Phase.READY)
	for i: int in FootRace.READY_FRAMES:
		FootRace.step()
	assert_int(FootRace.phase).is_equal(FootRace.Phase.RACE)
	FootRace.cross(1)
	FootRace.cross(0)
	assert_int(FootRace.finish[1]).is_equal(1)
	assert_int(FootRace.finish[0]).is_equal(2)
	FootRace.step()
	assert_int(FootRace.phase).is_equal(FootRace.Phase.GOAL)
	for i: int in FootRace.GOAL_FRAMES:
		FootRace.step()
	assert_int(FootRace.phase).is_equal(FootRace.Phase.WARMUP)
	assert_bool(FootRace.racing(3)).is_true()
	assert_bool(FootRace.racing(1)).is_false()


func test_legs_go_round_the_shrine_and_four_laps_finish() -> void:
	FootRace.reset()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var angle: float = 0.0
	var legs: int = 0
	while not FootRace.done_laps(1) and legs < 200:
		var leg: Array = FootRace.next_leg(1, angle, rng)
		var r: float = (leg[0] as Vector2).length()
		assert_float(r).is_between(125.0, 145.0)
		assert_float(float(leg[1]) - angle).is_between(FootRace.LEG_ANGLE, FootRace.LEG_ANGLE * 2.0)
		angle = float(leg[1])
		legs += 1
	assert_bool(FootRace.done_laps(1)).is_true()
	assert_int(legs).is_between(30, 70)
