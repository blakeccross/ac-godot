class_name TestShrineQueue
extends GdUnitTestSuite

## The New Year's queue at the wishing well (`ShrineQueue`, `ac_hatumode_npc0`).


func before_test() -> void:
	ShrineQueue.reset()


func after_test() -> void:
	ShrineQueue.reset()


func test_each_column_goes_out_round_the_back_and_up_the_front() -> void:
	## Left: offering → (−80, 55) → (−80, 180) → (−20, 180) → (−20, 140) → offering.
	var left: Array[Vector2] = []
	for leg: int in 5:
		left.append(ShrineQueue.point_of(0, leg))
	assert_array(left).contains_exactly([
		Vector2(0, 55), Vector2(-80, 55), Vector2(-80, 180), Vector2(-20, 180), Vector2(-20, 140),
	])
	assert_vector(ShrineQueue.point_of(1, ShrineQueue.LEG_FRONT)).is_equal(Vector2(20, 140))
	assert_int(ShrineQueue.next_leg(4)).is_equal(0)


func test_villagers_start_where_the_decomp_puts_them() -> void:
	## `aHN0_ready2` roots 5 / 4 / 9 / 3.
	assert_int(ShrineQueue.start_leg(0)).is_equal(ShrineQueue.LEG_OFFER)
	assert_int(ShrineQueue.start_leg(1)).is_equal(ShrineQueue.LEG_FRONT)
	assert_int(ShrineQueue.start_leg(2)).is_equal(ShrineQueue.LEG_FRONT)
	assert_int(ShrineQueue.start_leg(3)).is_equal(ShrineQueue.LEG_BACK)
	assert_int(ShrineQueue.column_of(0)).is_equal(ShrineQueue.column_of(2))
	assert_int(ShrineQueue.column_of(1)).is_equal(ShrineQueue.column_of(3))
	assert_int(ShrineQueue.column_of(0)).is_not_equal(ShrineQueue.column_of(1))


func test_the_columns_take_turns_at_the_well() -> void:
	ShrineQueue.step_up(0)
	ShrineQueue.turn = ShrineQueue.column_of(0)
	ShrineQueue.take_front(1)
	ShrineQueue.take_front(2)
	assert_bool(ShrineQueue.may_step_up(1)).is_false()  ## the well is taken
	ShrineQueue.step_down(0)
	assert_int(ShrineQueue.turn).is_equal(ShrineQueue.column_of(1))
	assert_bool(ShrineQueue.may_step_up(2)).is_false()  ## not its column's turn
	assert_bool(ShrineQueue.may_step_up(1)).is_true()
	ShrineQueue.step_up(1)
	assert_int(ShrineQueue.front_by[ShrineQueue.column_of(1)]).is_equal(-1)


func test_one_villager_at_a_time_at_each_front() -> void:
	ShrineQueue.take_front(1)
	assert_bool(ShrineQueue.can_take_front(3)).is_false()
	assert_bool(ShrineQueue.can_take_front(1)).is_true()
	assert_bool(ShrineQueue.can_take_front(2)).is_true()


func test_the_player_goes_in_place_of_whoever_let_them_in() -> void:
	ShrineQueue.take_front(1)
	assert_bool(ShrineQueue.can_offer(1)).is_true()
	assert_bool(ShrineQueue.can_offer(3)).is_false()  ## not at the front
	ShrineQueue.queue_player(1)
	assert_bool(ShrineQueue.can_offer(1)).is_false()  ## asked only once
	ShrineQueue.turn = ShrineQueue.column_of(1)
	assert_bool(ShrineQueue.may_step_up(1)).is_false()
	assert_bool(ShrineQueue.player_may_step_up()).is_true()
	ShrineQueue.offering_by = ShrineQueue.PLAYER
	assert_bool(ShrineQueue.player_may_step_up()).is_false()
	ShrineQueue.step_down(ShrineQueue.PLAYER)
	assert_int(ShrineQueue.offering_by).is_equal(-1)
	assert_int(ShrineQueue.turn).is_equal(1 - ShrineQueue.column_of(1))


func test_queue_talk_counts_places_from_the_one_at_the_well() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	ShrineQueue.offering_by = 0
	assert_int(ShrineQueue.place_in_line(1, 0)).is_equal(1)
	assert_int(ShrineQueue.place_in_line(3, 0)).is_equal(3)
	assert_int(ShrineQueue.place_in_line(0, 0)).is_equal(4)
	var n: int = ShrineQueue.talk_msg(0, 2, rng)
	assert_int(n).is_between(7679 + 6, 7679 + 8)
	assert_int(ShrineQueue.offer_msg(5)).is_equal(7751)
	assert_int(ShrineQueue.thanks_msg(1, rng)).is_between(7697 + 15, 7697 + 17)


func test_queue_points_follow_the_wells_facing() -> void:
	var well: Node3D = auto_free(Node3D.new())
	add_child(well)
	well.rotation.y = PI * 0.5
	var at: Vector3 = ShrineQueue.to_world(well, Vector2(0.0, 100.0))
	assert_float(at.x).is_equal_approx(100.0 * FieldCatalog.GX_TO_METERS, 0.001)
	assert_float(at.z).is_equal_approx(0.0, 0.001)
	assert_float(angle_difference(ShrineQueue.facing_well(well), -PI * 0.5)).is_equal_approx(0.0, 0.001)
