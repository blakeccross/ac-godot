extends GdUnitTestSuite

## Tortimer's second bridge (`mEv_EVENT_SONCHO_BRIDGE_MAKE`, `ac_ev_soncho_talk`,
## `bridge_make_in`, `ac_bridge_a`).


func before_test() -> void:
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()


## Three river acres with spots: (2, 1), (2, 2) and (3, 3) in FG blocks.
func _layout() -> WorldData:
	var data := WorldData.new()
	data.bridge_spots = [Vector3i(16 + 5, 5, 0), Vector3i(16 + 6, 16 + 7, 1), Vector3i(32 + 4, 32 + 9, 0), Vector3i(32 + 6, 32 + 9, 1)]
	return data


func test_he_comes_once_the_town_is_full_and_not_on_sundays_or_gullivers_day() -> void:
	assert_bool(SecondBridge.tortimer_due(6, true, true, false)).is_true()
	assert_bool(SecondBridge.tortimer_due(3, false, true, false)).is_true()
	assert_bool(SecondBridge.tortimer_due(3, true, true, false)).is_false()
	assert_bool(SecondBridge.tortimer_due(0, false, true, false)).is_false()
	assert_bool(SecondBridge.tortimer_due(3, false, false, false)).is_false()
	assert_bool(SecondBridge.tortimer_due(3, false, true, true)).is_false()
	SecondBridge.state()["exists"] = true
	assert_bool(SecondBridge.tortimer_due(6, false, true, false)).is_false()


func test_each_day_moves_him_upstream_then_back_to_the_mouth() -> void:
	var data := _layout()
	var blocks: Array[Vector2i] = SecondBridge.blocks(data)
	assert_int(blocks.size()).is_equal(3)
	SecondBridge.note_day(100)
	assert_object(SecondBridge.tortimer_block(data)).is_equal(blocks[1])
	SecondBridge.note_day(100)
	assert_object(SecondBridge.tortimer_block(data)).is_equal(blocks[1])
	SecondBridge.note_day(101)
	assert_object(SecondBridge.tortimer_block(data)).is_equal(blocks[0])
	## At the top his lines say he'll head downstream next.
	assert_int(SecondBridge.elsewhere_msg()).is_equal(SecondBridge.MSG_ELSEWHERE_TOP)
	SecondBridge.note_day(102)
	assert_object(SecondBridge.tortimer_block(data)).is_equal(blocks[2])
	assert_int(SecondBridge.elsewhere_msg()).is_equal(SecondBridge.MSG_ELSEWHERE + 1)


func test_the_bridge_stands_from_six_on_the_next_day() -> void:
	SecondBridge.order(Vector2i(3, 3), 200)
	assert_bool(SecondBridge.build_if_due(200, 20)).is_false()
	assert_bool(SecondBridge.build_if_due(201, 5)).is_false()
	assert_bool(SecondBridge.build_if_due(201, 6)).is_true()
	assert_bool(bool(SecondBridge.state()["exists"])).is_true()
	## A0 before A1 in the acre.
	assert_object(SecondBridge.spot_in(_layout(), Vector2i(3, 3))).is_equal(Vector3i(32 + 4, 32 + 9, 0))


func test_it_is_saved() -> void:
	SecondBridge.order(Vector2i(2, 1), 300)
	var saved: Dictionary = Game.to_save()
	Game.reset_session()
	assert_bool(Game.bridge.is_empty()).is_true()
	Game.apply_snapshot(saved)
	assert_bool(bool(SecondBridge.state()["pending"])).is_true()
	assert_int(int(SecondBridge.state()["bx"])).is_equal(2)


func _run_to_choice(runner: DialogueRunner) -> void:
	var guard := 0
	while not runner.waiting_choice and not runner.done and guard < 80:
		guard += 1
		runner.advance()


func test_here_is_good_orders_the_bridge_for_tomorrow() -> void:
	if DialogueCatalog.conversation(&"msg_12087") == null:
		return
	var rng := RandomNumberGenerator.new()
	var talk := TortimerBridgeTalk.new(Vector2i(2, 2), true, EventDates.ordinal(2001, 7, 15), 12, rng)
	talk.context = DialogueContext.new()
	var runner := DialogueRunner.new()
	runner.talk_manager = talk
	talk.prepare()
	runner.start(DialogueCatalog.conversation(StringName("msg_%d" % talk.start_msg())), talk.context)
	_run_to_choice(runner)
	assert_int(talk.current_msg).is_equal(SecondBridge.MSG_ASK)
	runner.choose(1)
	assert_bool(bool(SecondBridge.state()["pending"])).is_true()
	assert_int(int(SecondBridge.state()["build"])).is_equal(EventDates.ordinal(2001, 7, 16))
	assert_str(talk.context.substitute("{free0}")).is_equal("16")


func test_sleeping_on_it_looks_elsewhere() -> void:
	if DialogueCatalog.conversation(&"msg_12087") == null:
		return
	var talk := TortimerBridgeTalk.new(Vector2i(2, 2), true, 1000, 12, RandomNumberGenerator.new())
	talk.context = DialogueContext.new()
	var runner := DialogueRunner.new()
	runner.talk_manager = talk
	runner.start(DialogueCatalog.conversation(StringName("msg_%d" % talk.start_msg())), talk.context)
	_run_to_choice(runner)
	runner.choose(0)
	assert_int(talk.current_msg).is_equal(SecondBridge.MSG_ELSEWHERE)
	assert_bool(bool(SecondBridge.state()["pending"])).is_false()


func test_the_deck_carries_you_over_the_river_at_bank_height() -> void:
	var data: WorldData = WorldGenerator.generate(12345)
	if data.bridge_spots.is_empty():
		return
	FieldCollision.clear_caches()
	var spot: Vector3i = data.bridge_spots[0]
	var centre := Vector2i(spot.x, spot.y)
	var bed: float = FieldCollision.height_at(data, centre)
	SecondBridge.apply_collision(data, null, spot)
	assert_float(FieldCollision.height_at(data, centre)).is_greater(bed)
	assert_bool(FieldCatalog.is_wood_bridge_attr(FieldCollision.unit_attr_at_cell(data, centre))).is_true()
	assert_bool(FieldCollision._forbids_enter(data, centre)).is_false()
	FieldCollision.clear_caches()
