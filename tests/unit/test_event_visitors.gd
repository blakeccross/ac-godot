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


func test_saharah_prices_double_and_needs_a_carpet() -> void:
	if not FtrCatalog.available():
		return
	var area: Dictionary = {"used": 2}
	var inv := Inventory.new()
	inv.set_wallet(20000)
	var t := SaharahTalk.new(area, inv)
	t.context = DialogueContext.new()
	t.prepare()
	assert_int(t.price).is_equal(12000)
	assert_str(t.context.frees[0]).is_equal("12000")
	## No carpet in the pockets.
	assert_int(t.picked(SaharahTalk.MSG_OFFER, 0)).is_equal(SaharahTalk.MSG_NO_CARPET)
	var floor_item: ItemData = ItemCatalog.get_item(InteriorStyleCatalog.floor_style_id(3))
	inv.add(floor_item, 1)
	assert_int(t.picked(SaharahTalk.MSG_OFFER, 0)).is_equal(SaharahTalk.MSG_CHOOSE)
	var step: Dictionary = t.hand_result(floor_item.id)
	assert_int(int(step["then"]["msg"])).is_equal(SaharahTalk.MSG_TRADE)
	assert_int(inv.wallet).is_equal(8000)
	assert_int(inv.count_of(t.carpet)).is_equal(1)
	assert_int(int(area["used"])).is_equal(3)


func test_wendell_gives_wallpaper_for_fish() -> void:
	if not FtrCatalog.available():
		return
	var area: Dictionary = {}
	var inv := Inventory.new()
	var t := WendellTalk.new(area, inv)
	assert_int(t.start_msg()).is_equal(WendellTalk.MSG_HUNGRY)
	var fish: ItemData = null
	for it: ItemData in ItemCatalog.all_items():
		if it.category == ItemData.Category.FISH:
			fish = it
			break
	if fish == null:
		return
	inv.add(fish, 1)
	assert_int(int(t.hand_result(fish.id)["msg"])).is_equal(WendellTalk.MSG_FISH)
	assert_int(inv.count_of(fish.id)).is_equal(0)
	t.current_msg = WendellTalk.MSG_FISH
	assert_int(int(t.next_step()["msg"])).is_equal(WendellTalk.MSG_THANKS)
	assert_int(inv.count_of(t.present)).is_equal(1)
	assert_int(WendellTalk.new(area, inv).start_msg()).is_equal(WendellTalk.MSG_FULL)


func test_gracie_wash_results() -> void:
	if not FtrCatalog.available():
		return
	var area: Dictionary = {}
	var inv := Inventory.new()
	var t := GracieTalk.new(GracieTalk.Kind.NORMAL, area, inv)
	t.female = true
	var first: int = t.start_msg()
	assert_int(first).is_between(GracieTalk.MSG_NOT_WEARING[4], GracieTalk.MSG_NOT_WEARING[7])
	t.current_msg = first
	assert_int(int(t.next_step()["msg"])).is_equal(GracieTalk.MSG_NOT_WEARING[19])
	assert_bool(t.wants_wash).is_true()
	var r := GracieTalk.new(GracieTalk.Kind.RESULT, area, inv)
	r.result = 0
	r.current_msg = r.start_msg()
	assert_int(int(r.next_step()["msg"])).is_equal(GracieTalk.MSG_NOT_WEARING[12])
	assert_bool(FtrCatalog.named_list("cloth", "Event").has(r.present)).is_true()
	assert_int(inv.count_of(r.present)).is_equal(1)


func test_katrina_reading_costs_50_and_sets_a_destiny() -> void:
	var inv := Inventory.new()
	inv.set_wallet(60)
	var t := KatrinaTalk.new(KatrinaTalk.Destiny.NORMAL, false, inv)
	t.context = DialogueContext.new()
	assert_int(t.start_msg()).is_equal(KatrinaTalk.MSG_ASK)
	assert_int(t.picked(KatrinaTalk.MSG_ASK, 0)).is_equal(KatrinaTalk.MSG_READING)
	assert_int(inv.wallet).is_equal(10)
	t.current_msg = KatrinaTalk.MSG_READING
	var n: int = int(t.next_step()["msg"])
	assert_int(n).is_between(KatrinaTalk.MSG_RESULT, KatrinaTalk.MSG_RESULT + 5)
	assert_int(t.destiny).is_equal(n - KatrinaTalk.MSG_RESULT)
	## Out of Bells now.
	var broke := KatrinaTalk.new(KatrinaTalk.Destiny.NORMAL, false, inv)
	broke.context = DialogueContext.new()
	assert_int(broke.picked(KatrinaTalk.MSG_ASK, 0)).is_equal(KatrinaTalk.MSG_BROKE)


func test_tortimer_holiday_gives_the_trophy_once() -> void:
	var record: Dictionary = {}
	var inv := Inventory.new()
	var ev: int = TortimerHoliday.event_index(&"soncho_nature_day")
	assert_int(ev).is_greater_equal(0)
	var t := TortimerHoliday.new(ev, record, inv)
	t.context = DialogueContext.new()
	t.prepare()
	var first: int = t.start_msg()
	assert_int(first).is_equal(t.msg_for(0))
	t.current_msg = first
	var step: Dictionary = t.next_step()
	assert_int(int(step["msg"])).is_equal(t.msg_for(3))
	assert_int(inv.count_of(t.item)).is_equal(1)
	## Same year, trophy owned: one of the chat lines.
	var again := TortimerHoliday.new(ev, record, inv)
	again.context = DialogueContext.new()
	again.prepare()
	assert_int(again.start_msg()).is_between(again.msg_for(6), again.msg_for(8))
	assert_int(TortimerHoliday.new(TortimerHoliday.HARVEST_FESTIVAL, {}, inv).msg_for(0)).is_equal(TortimerHoliday.MSG_HARVEST_FESTIVAL)


func test_festival_crowd_talk_follows_looks_and_slot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	## `aHN1_set_talk_info`: base[looks] + RANDOM(3) + npc_idx * 3, npc_idx from HANABI_1.
	var n: int = FestivalCrowd.talk_msg(&"hanabi1", VillagerPersonality.Looks.LAZY, 3, rng)
	assert_int(n).is_between(5699 + 6, 5699 + 8)
	## Meteor shower swaps the moon-viewing lines.
	var alt: int = FestivalCrowd.talk_msg(&"tukimi1", VillagerPersonality.Looks.NORMAL, 0, rng, true)
	assert_int(alt).is_between(0x3F46, 0x3F48)
	assert_str(String(FestivalCrowd.family_of("SP_NPC_EV_HANAMI_4"))).is_equal("hanami1")
	var ids: Array[StringName] = [&"a", &"b", &"c", &"d"]
	var picked: Array[StringName] = FestivalCrowd.pick_villagers(ids, 2, "x", func(v: StringName) -> bool: return v == &"c")
	assert_int(picked.size()).is_equal(2)
	assert_str(String(picked[0])).is_equal("c")
	assert_array(FestivalCrowd.pick_villagers(ids, 2, "x")).is_equal(FestivalCrowd.pick_villagers(ids, 2, "x"))


func test_yomise_sells_tonights_goods() -> void:
	var inv := Inventory.new()
	inv.set_wallet(1000)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var area: Dictionary = {}
	var t := YomiseTalk.new(area, inv, rng)
	t.context = DialogueContext.new()
	assert_int(t.start_msg()).is_equal(YomiseTalk.MSG_PITCH[t.kind()])
	var menu: Dictionary = t.pick_step(t.start_msg(), 0)
	assert_int(int(menu["msg"])).is_equal(YomiseTalk.MSG_PICK)
	assert_int((menu["choices"] as Array).size()).is_equal(4)
	assert_int(int(t.choose(0)["msg"])).is_equal(YomiseTalk.MSG_BOUGHT)
	assert_int(inv.wallet).is_equal(1000 - YomiseTalk.PRICE[t.kind()])
	t.current_msg = YomiseTalk.MSG_BOUGHT
	assert_int(int(t.next_step()["msg"])).is_equal(YomiseTalk.MSG_ANOTHER)
	assert_int(t.left_from(0)).is_equal(7)
	## "I don't want it!" on a full page → "anything else?", then the next three.
	t.pick_step(YomiseTalk.MSG_MORE, 0)
	assert_int(int(t.choose(3)["msg"])).is_equal(YomiseTalk.MSG_MORE)
	## Out of Bells.
	var broke := Inventory.new()
	var t2 := YomiseTalk.new(area, broke, rng)
	t2.pick_step(YomiseTalk.MSG_PITCH[t2.kind()], 0)
	assert_int(int(t2.choose(0)["msg"])).is_equal(YomiseTalk.MSG_BROKE)


func test_angler_measures_bass_and_keeps_the_record() -> void:
	var inv := Inventory.new()
	var bass: ItemData = ItemCatalog.get_item(&"large_bass")
	if bass == null:
		return
	inv.add(bass, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var area: Dictionary = {}
	var t := AnglerTalk.new(area, inv, rng, 10)
	t.context = DialogueContext.new()
	assert_int(t.start_msg()).is_equal(AnglerTalk.MSG_RULES)
	assert_int(AnglerTalk.new(area, inv, rng, 10).start_msg()).is_equal(AnglerTalk.MSG_CAUGHT_ONE)
	assert_int(AnglerTalk.new(area, inv, rng, 19).start_msg()).is_equal(AnglerTalk.MSG_CLOSED)
	t.current_msg = AnglerTalk.MSG_HAND_IT_OVER
	assert_str(str(t.next_step()["hand"]["mode"])).is_equal("take")
	var step: Dictionary = t.hand_result(&"large_bass")
	assert_int(int(step["msg"])).is_equal(0x111A)
	## `mFR_fish_rndsize(LARGE)`: 50–70 cm.
	assert_int(t.size).is_between(19, 27)
	t.current_msg = 0x111A
	var after: Dictionary = t.next_step()
	assert_int(int(after["msg"])).is_equal(0x111A + 2)
	assert_int(inv.count_of(&"large_bass")).is_equal(0)
	assert_bool(bool(area["top_player"])).is_true()
	assert_int(int(area["size"])).is_equal(t.size)
	## A villager's catch can only raise the record.
	AnglerTalk.roll_npc_record(area, 8, ["Rosie"], rng)
	assert_int(int(area["size"])).is_greater_equal(t.size)


func test_miko_fortune_costs_50_and_sends_a_letter() -> void:
	var inv := Inventory.new()
	inv.set_wallet(80)
	var t := MikoTalk.new(inv)
	t.context = DialogueContext.new()
	assert_int(t.start_msg()).is_equal(MikoTalk.MSG_ASK)
	assert_int(t.picked(MikoTalk.MSG_ASK, 0)).is_equal(-1)
	t.current_msg = MikoTalk.MSG_CHANT
	var n: int = int(t.next_step()["msg"])
	assert_int(n).is_between(MikoTalk.MSG_READING, MikoTalk.MSG_READING + 3)
	assert_int(inv.wallet).is_equal(30)
	t.entered(MikoTalk.MSG_HERE)
	assert_int(inv.received_mail_count()).is_equal(1)
	var broke := MikoTalk.new(inv)
	broke.context = DialogueContext.new()
	assert_int(broke.picked(MikoTalk.MSG_ASK, 0)).is_equal(MikoTalk.MSG_BROKE)


func test_festival_terms_pick_countdown_and_groundhog_lines() -> void:
	var rng := RandomNumberGenerator.new()
	assert_int(FestivalCrowd.countdown_term(23 * 3600 + 56 * 60)).is_equal(FestivalCrowd.Countdown.FIVE)
	assert_int(FestivalCrowd.countdown_term(5)).is_equal(FestivalCrowd.Countdown.NEW_YEAR)
	assert_int(FestivalCrowd.countdown_term(3600)).is_equal(FestivalCrowd.Countdown.AFTER)
	## `aCD1_set_talk_info`: term * 4, +17 after midnight.
	var n: int = FestivalCrowd.talk_msg(&"countdown", 0, 2, rng, false, FestivalCrowd.Countdown.TEN)
	assert_int(n).is_between(7528 + 8, 7528 + 10)
	assert_int(FestivalCrowd.talk_msg(&"countdown", 0, 2, rng, false, FestivalCrowd.Countdown.AFTER)).is_between(7528 + 17, 7528 + 19)
	assert_int(FestivalCrowd.countdown_force_msg(0, FestivalCrowd.Countdown.TEN)).is_equal(7531 + 4)
	## `aGH0_set_norm_talk_info`: the last minute shares the 5-minute lines.
	assert_int(FestivalCrowd.groundhog_term(7 * 3600 + 59 * 60)).is_equal(FestivalCrowd.Groundhog.ONE)
	var g: int = FestivalCrowd.talk_msg(&"groundhog", 0, 1, rng, false, FestivalCrowd.Groundhog.ONE)
	assert_int(g).is_between(15698 + 9, 15698 + 11)


func test_franklin_trades_his_knife_and_fork_for_a_present() -> void:
	if not FtrCatalog.available():
		return
	var area: Dictionary = {}
	var inv := Inventory.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var t := FranklinTalk.new(area, inv, rng)
	t.context = DialogueContext.new()
	assert_int(t.start_msg()).is_equal(FranklinTalk.MSG_STORY)
	t.current_msg = FranklinTalk.MSG_STORY
	assert_int(int(t.next_step()["msg"])).is_equal(FranklinTalk.MSG_STORY + 1)
	t.current_msg = FranklinTalk.MSG_STORY_LAST
	assert_int(int(t.next_step()["msg"])).is_between(FranklinTalk.MSG_PLEA, FranklinTalk.MSG_PLEA + 2)
	inv.add(ItemCatalog.get_item(FranklinTalk.FORK), 1)
	var again := FranklinTalk.new(area, inv, rng, t.present_idx)
	again.context = DialogueContext.new()
	assert_int(again.start_msg()).is_equal(FranklinTalk.MSG_AGAIN + t.present_idx)
	again.current_msg = FranklinTalk.MSG_AGAIN + t.present_idx
	var step: Dictionary = again.next_step()
	assert_int(int(step["then"]["msg"])).is_equal(FranklinTalk.MSG_THANKS + t.present_idx)
	assert_int(inv.count_of(FranklinTalk.FORK)).is_equal(0)
	assert_int(inv.count_of(FranklinTalk.presents()[t.present_idx])).is_equal(1)
	## Never the same present twice until all twelve are given.
	for _i: int in 20:
		assert_int(FranklinTalk.decide_present(area, rng)).is_not_equal(t.present_idx)


func test_trick_or_treat_candy_and_tricks() -> void:
	if not FtrCatalog.available():
		return
	var inv := Inventory.new()
	inv.add(ItemCatalog.get_item(&"candy"), 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var jack := TrickOrTreatTalk.new(true, 0, inv, rng)
	assert_int(jack.start_msg()).is_equal(TrickOrTreatTalk.MSG_TRICK_OR_TREAT)
	jack.current_msg = TrickOrTreatTalk.MSG_TRICK_OR_TREAT
	assert_int(int(jack.next_step()["msg"])).is_equal(TrickOrTreatTalk.JACK_ASK)
	assert_str(str(jack.pick_step(TrickOrTreatTalk.JACK_ASK, 0)["hand"]["mode"])).is_equal("take")
	assert_int(int(jack.hand_result(&"candy")["msg"])).is_equal(TrickOrTreatTalk.JACK_CANDY)
	assert_int(inv.count_of(&"candy")).is_equal(0)
	jack.current_msg = TrickOrTreatTalk.JACK_CANDY
	assert_int(int(jack.next_step()["msg"])).is_equal(TrickOrTreatTalk.JACK_BYE)
	## A costumed villager (looks 2) with no candy: the empty-hand line, then a trick.
	var npc := TrickOrTreatTalk.new(false, 2, inv, rng)
	npc.current_msg = TrickOrTreatTalk.MSG_TRICK_OR_TREAT
	assert_int(int(npc.next_step()["msg"])).is_equal(TrickOrTreatTalk.NPC_ASK + 12)
	assert_int(int(npc.hand_result(&"")["msg"])).is_equal(TrickOrTreatTalk.NPC_EMPTY + 12)
	npc.current_msg = TrickOrTreatTalk.NPC_EMPTY + 12
	assert_int(int(npc.next_step()["msg"])).is_equal(TrickOrTreatTalk.NPC_TRICKED + 12)
	assert_bool(npc.tricked_cloth or npc.tricked_item != &"").is_true()


func test_jingle_wish_list_and_shirt_trick() -> void:
	if not FtrCatalog.available():
		return
	var area: Dictionary = {}
	var inv := Inventory.new()
	var rng := RandomNumberGenerator.new()
	var talk := func(block: Vector2i, cloth: StringName) -> JingleTalk:
		var t := JingleTalk.new(area, inv, rng)
		t.block = block
		t.cloth = cloth
		return t
	assert_int(talk.call(Vector2i(1, 1), &"shirt_000").start_msg()).is_equal(JingleTalk.MSG_HELLO)
	assert_int(talk.call(Vector2i(1, 1), &"shirt_000").start_msg()).is_between(JingleTalk.MSG_SAME_ACRE, JingleTalk.MSG_SAME_ACRE + 2)
	var t1: JingleTalk = talk.call(Vector2i(2, 1), &"shirt_000")
	assert_int(t1.start_msg()).is_equal(JingleTalk.MSG_CHECK_1ST)
	t1.picked(JingleTalk.MSG_CHECK_1ST, 1)
	var t2: JingleTalk = talk.call(Vector2i(3, 1), &"shirt_000")
	assert_int(t2.start_msg()).is_equal(JingleTalk.MSG_CHECK_2ND)
	t2.picked(JingleTalk.MSG_CHECK_2ND, 0)
	## 1st answer "no" (bit 0), 2nd "yes": clothing.
	var t3: JingleTalk = talk.call(Vector2i(4, 1), &"shirt_000")
	assert_int(t3.start_msg()).is_equal(JingleTalk.MSG_CHECK_FINAL[JingleTalk.Wish.CLOTH])
	t3.picked(JingleTalk.MSG_CHECK_FINAL[JingleTalk.Wish.CLOTH], 0)
	var t4: JingleTalk = talk.call(Vector2i(5, 1), &"shirt_000")
	assert_int(t4.start_msg()).is_equal(JingleTalk.MSG_PRESENT)
	assert_bool(FtrCatalog.named_list("cloth", "Christmas").has(t4.gift)).is_true()
	## Same shirt: recognised. New shirt twice in a row: another present.
	assert_int(talk.call(Vector2i(6, 1), &"shirt_000").start_msg()).is_between(JingleTalk.MSG_SAME_PLAYER, JingleTalk.MSG_SAME_PLAYER + 2)
	assert_int(talk.call(Vector2i(7, 1), &"shirt_005").start_msg()).is_equal(JingleTalk.MSG_ALMOST)
	assert_int(talk.call(Vector2i(8, 1), &"shirt_005").start_msg()).is_equal(JingleTalk.MSG_PRESENT2)
