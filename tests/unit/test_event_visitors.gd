class_name TestEventVisitors
extends GdUnitTestSuite

## Event visitors' talk scripts (`BankTalk`) run over the disc messages, and the event
## manager's shared placement rules.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	DialogueCatalog.reset()


func after_test() -> void:
	DialogueCatalog.reset()
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


## Runs `runner` until it wants a choice or ends.
func _run(runner: DialogueRunner) -> void:
	var guard := 0
	while not runner.waiting_choice and not runner.done and guard < 80:
		guard += 1
		runner.advance()


func _start(talk: BankTalk, msg_no: int) -> DialogueRunner:
	var runner := DialogueRunner.new()
	runner.talk_manager = talk
	talk.context = DialogueContext.new()
	runner.start(DialogueCatalog.conversation(StringName("msg_%d" % msg_no)), talk.context)
	return runner


func test_joan_greets_once_a_week() -> void:
	Clock.apply_snapshot({"year": 2002, "month": 3, "day": 3, "hour": 8, "minute": 0})
	var area: Dictionary = {}
	var first := JoanTalk.new(100)
	first.setup(area)
	assert_int(first.start_msg()).is_equal(JoanTalk.MSG_FIRST)
	var again := JoanTalk.new(100)
	again.setup(area)
	assert_int(again.start_msg()).is_equal(JoanTalk.MSG_AGAIN)
	## Next Sunday she introduces herself again.
	Clock.apply_snapshot({"year": 2002, "month": 3, "day": 10, "hour": 8, "minute": 0})
	var next_week := JoanTalk.new(100)
	next_week.setup(area)
	assert_int(next_week.start_msg()).is_equal(JoanTalk.MSG_FIRST)


func test_joan_sells_a_bunch_for_sundays_price() -> void:
	if DialogueCatalog.conversation(&"msg_1802") == null:
		return
	var inv := Inventory.new()
	inv.set_wallet(5000)
	var talk := JoanTalk.new(95, inv)
	var runner := _start(talk, JoanTalk.MSG_PRICE)
	_run(runner)
	assert_str(talk.context.frees[1]).is_equal("950")
	assert_int(runner.choices.size()).is_equal(4)
	runner.choose(1)
	_run(runner)
	## 50 turnips: 4750 Bells, then "Much obliged! … buy more?".
	assert_int(inv.wallet).is_equal(250)
	assert_int(inv.count_of(&"turnips_50")).is_equal(1)
	assert_int(talk.current_msg).is_equal(JoanTalk.MSG_MORE)
	runner.choose(2)
	_run(runner)
	## 9500 is more than is left: "all out of money".
	assert_int(talk.current_msg).is_equal(0x0717)
	assert_int(inv.count_of(&"turnips_100")).is_equal(0)
	assert_bool(runner.done).is_true()


func test_joan_notices_full_pockets() -> void:
	if DialogueCatalog.conversation(&"msg_1802") == null:
		return
	var inv := Inventory.new()
	inv.set_wallet(99999)
	var apple: ItemData = ItemCatalog.get_item(&"apple")
	while inv.has_space(1):
		inv.add(apple, 1)
	var talk := JoanTalk.new(100, inv)
	var runner := _start(talk, JoanTalk.MSG_PRICE)
	_run(runner)
	runner.choose(0)
	_run(runner)
	assert_int(talk.current_msg).is_equal(0x070F)
	assert_int(inv.wallet).is_equal(99999)


func test_block_unit_cells() -> void:
	assert_that(EventManager.block_unit_to_cell(Vector2i(1, 1), Vector2i(0, 0))).is_equal(Vector2i(0, 0))
	assert_that(EventManager.block_unit_to_cell(Vector2i(3, 2), Vector2i(7, 7))).is_equal(Vector2i(39, 23))
	assert_that(EventManager.cell_to_block(Vector2i(39, 23))).is_equal(Vector2i(3, 2))


func test_event_map_has_the_festival_layouts() -> void:
	var fireworks: Dictionary = EventManager.event_map(&"fireworks_show")
	assert_str(str(fireworks.get("block_kind"))).is_equal("pool")
	assert_int((fireworks.get("maps", []) as Array).size()).is_equal(7)
	var new_year: Dictionary = EventManager.event_map(&"new_years_day")
	assert_int(int(new_year.get("joint_npcs"))).is_equal(4)
