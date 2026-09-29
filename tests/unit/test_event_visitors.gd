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


func test_kk_intro_then_hello_then_again() -> void:
	var show: Dictionary = {}
	var player: Dictionary = {}
	var t := KkTalk.new(show, player)
	t.in_front = false
	assert_int(t.start_msg()).is_equal(KkTalk.MSG_FRONT_ROW)
	t.in_front = true
	assert_int(t.start_msg()).is_equal(KkTalk.MSG_INTRO)
	assert_int(t.start_msg()).is_equal(KkTalk.MSG_HELLO)
	## "Want me to jam?" → yes: the request question.
	assert_int(t.picked(KkTalk.MSG_HELLO, 0)).is_equal(KkTalk.MSG_REQUEST)
	assert_int(t.start_msg()).is_equal(KkTalk.MSG_AGAIN)


func test_kk_request_by_exact_title() -> void:
	var inv := Inventory.new()
	var t := KkTalk.new({}, {}, inv)
	t.context = DialogueContext.new()
	var title: String = MinidiskCatalog.song_name(5)
	var step: Dictionary = t.text_result(title)
	assert_int(int(step["msg"])).is_equal(KkTalk.MSG_FAR_OUT)
	assert_int(t.song).is_equal(5)
	assert_int(inv.count_of(MinidiskCatalog.item_id(5))).is_equal(1)
	assert_int(t.after_show_msg()).is_equal(KkTalk.MSG_AIRCHECK)
	## Already got tonight's aircheck.
	assert_int(t.picked(KkTalk.MSG_AGAIN, 0)).is_equal(KkTalk.MSG_ALREADY)
	## Unknown title: one of his made-up tunes, no aircheck.
	var u := KkTalk.new({}, {}, inv)
	u.context = DialogueContext.new()
	assert_int(int(u.text_result("not a song")["msg"])).is_equal(KkTalk.MSG_MADE_UP)
	assert_int(u.song).is_between(KkTalk.MADE_UP_FIRST, KkTalk.MADE_UP_FIRST + 2)
	assert_int(u.after_show_msg()).is_equal(KkTalk.MSG_NOT_MY_BAG)


func test_kk_random_pick_skips_collected() -> void:
	var player: Dictionary = {"collected": (1 << KkTalk.GOOD_SONGS) - 1 - (1 << 7)}
	var t := KkTalk.new({}, player, Inventory.new())
	assert_int(t.random_song()).is_equal(7)


func test_gulliver_gives_a_keepsake_once_awake() -> void:
	var inv := Inventory.new()
	var area: Dictionary = {}
	var g := GulliverTalk.new(GulliverTalk.Mode.WOKEN, area, inv)
	var first: int = g.start_msg()
	assert_int(first).is_between(GulliverTalk.MSG_WAKE, GulliverTalk.MSG_WAKE + 5)
	assert_bool(bool(area["wakeup"])).is_true()
	g.current_msg = first
	assert_int(int(g.next_step()["msg"])).is_equal(GulliverTalk.MSG_GIFT)
	g.current_msg = GulliverTalk.MSG_GIFT
	var step: Dictionary = g.next_step()
	assert_int(int(step["msg"])).is_equal(GulliverTalk.MSG_BYE_FIRST)
	assert_bool(bool(area["give"])).is_true()
	if FtrCatalog.available():
		assert_int(inv.count_of(g.gift)).is_equal(1)
	## Afterwards he just chats.
	var chat := GulliverTalk.new(GulliverTalk.Mode.WANDER, area, inv)
	assert_int(chat.start_msg()).is_between(GulliverTalk.MSG_CHAT, GulliverTalk.MSG_CHAT + 5)


func test_redd_stock_and_sale() -> void:
	if not FtrCatalog.available():
		return
	var area: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	ReddStock.roll(area, rng)
	var items: Array[StringName] = ReddStock.items(area)
	assert_int(items.size()).is_equal(3)
	assert_int(ReddStock.left(area)).is_equal(3)
	var inv := Inventory.new()
	inv.set_wallet(99999)
	var t := ReddTalk.new(ReddTalk.Kind.OFFER, area, inv, rng)
	t.item_id = items[0]
	var runner := _start(t, t.start_msg())
	_run(runner)
	## "What do you say?" → yes.
	runner.choose(0)
	_run(runner)
	assert_int(t.current_msg).is_equal(ReddTalk.MSG_SOLD)
	assert_int(inv.count_of(items[0])).is_equal(1)
	assert_int(inv.wallet).is_equal(99999 - ReddStock.price(items[0]))
	assert_that(ReddStock.bought(area)).is_equal(items[0])
	assert_int(ReddStock.left(area)).is_equal(2)
	## Outside afterwards he congratulates the purchase.
	var out := ReddTalk.new(ReddTalk.Kind.OUTSIDE, area, inv, rng)
	assert_int(out.start_msg()).is_equal(ReddTalk.MSG_OUT_BOUGHT)
