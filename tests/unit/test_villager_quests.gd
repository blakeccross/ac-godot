class_name TestVillagerQuests
extends GdUnitTestSuite

## `VillagerQuests` + the quest half of `VillagerTalkManager` against `m_quest.c`,
## `ac_quest_manager.c` and `ac_quest_talk_init.c`.

const Q := preload("res://scripts/systems/villager_quests.gd")
const S := VillagerTalkManager.Step


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	VillagerCatalog.reload()
	VillagerTalkManager.errand_next = PackedByteArray([0, 0, 0, 0, 0])
	var houses: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var i: int = 0
	for v: VillagerData in VillagerCatalog.pick_starters(rng, 6):
		## One house per acre so every villager is "in another block".
		houses.append({"id": v.id, "home": Vector2i(20 + i * WorldGenerator.UT, 40)})
		i += 1
	Game.residents.adopt_from_houses(houses)


func after_test() -> void:
	Game.reset_session()
	Clock.paused = false


func _id(slot: int) -> StringName:
	return Game.residents.slots[slot]["id"]


func _manager(slot: int, seed_value: int = 1) -> VillagerTalkManager:
	var v: VillagerData = VillagerCatalog.get_villager(_id(slot))
	var state: VillagerState = Game.villagers.get_or_create(v.id)
	var ctx := DialogueContext.from_game(v, state)
	ctx.rng = RandomNumberGenerator.new()
	ctx.rng.seed = seed_value
	ctx.inventory = Game.inventory
	var m := VillagerTalkManager.new(v, state, ctx)
	m.slot = slot
	m.hint_count_get = func() -> int: return VillagerTalkManager.FJ_HINT_DONE
	return m


## Make the villager's next offer this type / kind (`npclist.quest_info`).
func _offer(slot: int, type: int, kind: int) -> void:
	var info: Dictionary = Q.new_base()
	info["type"] = type
	info["kind"] = kind
	Game.npc_talk_info.set_client_quest(slot, info)


func _in(msg: Dictionary, base: int, looks: int) -> bool:
	var n: int = int(msg.get("msg", -1))
	return n >= base + looks * 3 and n <= base + looks * 3 + 2


func test_limit_over_past_the_deadline_or_before_the_start() -> void:
	var q: Dictionary = Q.new_base()
	q["type"] = Q.Type.DELIVERY
	q["kind"] = Q.DELIVERY_NORMAL
	q["limit_on"] = true
	q["limit"] = 10000
	assert_bool(Q.limit_over(q, 9999)).is_false()
	assert_bool(Q.limit_over(q, 10000)).is_true()
	## Two days before the deadline is when it began; earlier means the clock went back.
	assert_bool(Q.limit_over(q, 10000 - 2 * 1440)).is_false()
	assert_bool(Q.limit_over(q, 10000 - 2 * 1440 - 1)).is_true()
	q["limit_on"] = false
	assert_bool(Q.limit_over(q, 99999)).is_false()


func test_delivery_from_offer_to_reward() -> void:
	_offer(0, Q.Type.DELIVERY, Q.DELIVERY_NORMAL)
	var a: VillagerTalkManager = _manager(0)
	var first: Dictionary = a.next_step()
	assert_int(a.step).is_equal(S.NEW_QUEST_OR_NORMAL)
	assert_bool(_in(first, 0x2A6, a.looks)).is_true()
	var ask: Dictionary = a.choose(0)
	assert_bool(_in(ask, 0x0151, a.looks)).is_true()
	assert_int((ask["choices"] as Array).size()).is_equal(2)
	var accepted: Dictionary = a.choose(0)
	assert_bool(_in(accepted, 0x024C, a.looks)).is_true()
	## The clothes are in the first pocket, flagged as a quest item, and handed over.
	var parcel: InventorySlot = Game.inventory.slot_at(0)
	assert_int(parcel.item.condition).is_equal(InventoryItem.Condition.QUEST)
	assert_that(accepted["anim"]["give"]).is_equal(parcel.item.item_id)
	var d: Dictionary = Game.quests.deliveries[0]
	assert_int(int(d["type"])).is_equal(Q.Type.DELIVERY)
	assert_that(d["from"]).is_equal(_id(0))
	assert_that(d["to"]).is_not_equal(_id(0))
	assert_int(int(d["limit"])).is_equal(Clock.absolute_minute() + 2 * 1440)
	assert_int(int(Game.npc_talk_info.client_quest(0)["type"])).is_equal(Q.Type.NONE)
	## The recipient takes it and pays.
	var to_slot: int = Game.residents.slot_of(d["to"])
	var b: VillagerTalkManager = _manager(to_slot, 5)
	b.state.relationship.set_friendship(20)
	b.next_step()
	assert_int(b.step).is_equal(S.FIN_QUEST_START)
	var hand: Dictionary = b.choose(0)
	assert_int(int(hand["hand"]["pocket"])).is_equal(0)
	var item: StringName = parcel.item.item_id
	var complete: Dictionary = b.hand_result(item, 0)
	assert_bool(_in(complete, 0x0175, b.looks)).is_true()
	assert_bool(Game.inventory.slot_at(0).is_empty() or Game.inventory.slot_at(0).item.item_id != item).is_true()
	assert_that(b.state.cloth_id).is_equal(item)
	var wallet: int = Game.inventory.wallet
	var reward: Dictionary = b.next_step()
	assert_int(int(reward["msg"])).is_greater(0)
	assert_int(b.state.friendship).is_equal(23)
	assert_bool(Q.is_free(d)).is_true()
	## Bells, furniture or the shirt they had on (`l_set_delivery_data[0]`: 40 / 30 / 30).
	var kind: int = int(b._target["reward_kind"])
	assert_bool(kind in [Q.Reward.FTR, Q.Reward.MONEY, Q.Reward.WORN_CLOTH]).is_true()
	if kind == Q.Reward.MONEY:
		assert_int(Game.inventory.wallet).is_greater(wallet)
	var thanks: Dictionary = b.next_step()
	assert_bool(_in(thanks, 0x0294, b.looks)).is_true()


func test_turning_a_request_down_costs_friendship_and_is_remembered() -> void:
	_offer(1, Q.Type.DELIVERY, Q.DELIVERY_NORMAL)
	var m: VillagerTalkManager = _manager(1)
	m.state.relationship.set_friendship(30)
	m.next_step()
	m.choose(0)
	var no: Dictionary = m.choose(1)
	assert_bool(_in(no, 0x025E, m.looks)).is_true()
	assert_int(m.state.friendship).is_equal(27)
	assert_int(int(Game.npc_talk_info.client_quest(1)["type"])).is_equal(Q.Type.DELIVERY)
	assert_bool(Q.is_free(Game.quests.deliveries[0])).is_true()


func test_full_pockets_mean_no_delivery() -> void:
	var filler: ItemData = ItemCatalog.get_item(&"paper")
	for i: int in Inventory.POCKET_SLOTS:
		Game.inventory.slot_at(i).set_stack(filler.id, 1)
	_offer(2, Q.Type.DELIVERY, Q.DELIVERY_NORMAL)
	var m: VillagerTalkManager = _manager(2)
	m.next_step()
	assert_int(m.step).is_equal(S.FULL_ITEM_OR_NORMAL)
	assert_bool(_in(m.choose(0), 0x0440, m.looks)).is_true()


func test_overdue_delivery_goes_back_to_the_sender() -> void:
	_offer(0, Q.Type.DELIVERY, Q.DELIVERY_NORMAL)
	var a: VillagerTalkManager = _manager(0)
	a.next_step()
	a.choose(0)
	a.choose(0)
	var item: StringName = Game.inventory.slot_at(0).item.item_id
	var later: VillagerTalkManager = _manager(0, 9)
	later.now_minute += 3 * 1440
	later.state.relationship.set_friendship(40)
	var nag: Dictionary = later.next_step()
	assert_int(later.step).is_equal(S.GIVEUP)
	assert_bool(_in(nag, 0x0187, later.looks)).is_true()
	assert_int(int(later.next_step()["hand"]["pocket"])).is_equal(0)
	## Closing the pockets: "dirty thief", then the pockets again.
	assert_bool(_in(later.hand_result(&""), 0x0499, later.looks)).is_true()
	assert_bool(later.next_step().has("hand")).is_true()
	var back: Dictionary = later.hand_result(item, 0)
	assert_bool(_in(back, 0x02B8, later.looks)).is_true()
	assert_int(later.state.friendship).is_equal(35)
	assert_bool(Q.is_free(Game.quests.deliveries[0])).is_true()
	assert_bool(Game.inventory.slot_at(0).is_empty()).is_true()


func test_errand_chain_returns_the_item_to_whoever_lent_it() -> void:
	_offer(0, Q.Type.ERRAND, Q.ERRAND_REQUEST)
	var a: VillagerTalkManager = _manager(0)
	a.next_step()
	assert_bool(_in(a.choose(0), 0x038C, a.looks)).is_true()
	a.choose(0)
	var e: Dictionary = Game.quests.errands[0]
	assert_int(int(e["progress"])).is_equal(4)
	assert_int(int(e["used_num"])).is_equal(1)
	assert_that((e["used_ids"] as Array)[0]).is_equal(_id(0))
	assert_int(int(e["pocket"])).is_equal(-1)
	## The borrower hands it back straight away (`errand_next` = 1 → final).
	VillagerTalkManager.errand_next[0] = 1
	var b: VillagerTalkManager = _manager(Game.residents.slot_of(e["to"]))
	b.next_step()
	assert_int(b.step).is_equal(S.RENEW_ERRAND_OR_NORMAL)
	var give: Dictionary = b.choose(0)
	assert_bool(_in(give, 0x039E, b.looks)).is_true()
	assert_int(int(e["kind"])).is_equal(Q.ERRAND_REQUEST_FINAL)
	assert_that(e["to"]).is_equal(_id(0))
	var pocket: int = int(e["pocket"])
	assert_int(pocket).is_equal(0)
	assert_that(Game.inventory.slot_at(0).item.item_id).is_equal(e["item"])
	var end: Dictionary = b.next_step()
	assert_bool(_in(end, 0x024C, b.looks)).is_true()
	assert_that(end["anim"]["give"]).is_equal(e["item"])
	## Back to the lender.
	var home: VillagerTalkManager = _manager(0, 4)
	home.next_step()
	assert_int(home.step).is_equal(S.FIN_QUEST_START)
	home.choose(0)
	assert_bool(_in(home.hand_result(e["item"], 0), 0x03F8, home.looks)).is_true()
	home.next_step()
	assert_bool(Q.is_free(e)).is_true()


func test_errand_passed_on_goes_to_someone_new() -> void:
	_offer(0, Q.Type.ERRAND, Q.ERRAND_REQUEST)
	var a: VillagerTalkManager = _manager(0)
	a.next_step()
	a.choose(0)
	a.choose(0)
	var e: Dictionary = Game.quests.errands[0]
	var first_to: StringName = e["to"]
	VillagerTalkManager.errand_next[0] = 2
	var b: VillagerTalkManager = _manager(Game.residents.slot_of(first_to))
	b.next_step()
	assert_bool(_in(b.choose(0), 0x03B0, b.looks)).is_true()
	assert_int(int(e["kind"])).is_equal(Q.ERRAND_REQUEST_CONTINUE)
	assert_int(int(e["progress"])).is_equal(3)
	assert_int(int(e["used_num"])).is_equal(2)
	assert_that(e["to"]).is_not_equal(first_to)
	assert_that(e["to"]).is_not_equal(_id(0))
	## The first villager now reminds the player where it went (`aQMgr_actor_check_errand_from`).
	var lender: VillagerTalkManager = _manager(0)
	lender.next_step()
	assert_int(lender.step).is_equal(S.ROOT_RECONF_OR_NORMAL)


func test_fruit_contest_takes_the_fruit_and_stays_done() -> void:
	_offer(3, Q.Type.CONTEST, Q.CONTEST_FRUIT)
	var m: VillagerTalkManager = _manager(3)
	m.next_step()
	m.choose(0)
	var c: Dictionary = Game.quests.contests[3]
	assert_int(int(c["type"])).is_equal(Q.Type.CONTEST)
	assert_that(c["requested"]).is_not_equal(Game.town_fruit)
	assert_that(c["owner"]).is_equal(_id(3))
	## A second fruit contest can't start while this one runs.
	assert_int(Game.quests.occured_contest_idx(Q.CONTEST_FRUIT)).is_equal(3)
	m.choose(0)
	Game.inventory.slot_at(4).set_stack(c["requested"], 1)
	var done: VillagerTalkManager = _manager(3, 2)
	done.next_step()
	assert_int(done.step).is_equal(S.FIN_QUEST_START)
	var hand: Dictionary = done.choose(0)
	assert_int(int(hand["hand"]["pocket"])).is_equal(4)
	done.hand_result(c["requested"], 4)
	done.next_step()
	assert_int(int(c["progress"])).is_equal(0)
	assert_bool(bool(c["player"])).is_true()
	## Done for now: nothing more to ask this villager until it runs out.
	var again: VillagerTalkManager = _manager(3, 3)
	again.next_step()
	assert_int(again.step).is_equal(S.NO_OR_NORMAL)
	## Deadline +3 days, then the fin limit clears it.
	Game.quests.move(int(c["limit"]) + 1, Clock.month, Clock.day)
	assert_bool(Q.is_free(c)).is_true()


func test_contest_starts_even_when_turned_down() -> void:
	_offer(4, Q.Type.CONTEST, Q.CONTEST_FISH)
	var m: VillagerTalkManager = _manager(4)
	m.next_step()
	m.choose(0)
	m.choose(1)
	assert_int(int(Game.quests.contests[4]["kind"])).is_equal(Q.CONTEST_FISH)


func test_letter_contest_answers_with_a_ranked_reply() -> void:
	_offer(5, Q.Type.CONTEST, Q.CONTEST_LETTER)
	var m: VillagerTalkManager = _manager(5)
	m.next_step()
	m.choose(0)
	m.choose(0)
	var c: Dictionary = Game.quests.contests[5]
	assert_int(int(c["progress"])).is_equal(2)
	var rng := RandomNumberGenerator.new()
	assert_bool(Game.quests.receive_letter(5, "Hi.", &"apple", "Ann", rng)).is_true()
	assert_int(int(c["progress"])).is_equal(1)
	## Short (0) + a present (+6).
	assert_int(int(c["letter_score"])).is_equal(6)
	var sent: Array[MailData] = []
	var reply: VillagerTalkManager = _manager(5, 7)
	reply.send_mail = func(mail: MailData) -> bool:
		sent.append(mail)
		return true
	reply.next_step()
	if not MailBank.has_bank():
		return
	assert_int(reply.step).is_equal(S.FINISH_LETTER)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].paper_type).is_equal(Q.LETTER_REPLY_PAPER)
	assert_bool(_in(reply.choose(0), 0x1B17, reply.looks)).is_true()
	assert_bool(Q.is_free(c)).is_true()


func test_other_resident_skips_the_excluded_and_the_same_acre() -> void:
	var m: VillagerTalkManager = _manager(0)
	for i: int in 30:
		m.context.rng.seed = i
		var id: StringName = m.other_resident([_id(0), _id(1)], VillagerWalk.block_from_cell(Game.residents.home_of(2)), true)
		assert_bool(id in [_id(3), _id(4), _id(5)]).is_true()


func test_pay_scales_with_money_power() -> void:
	var rng := RandomNumberGenerator.new()
	for i: int in 20:
		rng.seed = i
		var p: int = Q.pay(1000, 0, rng)
		assert_int(p).is_between(900, 1100)
	assert_int(Q.pay_rate(660)).is_equal(660)
	assert_int(Q.pay_rate(250)).is_equal(235)
	assert_int(Q.errand_reward(1)["pay"]).is_equal(0)
	assert_int(Q.errand_reward(9)["pay"]).is_equal(1000)


func test_quests_survive_a_save() -> void:
	_offer(0, Q.Type.ERRAND, Q.ERRAND_REQUEST)
	var a: VillagerTalkManager = _manager(0)
	a.next_step()
	a.choose(0)
	a.choose(0)
	var copy := VillagerQuests.new()
	copy.apply_snapshot(JSON.parse_string(JSON.stringify(Game.quests.to_save())))
	var e: Dictionary = copy.errands[0]
	assert_int(int(e["type"])).is_equal(Q.Type.ERRAND)
	assert_that(e["to"]).is_equal(Game.quests.errands[0]["to"])
	assert_that((e["used_ids"] as Array)[0]).is_equal(_id(0))
	assert_int(typeof((e["used_ids"] as Array)[0])).is_equal(TYPE_STRING_NAME)


func test_runner_walks_the_offer_through_the_disc_messages() -> void:
	if DialogueCatalog.conversation(&"msg_678") == null:
		return
	_offer(0, Q.Type.DELIVERY, Q.DELIVERY_NORMAL)
	var m: VillagerTalkManager = _manager(0)
	var greeting := DialogueData.from_dict({
		"id": "msg_t_greet", "start": "p0", "nodes": {"p0": {"type": "line", "text": "Hello", "cont": true}},
	})
	var runner := DialogueRunner.new()
	runner.talk_manager = m
	runner.start(greeting, m.context, m.state)
	var guard: int = 0
	while not runner.waiting_choice and not runner.done and guard < 40:
		runner.advance()
		guard += 1
	assert_int(runner.choices.size()).is_equal(3)
	runner.choose(0)
	guard = 0
	while not runner.waiting_choice and not runner.done and guard < 40:
		runner.advance()
		guard += 1
	## "Would you deliver them?" → accept / turn down.
	assert_int(runner.choices.size()).is_equal(2)
	runner.choose(0)
	guard = 0
	while not runner.done and guard < 40:
		runner.advance()
		guard += 1
	## "Please do your best" ends on MSGEND.
	assert_bool(runner.done).is_true()
	assert_int(int(Game.quests.deliveries[0]["type"])).is_equal(Q.Type.DELIVERY)
