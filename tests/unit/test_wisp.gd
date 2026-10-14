extends GdUnitTestSuite

## The Wisp's night (`ac_ev_ghost`, `ac_ins_hitodama`).

var _saved_clear: bool = false


func before_test() -> void:
	_saved_clear = Game.clear_grass


func after_test() -> void:
	Game.clear_grass = _saved_clear


func _rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


func test_five_spirits_in_five_acres() -> void:
	var acres: Array = WispEvent.roll_acres(_rng(3))
	assert_int(acres.size()).is_equal(WispEvent.SPIRITS)
	for a: Array in acres:
		assert_int(int(a[0])).is_between(1, 5)
		assert_int(int(a[1])).is_between(2, 5)
		assert_int(acres.count(a)).is_equal(1)


func test_catch_reports_count_up() -> void:
	assert_int(WispEvent.catch_msg(0)).is_equal(0x2F03)
	assert_int(WispEvent.catch_msg(4)).is_equal(0x2F07)
	assert_int(WispEvent.weeds_msg(10)).is_equal(0x2EF1)
	assert_int(WispEvent.weeds_msg(500)).is_equal(0x2EF4)
	assert_int(WispEvent.weeds_msg(2000)).is_equal(0x2EF5)


func test_he_needs_weeds_until_found_and_goes_once_paid() -> void:
	assert_bool(WispEvent.shows_up({"found": false}, 7)).is_false()
	assert_bool(WispEvent.shows_up({"found": false}, 8)).is_true()
	assert_bool(WispEvent.shows_up({"found": true}, 0)).is_true()
	assert_bool(WispEvent.shows_up({"found": true, "returned": true}, 50)).is_false()


func test_his_night_comes_two_to_four_days_out_and_lasts_a_week() -> void:
	var cal := EventCalendar.new()
	var now := {"year": 2026, "month": 10, "day": 4, "hour": 1}
	cal._init_ghost(now)
	var today: int = EventDates.ordinal(2026, 10, 4)
	assert_int(cal.ghost_day).is_between(today + 2, today + 4)
	assert_bool(cal.ghost_tonight).is_false()
	## Once the night has come he keeps coming for a week.
	cal.ghost_day = today - 3
	cal._init_ghost(now)
	assert_bool(cal.ghost_tonight).is_true()
	cal.ghost_day = today - 8
	cal._init_ghost(now)
	assert_int(cal.ghost_day).is_greater(today)
	assert_bool(cal.ghost_tonight).is_false()


func _talk_to(talk: WispTalk) -> DialogueRunner:
	var runner := DialogueRunner.new()
	runner.talk_manager = talk
	runner.action_requested.connect(func(_a: Dictionary) -> void: pass)
	talk.context = DialogueContext.new()
	talk.prepare()
	runner.start(DialogueCatalog.conversation(StringName("msg_%d" % talk.start_msg())), talk.context)
	return runner


func _advance_until(runner: DialogueRunner, cond: Callable) -> void:
	var guard := 0
	while not runner.done and not runner.waiting_choice and not runner.waiting_action and guard < 40 and not bool(cond.call()):
		guard += 1
		runner.advance()


func test_five_spirits_buy_a_wish() -> void:
	if DialogueCatalog.conversation(&"msg_12016") == null:
		return
	var inv := Inventory.new()
	var spirit: ItemData = BugCatalog.get_by_type(WispEvent.TYPE_SPIRIT)
	assert_object(spirit).is_not_null()
	assert_int(inv.add(spirit, 5)).is_equal(0)
	assert_int(WispEvent.spirit_count(inv)).is_equal(5)
	var state: Dictionary = {"found": true, "active": true, "returned": false, "name_no": 0, "acres": []}
	var talk := WispTalk.new(WispTalk.Kind.NORMAL, state, inv, _rng(1))
	var runner := _talk_to(talk)
	assert_int(talk.current_msg).is_equal(WispTalk.MSG_ALL)
	## "Please, show them to me!": the spirits change hands.
	_advance_until(runner, func() -> bool: return false)
	assert_bool(runner.waiting_action).is_true()
	assert_int(WispEvent.spirit_count(inv)).is_equal(0)
	runner.resolve_action({})
	_advance_until(runner, func() -> bool: return false)
	assert_bool(runner.waiting_choice).is_true()
	## "Give me stuff!"
	runner.choose(2)
	assert_bool(bool(state["returned"])).is_true()
	assert_str(String(talk.item)).is_not_empty()
	_advance_until(runner, func() -> bool: return false)
	assert_bool(runner.waiting_action).is_true()
	runner.resolve_action({})
	assert_int(inv.count_of(talk.item)).is_equal(1)


func test_the_weeds_wish_clears_them_with_the_next_growth() -> void:
	if DialogueCatalog.conversation(&"msg_12016") == null:
		return
	var inv := Inventory.new()
	inv.add(BugCatalog.get_by_type(WispEvent.TYPE_SPIRIT), 5)
	var state: Dictionary = {"found": true, "active": true, "returned": false, "name_no": 0, "acres": []}
	var talk := WispTalk.new(WispTalk.Kind.NORMAL, state, inv, _rng(2))
	var runner := _talk_to(talk)
	_advance_until(runner, func() -> bool: return false)
	runner.resolve_action({})
	_advance_until(runner, func() -> bool: return false)
	Game.clear_grass = false
	runner.choose(0)
	assert_int(talk.current_msg).is_between(0x2EF1, 0x2EF5)
	var guard := 0
	while not runner.done and guard < 40:
		guard += 1
		runner.advance()
	assert_bool(Game.clear_grass).is_true()
