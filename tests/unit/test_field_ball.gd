class_name TestFieldBall
extends GdUnitTestSuite

## The town's ball (`ac_ball`): kicks, the villagers' chase cone, tool reach, where a new one
## goes and that it's remembered.


func before_test() -> void:
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()


func _ball() -> FieldBall:
	var ball := FieldBall.new()
	add_child(ball)
	return ball


func test_a_walking_nudge_rolls_it_a_running_kick_lofts_it() -> void:
	var ball := _ball()
	## About walking pace (2 GX a frame): almost flat.
	ball.kick(Vector2(0.0, 1.0), Vector2(0.0, 2.0))
	assert_float(ball.speed).is_greater(0.0)
	assert_float(ball.vy).is_less(ball.speed)
	var lofted := _ball()
	## Running (7.5 GX a frame): it goes up more than along.
	lofted.kick(Vector2(0.0, 1.0), Vector2(0.0, 7.5))
	assert_float(lofted.vy).is_greater(lofted.speed)
	assert_bool(lofted.on_ground).is_false()
	ball.queue_free()
	lofted.queue_free()


func test_kick_is_capped_and_heads_away() -> void:
	var ball := _ball()
	ball.speed = 5.0
	ball.heading = 0.0
	ball.kick(Vector2(1.0, 0.0), Vector2(30.0, 0.0))
	assert_float(ball.speed).is_less_equal(FieldBall.MAX_KICK)
	## Pushed toward +x from the side.
	assert_float(sin(ball.heading)).is_greater(0.0)
	ball.queue_free()


func test_villagers_chase_a_ball_ahead_and_near() -> void:
	var gx: float = FieldBall.gx()
	assert_bool(FieldBall.chase_from(Vector3.ZERO, Vector3(0.0, 0.0, 100.0 * gx))).is_true()
	## Too far, or behind (north of) them.
	assert_bool(FieldBall.chase_from(Vector3.ZERO, Vector3(0.0, 0.0, 210.0 * gx))).is_false()
	assert_bool(FieldBall.chase_from(Vector3.ZERO, Vector3(0.0, 0.0, -50.0 * gx))).is_false()
	assert_bool(FieldBall.chase_from(Vector3.ZERO, Vector3(100.0 * gx, 0.0, 10.0 * gx))).is_false()


func test_tools_reach_it_in_front() -> void:
	var ball := _ball()
	var gx: float = FieldBall.gx()
	ball.global_position = Vector3(0.0, 0.0, 40.0 * gx)
	assert_bool(ball.in_front_of(Vector3.ZERO, 0.0)).is_true()
	assert_bool(ball.in_front_of(Vector3.ZERO, PI)).is_false()
	ball.in_hole = true
	assert_bool(ball.hit_by_shovel(Vector3.ZERO, 0.0)).is_true()
	assert_bool(ball.in_hole).is_false()
	assert_float(ball.vy).is_equal(4.5)
	ball.queue_free()


func test_new_balls_stay_out_of_the_busy_acres() -> void:
	assert_bool(BallUse.block_allowed(TownFieldGenerator.T_FLAT)).is_true()
	assert_bool(BallUse.block_allowed(TownFieldGenerator.T_PLAYER_HOUSE)).is_false()
	assert_bool(BallUse.block_allowed(TownFieldGenerator.T_TRACKS_STATION)).is_false()
	assert_bool(BallUse.block_allowed(TownFieldGenerator.T_TRACKS_SHOP)).is_false()
	assert_bool(BallUse.block_allowed(TownFieldGenerator.T_BEACH)).is_false()


func test_lost_ball_means_a_new_one_next_time() -> void:
	var ball := _ball()
	ball.global_position = Vector3(3.0, 0.0, 4.0)
	remove_child(ball)
	assert_float(float(Game.ball["x"])).is_equal(3.0)
	add_child(ball)
	ball.dead = true
	remove_child(ball)
	assert_bool(Game.ball.is_empty()).is_true()
	ball.free()


func test_ball_is_saved() -> void:
	Game.ball = {"x": 1.0, "y": 0.0, "z": 2.0, "type": 2}
	var saved: Dictionary = Game.to_save()
	Game.reset_session()
	assert_bool(Game.ball.is_empty()).is_true()
	Game.apply_snapshot(saved)
	assert_int(int(Game.ball["type"])).is_equal(2)


func test_the_ball_reaching_the_soccer_asker_finishes_the_contest() -> void:
	var q := VillagerQuests.new()
	q.contests.resize(3)
	for i: int in 3:
		q.contests[i] = {}
	q.contests[1] = {"type": VillagerQuests.Type.CONTEST, "kind": VillagerQuests.CONTEST_SOCCER, "progress": 2, "player": false}
	assert_bool(q.soccer_target(0)).is_false()
	assert_bool(q.soccer_target(1)).is_true()
	assert_bool(q.next_soccer(1, "Kim")).is_true()
	assert_int(int(q.contests[1]["progress"])).is_equal(1)
	assert_bool(q.soccer_target(1)).is_false()
