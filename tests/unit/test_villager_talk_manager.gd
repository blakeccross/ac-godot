class_name TestVillagerTalkManager
extends GdUnitTestSuite

## `VillagerTalkManager` / `NpcTalkInfo` against `ac_quest_talk_*.c` and `m_npc.c`.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	VillagerCatalog.reload()


func after_test() -> void:
	Game.reset_session()
	Clock.paused = false


func _villager(looks: int) -> VillagerData:
	for v: VillagerData in VillagerCatalog.all_villagers():
		if v.personality != null and int(v.personality.looks) == looks and not v.islander:
			return v
	return null


func _manager(looks: int = 2, seed_value: int = 1, hints_done: bool = true) -> VillagerTalkManager:
	var v: VillagerData = _villager(looks)
	var state: VillagerState = Game.villagers.get_or_create(v.id)
	var ctx := DialogueContext.from_game(v, state)
	ctx.rng = RandomNumberGenerator.new()
	ctx.rng.seed = seed_value
	ctx.inventory = Inventory.new()
	var m := VillagerTalkManager.new(v, state, ctx)
	m.slot = 0
	var hints := {"n": VillagerTalkManager.FJ_HINT_DONE if hints_done else 0}
	m.hint_count_get = func() -> int: return int(hints["n"])
	m.hint_count_set = func(value: int) -> void: hints["n"] = value
	return m


func test_after_greeting_offers_the_three_choices() -> void:
	var m: VillagerTalkManager = _manager(2)
	var step: Dictionary = m.next_step()
	var msg: int = int(step["msg"])
	assert_int(msg).is_between(0x2A6 + 2 * 3, 0x2A6 + 2 * 3 + 2)
	var labels: Array = step["choices"]
	assert_int(labels.size()).is_equal(3)
	if DialogueCatalog.choice_label(0x7F) != "":
		var help: Array[String] = []
		for i: int in 10:
			help.append(DialogueCatalog.choice_label(0x7F + i))
		assert_bool(str(labels[0]) in help).is_true()


func test_choices_route_like_no_or_normal() -> void:
	var m: VillagerTalkManager = _manager(0)
	## Not asking for anything (`mNpc_CheckQuestRequest` off) → NO_OR_NORMAL.
	m.talk_info.set_quest_request_off(m.slot, m.looks)
	m.next_step()
	assert_int(int(m.choose(0)["msg"])).is_between(0x282, 0x282 + 2)
	m = _manager(5)
	m.talk_info.set_quest_request_off(m.slot, m.looks)
	m.next_step()
	assert_int(int(m.choose(2)["msg"])).is_between(0x254A + 15, 0x254A + 17)


func test_lets_talk_adds_one_friendship_then_a_topic() -> void:
	var m: VillagerTalkManager = _manager(2)
	m.state.relationship.set_friendship(10)
	m.next_step()
	var step: Dictionary = m.choose(1)
	assert_int(m.state.friendship).is_equal(11)
	assert_int(int(step["msg"])).is_greater(0)
	## The chat topic ends the talk.
	assert_that(m.next_step()).is_equal({})


func test_first_ten_chats_are_first_job_hints() -> void:
	var m: VillagerTalkManager = _manager(3, 1, false)
	for i: int in 10:
		assert_int(m.normal_select_talk()).is_equal(0x0841 + 3 * 10 + i)
	assert_int(int(m.hint_count_get.call())).is_equal(VillagerTalkManager.FJ_HINT_DONE)
	assert_int(m.normal_select_talk()).is_not_equal(0x0841 + 3 * 10 + 10)


func test_happy_villager_uses_the_ki_table() -> void:
	var m: VillagerTalkManager = _manager(1)
	m.state.mood = VillagerState.Mood.HAPPY
	for seed_value: int in 20:
		m.context.rng.seed = seed_value
		var msg: int = m.normal_select_talk()
		var ok: bool = (
			(msg >= 0x2099 and msg < 0x2099 + 10)
			or (msg >= 0x1DD0 and msg < 0x1DD0 + 4 * 6 + 6)
			or (msg >= 0x1CBE and msg < 0x1CBE + 3)
			or (msg >= 0x1CF9 and msg < 0x1CF9 + 3)
		)
		assert_bool(ok).is_true()


func test_friendship_order_counts_values_over_100_as_losses() -> void:
	var m: VillagerTalkManager = _manager()
	## Quest demo orders only reach the everyday chat.
	m._normal = true
	m.state.relationship.set_friendship(50)
	m.order(5, 3)
	assert_int(m.state.friendship).is_equal(53)
	m.order(5, 104)
	assert_int(m.state.friendship).is_equal(49)
	m.order(5, 100)
	assert_int(m.state.friendship).is_equal(127)


func test_trade_buys_the_players_furniture_for_goods() -> void:
	var m: VillagerTalkManager = _manager()
	## Quest demo orders only reach the everyday chat.
	m._normal = true
	var ftr: StringName = &""
	for id: StringName in ShopGoods.furniture_pool():
		ftr = id
		break
	if ftr == &"":
		return
	var inv: Inventory = m.inventory
	inv.add_to_empty_slot(ItemCatalog.get_item(ftr))
	m.order(2, 1)
	assert_that(m.trade_items[0]).is_equal(ftr)
	assert_int(m.pay % 10).is_equal(0)
	assert_int(m.pay).is_between(100, 2999)
	assert_that(m.context.item0).is_not_empty()
	## Hand the furniture over, receive goods 1 in the same pocket.
	m.order(3, 5)
	assert_bool(inv.slot_at(0).is_empty()).is_true()
	m.order(3, 14)
	assert_that(inv.slot_at(0).item.item_id).is_equal(m.trade_items[1])


func test_trade_pays_bells_over_the_wallet_cap_in_bags() -> void:
	var m: VillagerTalkManager = _manager()
	## Quest demo orders only reach the everyday chat.
	m._normal = true
	m.inventory.set_wallet(Inventory.WALLET_MAX - 50)
	m.order(2, 17)
	assert_int(m.pay).is_between(100, 999)
	m.order(3, 22)
	assert_int(m.inventory.wallet).is_less_equal(Inventory.WALLET_MAX)
	var bags: int = m.inventory.count_of(&"money_30000")
	assert_int(m.inventory.wallet + bags * 30000).is_equal(Inventory.WALLET_MAX - 50 + m.pay)


func test_set_string_fills_item_strings_from_the_rom_table() -> void:
	var m: VillagerTalkManager = _manager()
	## Quest demo orders only reach the everyday chat.
	m._normal = true
	m.order(9, 3)
	if DialogueCatalog.rom_string(0x464) == "":
		return
	assert_that(m.context.item0).is_not_empty()
	assert_that(m.context.item_strs[0]).is_not_empty()


func test_prob_table_draws_every_index() -> void:
	var m: VillagerTalkManager = _manager()
	var seen: Dictionary = {}
	for i: int in 400:
		seen[m.decide_idx_prob_table(VillagerTalkManager.NORMAL_2_PROB)] = true
	assert_int(seen.size()).is_equal(4)


func test_message_feel_order_sets_timed_mood() -> void:
	var state := VillagerState.new()
	state.set_feel(1, 3)
	assert_int(state.mood).is_equal(VillagerState.Mood.HAPPY)
	assert_int(state.feel_ticks).is_equal(3 * 3600)
	state.set_feel(1, 20)
	assert_int(state.feel_ticks).is_equal(10 * 3600)
	state.tick_feel(10 * 3600)
	assert_int(state.mood).is_equal(VillagerState.Mood.NORMAL)
	state.set_feel(5, 2)
	assert_int(state.mood).is_equal(VillagerState.Mood.NORMAL)


func test_runner_applies_feel_after_the_page() -> void:
	var state := VillagerState.new()
	var data := DialogueData.from_dict({
		"id": "t_feel", "start": "p0",
		"nodes": {"p0": {"type": "line", "text": "Hi", "events": [
			{"op": "demo_order", "target": "npc0", "slot": 2, "value": 3},
			{"op": "demo_order", "target": "npc0", "slot": 8, "value": 2},
		]}},
	})
	var runner := DialogueRunner.new()
	runner.start(data, DialogueContext.new(), state)
	assert_int(state.mood).is_equal(VillagerState.Mood.SAD)
	assert_int(state.feel_ticks).is_equal(2 * 3600)


func test_runner_asks_the_manager_and_shows_its_menu() -> void:
	var m: VillagerTalkManager = _manager(2)
	var greeting := DialogueData.from_dict({
		"id": "t_greet", "start": "p0", "nodes": {"p0": {"type": "line", "text": "Hello"}},
	})
	var runner := DialogueRunner.new()
	runner.talk_manager = m
	runner.start(greeting, m.context, m.state)
	runner.advance()
	if DialogueCatalog.conversation(&"msg_684") == null:
		return
	## Now on 0x2A6 + looks×3 (+0–2); its end shows the three choices.
	while not runner.waiting_choice and not runner.done:
		runner.advance()
	assert_bool(runner.waiting_choice).is_true()
	assert_int(runner.choices.size()).is_equal(3)
	runner.choose(2)
	assert_bool(runner.done).is_false()
	assert_str(String(runner.conversation.id)).starts_with("msg_")


func test_friendship_starts_at_one_and_caps_at_127() -> void:
	var bond := Relationship.new()
	assert_int(bond.record_talk("2001-01-01")).is_equal(1)
	assert_int(bond.friendship).is_equal(1)
	assert_int(bond.record_talk("2001-01-02")).is_equal(0)
	assert_int(bond.friendship).is_equal(1)
	bond.add_friendship(500)
	assert_int(bond.friendship).is_equal(127)


func test_talk_info_patience_and_request_flag() -> void:
	var info := NpcTalkInfo.new()
	assert_bool(info.quest_request(3)).is_true()
	## Looks 0: over-impatient at 12 talks, refuses at 15 (each within 1000 ticks).
	for i: int in 12:
		info.talk_end(3, 0)
	assert_int(info.patience(3, 0)).is_equal(NpcTalkInfo.Patience.MILDLY_ANNOYED)
	for i: int in 3:
		info.talk_end(3, 0)
	assert_int(info.patience(3, 0)).is_equal(NpcTalkInfo.Patience.ANNOYED)
	## The unlock timer (4000) only runs 1000 ticks per acre; wading re-arms it.
	info.tick(1500)
	assert_int(info.patience(3, 0)).is_equal(NpcTalkInfo.Patience.ANNOYED)
	for _w: int in 4:
		info.on_wade_start()
		info.tick(1000)
	assert_int(info.patience(3, 0)).is_equal(NpcTalkInfo.Patience.NORMAL)
	info.set_quest_request_off(3, 0)
	assert_bool(info.quest_request(3)).is_false()


func test_rumour_topic_uses_the_event_rumor_table_slot() -> void:
	var m: VillagerTalkManager = _manager(2)
	## 2001-12-27: new year's day and new year's eve rumours both run.
	Clock.apply_snapshot({"year": 2001, "month": 12, "day": 27, "hour": 10, "minute": 0, "second": 0})
	Game.events.sync(EventCalendar.date_from_clock())
	var seen: Dictionary = {}
	for i: int in 40:
		m.context.rng.seed = i
		var msg: int = m._decide_calendar_ev()
		seen[msg] = true
		var base: int = VillagerTalkManager.EV_CAL[2]
		## Whatever is live today, at its `event_rumor_table` slot × 2 (+0/1).
		var slot: int = (msg - base) / 2
		assert_bool(slot >= 0 and slot < VillagerTalkManager.RUMOR_TABLE.size()).is_true()
		assert_bool(VillagerTalkManager.RUMOR_TABLE[slot] in Game.events.active_rumors()).is_true()
	assert_int(seen.size()).is_greater(1)
	## Moon dates are always set for the message.
	assert_str(m.context.frees[16]).is_not_empty()


func test_kamakura_rumour_is_winter_only() -> void:
	var m: VillagerTalkManager = _manager(0)
	Clock.apply_snapshot({"year": 2001, "month": 7, "day": 10, "hour": 10, "minute": 0, "second": 0})
	Game.events.force(&"rumor_kamakura")
	Game.events.sync(EventCalendar.date_from_clock())
	for i: int in 20:
		m.context.rng.seed = i
		var msg: int = m._decide_calendar_ev()
		assert_bool(msg == -1 or msg < VillagerTalkManager.EV_CAL[0] + 2 or msg >= VillagerTalkManager.EV_CAL[0] + 4).is_true()


func test_special_visitor_topic_before_the_visit() -> void:
	var m: VillagerTalkManager = _manager(3)
	Clock.apply_snapshot({"year": 2001, "month": 5, "day": 3, "hour": 9, "minute": 0, "second": 0})
	Game.events.special_type = &"gypsy"
	Game.events.special_year = 2001
	Game.events.special_dates = {"special0": EventDates.md(5, 1), "special1": EventDates.md(5, 6), "special2": EventDates.md(5, 7), "special3": 6}
	var msg: int = m._decide_special_ev()
	var base: int = VillagerTalkManager.EV_SPECIAL[3] + 5 * 3
	assert_int(msg).is_between(base, base + 2)
	## After the visit day it's old news.
	Clock.apply_snapshot({"year": 2001, "month": 5, "day": 7, "hour": 9, "minute": 0, "second": 0})
	assert_int(m._decide_special_ev()).is_equal(-1)
	## On the day itself it still comes up.
	Clock.apply_snapshot({"year": 2001, "month": 5, "day": 6, "hour": 22, "minute": 0, "second": 0})
	assert_int(m._decide_special_ev()).is_between(base, base + 2)


func test_lunar_dates_are_near_the_harvest_moon() -> void:
	var moon: Vector2i = VillagerTalkManager.moon_dates(2001)
	assert_int(moon.x).is_equal(1001)
	assert_int(moon.y).is_equal(1029)
	assert_int(VillagerTalkManager.lunar_today(2001, 10, 1)).is_equal(815)
