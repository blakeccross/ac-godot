class_name TestRadioCard
extends GdUnitTestSuite

## Tortimer's exercise card at Morning Aerobics (`RadioCard`), Copper and Tortimer out front,
## and Copper leaving his post while the aerobics run.


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


func _talk(inv: Inventory, card: Dictionary, record: Dictionary, date: Vector3i) -> RadioCard:
	var t := RadioCard.new(inv, card, record, null, date)
	t.context = DialogueContext.new()
	return t


func _cards(inv: Inventory) -> Array[StringName]:
	var out: Array[StringName] = []
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inv.slot_at(i)
		if slot != null and not slot.is_empty():
			out.append(slot.item.item_id)
	return out


func test_card_items_exist() -> void:
	for d: int in RadioCard.DAYS:
		assert_object(ItemCatalog.get_item(RadioCard.card_id(d))).is_not_null()
	assert_str(String(RadioCard.card_id(12))).is_equal("exercise_card_12")


func test_first_visit_hands_over_a_one_stamp_card() -> void:
	var inv := Inventory.new()
	var card: Dictionary = RadioCard.new_state()
	var t := _talk(inv, card, {}, Vector3i(2002, 7, 25))
	assert_int(t.start_msg()).is_equal(RadioCard.MSG_NEW)
	assert_int(inv.count_of(RadioCard.card_id(0))).is_equal(1)
	assert_int(int(card["days"])).is_equal(0)
	assert_int(int(card["day"])).is_equal(25)
	t.current_msg = RadioCard.MSG_NEW
	assert_int(int(t.next_step()["msg"])).is_equal(RadioCard.MSG_NEW_GIVE)
	t.current_msg = RadioCard.MSG_NEW_GIVE
	var give: Dictionary = t.next_step()
	assert_str(String(give["anim"]["give"])).is_equal("exercise_card_00")
	assert_int(int(give["msg"])).is_equal(RadioCard.MSG_NEW_AFTER)


func test_full_pockets_get_no_card_and_the_second_try_says_so() -> void:
	var inv := Inventory.new()
	var apple: ItemData = ItemCatalog.get_item(&"apple")
	for i: int in Inventory.POCKET_SLOTS:
		inv.add_to_empty_slot(apple, 1)
	var record: Dictionary = {}
	var t := _talk(inv, RadioCard.new_state(), record, Vector3i(2002, 7, 25))
	assert_int(t.start_msg()).is_equal(RadioCard.MSG_NEW)
	t.current_msg = RadioCard.MSG_NEW
	assert_int(int(t.next_step()["msg"])).is_equal(RadioCard.MSG_NEW_FULL)
	## The calendar has today now: "What do you say?"
	var again := _talk(inv, RadioCard.new_state(), record, Vector3i(2002, 7, 25))
	assert_int(again.start_msg()).is_equal(RadioCard.MSG_NEW_AGAIN)


func test_one_stamp_a_day() -> void:
	var inv := Inventory.new()
	var card: Dictionary = RadioCard.new_state()
	_talk(inv, card, {}, Vector3i(2002, 7, 25)).start_msg()
	var t := _talk(inv, card, {}, Vector3i(2002, 7, 25))
	assert_int(t.start_msg()).is_equal(RadioCard.MSG_SAME_DAY)
	t.current_msg = RadioCard.MSG_SAME_DAY
	assert_int(int(t.next_step()["msg"])).is_between(RadioCard.MSG_SAME_DAY_AFTER, RadioCard.MSG_SAME_DAY_AFTER + 2)


func test_next_day_stamps_the_card() -> void:
	var inv := Inventory.new()
	var card: Dictionary = RadioCard.new_state()
	_talk(inv, card, {}, Vector3i(2002, 7, 25)).start_msg()
	var t := _talk(inv, card, {}, Vector3i(2002, 7, 27))
	assert_int(t.start_msg()).is_equal(RadioCard.MSG_STAMP)
	assert_int(inv.count_of(RadioCard.card_id(1))).is_equal(1)
	assert_int(inv.count_of(RadioCard.card_id(0))).is_equal(0)
	assert_str(t.context.frees[0]).is_equal("2")
	t.current_msg = RadioCard.MSG_STAMP
	var show: Dictionary = t.next_step()
	assert_str(String(show["anim"]["take"])).is_equal("exercise_card_00")
	t.current_msg = RadioCard.MSG_STAMP_COUNT
	var back: Dictionary = t.next_step()
	assert_str(String(back["anim"]["give"])).is_equal("exercise_card_01")
	assert_int(int(back["msg"])).is_equal(RadioCard.MSG_STAMP_AFTER)


func test_fourteenth_visit_trades_the_card_for_the_radio() -> void:
	var inv := Inventory.new()
	inv.add(ItemCatalog.get_item(RadioCard.card_id(12)), 1)
	var card: Dictionary = {"year": 2002, "month": 8, "day": 20, "days": 12}
	var t := _talk(inv, card, {}, Vector3i(2002, 8, 21))
	assert_int(t.start_msg()).is_equal(RadioCard.MSG_FINISH)
	assert_int(RadioCard.card_count(inv)).is_equal(0)
	assert_int(inv.count_of(RadioCard.radio_id())).is_equal(1)
	assert_int(int(card["days"])).is_equal(RadioCard.DAYS)
	t.current_msg = RadioCard.MSG_FINISH_PRESENT
	var give: Dictionary = t.next_step()
	assert_str(String(give["anim"]["give"])).is_equal(String(RadioCard.radio_id()))
	assert_int(int(give["msg"])).is_equal(RadioCard.MSG_PRIZE)
	assert_str(t.context.frees[1]).is_not_empty()


func test_lost_card_is_remembered_and_replaced() -> void:
	var inv := Inventory.new()
	var card: Dictionary = {"year": 2002, "month": 7, "day": 30, "days": 4}
	var t := _talk(inv, card, {}, Vector3i(2002, 8, 1))
	assert_int(t.start_msg()).is_equal(RadioCard.MSG_LOST)
	assert_str(t.context.frees[0]).is_equal("6")
	assert_int(inv.count_of(RadioCard.card_id(5))).is_equal(1)
	t.current_msg = RadioCard.MSG_LOST
	assert_int(int(t.next_step()["msg"])).is_equal(RadioCard.MSG_LOST_GIVE)


func test_lost_card_on_the_last_stamp_wins_the_radio() -> void:
	var inv := Inventory.new()
	var card: Dictionary = {"year": 2002, "month": 8, "day": 10, "days": 12}
	var t := _talk(inv, card, {}, Vector3i(2002, 8, 11))
	assert_int(t.start_msg()).is_equal(RadioCard.MSG_LOST)
	assert_int(inv.count_of(RadioCard.radio_id())).is_equal(1)
	t.current_msg = RadioCard.MSG_LOST
	assert_int(int(t.next_step()["msg"])).is_equal(RadioCard.MSG_LOST_FINISH)


func test_last_years_card_is_taken_away() -> void:
	var inv := Inventory.new()
	inv.add(ItemCatalog.get_item(RadioCard.card_id(3)), 1)
	var card: Dictionary = {"year": 2001, "month": 8, "day": 10, "days": 3}
	var t := _talk(inv, card, {}, Vector3i(2002, 7, 26))
	assert_int(t.start_msg()).is_equal(RadioCard.MSG_OLD_CARD)
	t.npc_order("npc0", 9, 1)
	t.current_msg = RadioCard.MSG_OLD_CARD
	var take: Dictionary = t.lock_continue()
	assert_str(String(take["anim"]["take"])).is_equal("exercise_card_03")
	assert_int(RadioCard.card_count(inv)).is_equal(0)


func test_too_late_for_a_new_card_from_august_19() -> void:
	var t := _talk(Inventory.new(), RadioCard.new_state(), {}, Vector3i(2002, 8, 19))
	assert_int(t.start_msg()).is_equal(RadioCard.MSG_TOO_LATE)
	var early := _talk(Inventory.new(), RadioCard.new_state(), {}, Vector3i(2002, 8, 18))
	assert_int(early.start_msg()).is_equal(RadioCard.MSG_NEW)


func test_visitors_get_no_card() -> void:
	var inv := Inventory.new()
	var t := _talk(inv, RadioCard.new_state(), {}, Vector3i(2002, 7, 25))
	t.foreigner = true
	assert_int(t.start_msg()).is_equal(RadioCard.MSG_FOREIGNER)
	assert_int(RadioCard.card_count(inv)).is_equal(0)


func test_card_record_is_saved_with_the_player() -> void:
	Game.radio_card = {"year": 2002, "month": 7, "day": 28, "days": 3}
	var saved: Dictionary = Game.to_save()
	Game.reset_session()
	assert_int(int(Game.radio_card["days"])).is_equal(0)
	Game.apply_snapshot(saved)
	assert_int(int(Game.radio_card["days"])).is_equal(3)
	assert_bool(PlayerRoster.PRIVATE_KEYS.has("radio_card")).is_true()


func test_copper_leaves_his_post_for_the_aerobics() -> void:
	var copper_script: GDScript = load("res://scenes/world/copper.gd")
	assert_bool(copper_script.aerobics_running()).is_false()
	Game.events.force(&"morning_aerobics")
	Game.events.sync(EventCalendar.make_date(2002, 7, 26, 6))
	assert_bool(copper_script.aerobics_running()).is_true()


func test_aerobics_map_puts_copper_and_tortimer_out_front() -> void:
	var leaders: Dictionary = load("res://scripts/systems/events/festival_presenter.gd").AEROBICS_LEADERS
	assert_str(String(leaders["SP_NPC_EV_TAISOU_0"])).is_equal("plc")
	assert_str(String(leaders["SP_NPC_SONCHO_D078"])).is_equal("ttl")
