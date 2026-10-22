extends GdUnitTestSuite

## `ac_snowman` / `ac_psnowman` / `m_snowman` rules.


func before_test() -> void:
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()


func test_size_grows_on_snow_and_wears_off_elsewhere() -> void:
	assert_float(SnowmanRules.roll(100.0, 3.0, true)).is_equal(103.0)
	assert_float(SnowmanRules.roll(100.0, 4.0, false)).is_equal(97.0)
	assert_float(SnowmanRules.roll(6399.0, 3.0, true)).is_equal(SnowmanRules.MOVE_DIST_MAX)
	assert_float(SnowmanRules.roll(1.0, 4.0, false)).is_equal(0.0)
	assert_float(SnowmanRules.radius_gx(0.0)).is_equal(10.0)
	assert_float(SnowmanRules.radius_gx(1.0)).is_equal(30.0)
	assert_float(SnowmanRules.actor_scale(1.0)).is_equal_approx(0.03, 0.0001)


func test_grading_by_head_to_body() -> void:
	## Head 0.85 of the body is perfect; each band widens by 0.1.
	assert_int(SnowmanRules.result(0.0255, 0.03)).is_equal(SnowmanRules.Result.PERFECT)
	assert_int(SnowmanRules.result(0.0225, 0.03)).is_equal(SnowmanRules.Result.GOOD)
	assert_int(SnowmanRules.result(0.0195, 0.03)).is_equal(SnowmanRules.Result.OK)
	assert_int(SnowmanRules.result(0.0294, 0.03)).is_equal(SnowmanRules.Result.GOOD)
	assert_int(SnowmanRules.result(0.012, 0.03)).is_equal(SnowmanRules.Result.BAD)
	assert_bool(SnowmanRules.can_combine(0, 0.3, 1, 0.25)).is_true()
	assert_bool(SnowmanRules.can_combine(0, 0.3, 0, 0.25)).is_false()
	assert_bool(SnowmanRules.can_combine(0, 0.3, 1, 0.2)).is_false()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	assert_int(SnowmanRules.combine_msg(SnowmanRules.Result.BAD, rng)).is_between(2206, 2208)
	assert_int(SnowmanRules.snowman_msg(2, 2, SnowmanRules.Result.GOOD)).is_equal(2209 + 1 + 3)


func test_snowmen_melt_over_three_winter_days() -> void:
	var e: Dictionary = {"head": 0.5, "body": 1.0, "age": 0}
	assert_bool(SnowmanRules.melt(e, 1, true)).is_true()
	assert_float(float(e["body"])).is_equal_approx(0.8, 0.0001)
	assert_bool(SnowmanRules.melt(e, 1, true)).is_true()
	assert_float(float(e["head"])).is_equal_approx(0.32, 0.0001)
	assert_bool(SnowmanRules.melt(e, 1, true)).is_false()
	assert_bool(SnowmanRules.melt({"age": 0}, 1, false)).is_false()
	assert_bool(SnowmanRules.melt({"age": 0}, 3, true)).is_false()
	Game.town.snowmen = [{"head": 0.5, "body": 0.6, "score": 0, "cell": [3, 3], "age": 1}, {}, {}]
	Game.town.melt_snowmen(1)
	## Season depends on the clock; either way the second day keeps it only in winter.
	if Clock.season() == Clock.Season.WINTER:
		assert_int(int((Game.town.snowmen[0] as Dictionary)["age"])).is_equal(2)
	else:
		assert_bool((Game.town.snowmen[0] as Dictionary).is_empty()).is_true()


func test_no_new_balls_until_six_the_next_morning() -> void:
	var day: int = 50 * 1440
	## Built at 14:00: blocked through 5:59 tomorrow.
	var built: int = day + 14 * 60
	assert_bool(SnowmanRules.balls_allowed(built, built + 60)).is_false()
	assert_bool(SnowmanRules.balls_allowed(built, day + 1440 + 5 * 60 + 59)).is_false()
	assert_bool(SnowmanRules.balls_allowed(built, day + 1440 + 6 * 60)).is_true()
	## Built at 3:00: blocked only until 5:59 the same morning.
	built = day + 3 * 60
	assert_bool(SnowmanRules.balls_allowed(built, day + 5 * 60)).is_false()
	assert_bool(SnowmanRules.balls_allowed(built, day + 6 * 60)).is_true()
	assert_bool(SnowmanRules.balls_allowed(-1, day)).is_true()
	Game.town.snowman_built_minute = -1
	Game.town.snowmen = [{}, {"age": 0}, {}]
	assert_bool(SnowmanUse.should_place_balls(day)).is_false()
	Game.town.snowmen = [{}, {"age": 1}, {}]
	assert_bool(SnowmanUse.should_place_balls(day)).is_true()


func test_perfect_gift_and_free_slots() -> void:
	assert_str(String(SnowmanRules.present_id(0))).is_equal("ftr_981")
	assert_str(String(SnowmanRules.present_id(9))).is_equal("ftr_990")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var gift: Dictionary = SnowmanRules.present(rng)
	assert_int(int(gift["mail"])).is_equal(SnowmanRules.PRESENT_MAIL + int(gift["index"]))
	assert_int(SnowmanRules.free_slot([{}, {}, {}])).is_equal(0)
	assert_int(SnowmanRules.free_slot([{"age": 0}, {}, {}])).is_equal(1)
	assert_int(SnowmanRules.free_slot([{"age": 0}, {"age": 0}, {"age": 0}])).is_equal(-1)
	var before: int = Game.post.occupied_count()
	assert_bool(SnowmanUse.send_present(rng)).is_true()
	assert_int(Game.post.occupied_count()).is_equal(before + 1)


func test_snowman_request_counts_in_the_residents_acre() -> void:
	var q := VillagerQuests.new()
	var residents := TownResidents.new()
	var slot: int = 0
	residents.slots[slot] = {"id": &"bob", "home": Vector2i(40, 20), "moved_in": false}
	q.contests[slot] = {"type": VillagerQuests.Type.CONTEST, "kind": VillagerQuests.CONTEST_SNOWMAN, "progress": 1, "player": false, "owner": &"bob"}
	assert_bool(q.note_snowman(Vector2i(1, 1), residents, true)).is_false()
	assert_bool(q.note_snowman(Vector2i(2, 1), residents, true)).is_true()
	assert_bool(bool(q.contests[slot]["player"])).is_true()
	q.note_snowman(Vector2i(2, 1), residents, false)
	assert_bool(bool(q.contests[slot]["player"])).is_false()


## Rolls a ball from the same spot for 0.5 s in steps of `1 / hz`; returns [speed, z, move_dist].
func _roll_for_half_a_second(hz: int) -> Array[float]:
	var ball: Snowball = load("res://scenes/world/snowball.tscn").instantiate() as Snowball
	ball.move_dist = 2000.0
	add_child(ball)
	ball.global_position = Vector3.ZERO
	ball.vel = Vector2(0.0, 4.0 * Snowball.FRAME)
	for _i: int in hz / 2:
		ball.advance(1.0 / float(hz))
	var out: Array[float] = [ball.speed(), ball.global_position.z, ball.move_dist]
	ball.discard = true
	ball.free()
	return out


func test_a_rolled_ball_slows_and_grows_the_same_at_any_frame_rate() -> void:
	## One at a time over the same ground, so whatever field is loaded can't tell them apart.
	var a := _roll_for_half_a_second(60)
	var b := _roll_for_half_a_second(16)
	## Braking at 0.1 − 0.05·n GX a frame per tick (n changes a little within a step, hence
	## the slack).
	assert_float(a[0]).is_less(4.0 * Snowball.FRAME)
	assert_float(b[0]).is_equal_approx(a[0], 0.005)
	assert_float(b[1]).is_equal_approx(a[1], 0.005)
	assert_float(a[2]).is_not_equal(2000.0)
	assert_float(b[2]).is_equal_approx(a[2], 0.05)


func test_a_snowman_push_fades_about_as_add_calc0_did() -> void:
	## A tick of `add_calc0(100, 1 − √0.7, 10)` takes off 10 (the cap); 20 eases by 16%.
	assert_float(100.0 - Snowman.ease_off(100.0, 1.0 / 60.0)).is_equal_approx(10.0, 0.0001)
	assert_float(Snowman.ease_off(20.0, 1.0 / 60.0)).is_equal_approx(20.0 * sqrt(0.7), 0.001)
