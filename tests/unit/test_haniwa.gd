class_name TestHaniwa
extends GdUnitTestSuite

## The house gyroids (`ac_haniwa`): placement, what they say, how they dance, the save walk.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func _cell_of(data: WorldData, id: StringName) -> Vector2i:
	for b: BuildingPlacement in data.buildings:
		if b != null and b.id == id:
			return b.cell
	for o: ObjectPlacement in data.objects:
		if o != null and o.id == id:
			return o.cell
	return Vector2i(-99, -99)


func test_generated_town_puts_a_gyroid_two_units_south_of_every_house() -> void:
	var data: WorldData = WorldGenerator.generate(4242)
	## West anchors are the house ut; east anchors sit one cell west of it (`nw_off (-1, 0)`).
	var expect: Dictionary = {
		&"player_haniwa": _cell_of(data, &"player_house") + Vector2i(0, 2),
		&"player_haniwa_1": _cell_of(data, &"player_house_1") + Vector2i(1, 2),
		&"player_haniwa_2": _cell_of(data, &"player_house_2") + Vector2i(0, 2),
		&"player_haniwa_3": _cell_of(data, &"player_house_3") + Vector2i(1, 2),
	}
	for id: StringName in expect:
		assert_that(_cell_of(data, id)).is_equal(expect[id])
	var kinds: int = 0
	for o: ObjectPlacement in data.objects:
		if o != null and o.kind == &"haniwa":
			kinds += 1
	assert_int(kinds).is_equal(4)


func test_gyroids_sit_on_the_house_row_like_the_fg_template() -> void:
	## FG house acre: HOUSE0 ut (3,3) / HANIWA0 ut (3,5), HOUSE1 (12,3) / HANIWA1 (12,5).
	var data: WorldData = WorldGenerator.generate(99)
	var west: Vector2i = _cell_of(data, &"player_haniwa")
	var east: Vector2i = _cell_of(data, &"player_haniwa_1")
	assert_int(east.x - west.x).is_equal(9)
	assert_int(east.y).is_equal(west.y)
	assert_int(_cell_of(data, &"player_haniwa_2").y - west.y).is_equal(7)


func test_house_idx_comes_from_the_placement_id() -> void:
	assert_int(PlayerHouse.plot_of("player_haniwa")).is_equal(0)
	assert_int(PlayerHouse.plot_of("player_haniwa_1")).is_equal(1)
	assert_int(PlayerHouse.plot_of("player_mailbox_3")).is_equal(3)
	assert_str(PlayerHouse.plot_building(0)).is_equal("player_house")
	assert_str(PlayerHouse.plot_building(2)).is_equal("player_house_2")


func test_decide_msg_follows_the_decomp_order() -> void:
	assert_int(HaniwaTalk.decide_msg(false, false, false, false, 0, 0)).is_equal(HaniwaTalk.Msg.NO_OWNER)
	assert_int(HaniwaTalk.decide_msg(true, false, false, false, 0, 0)).is_equal(HaniwaTalk.Msg.OTHER_OWNER)
	## First job, never saved, no villager friends yet.
	assert_int(HaniwaTalk.decide_msg(true, true, false, true, 0, 0)).is_equal(HaniwaTalk.Msg.NEED_FRIEND)
	## Any one of those lifted opens the menu.
	assert_int(HaniwaTalk.decide_msg(true, true, true, true, 0, 0)).is_equal(HaniwaTalk.Msg.NORMAL)
	assert_int(HaniwaTalk.decide_msg(true, true, false, false, 0, 0)).is_equal(HaniwaTalk.Msg.NORMAL)
	assert_int(HaniwaTalk.decide_msg(true, true, false, true, 1, 0)).is_equal(HaniwaTalk.Msg.NORMAL)
	assert_int(HaniwaTalk.decide_msg(true, true, true, false, 0, 500)).is_equal(HaniwaTalk.Msg.PROCEEDS)
	assert_int(HaniwaTalk.msg_no(HaniwaTalk.Msg.NO_OWNER)).is_equal(2356)
	assert_int(HaniwaTalk.msg_no(HaniwaTalk.Msg.NORMAL)).is_equal(2341)


func test_anim_speed_table() -> void:
	var a := HaniwaTalk.Action
	## Owner: bob at 0.3, dance at 0.45 when near, 0.3 in any conversation.
	assert_float(HaniwaTalk.anim_speed(a.WAIT, true, true, 0.0)).is_equal(0.3)
	assert_float(HaniwaTalk.anim_speed(a.DANCE, true, true, 0.3)).is_equal(0.45)
	assert_float(HaniwaTalk.anim_speed(a.TALK_WITH_MASTER, true, true, 0.45)).is_equal(0.3)
	## Someone else's house: slow.
	assert_float(HaniwaTalk.anim_speed(a.DANCE, true, false, 0.0)).is_equal(0.1)
	## Empty plot: never started stays still; after a talk it winds down to 0.075.
	assert_float(HaniwaTalk.anim_speed(a.WAIT, false, false, 0.0)).is_equal(0.0)
	assert_float(HaniwaTalk.anim_speed(a.DANCE, false, false, 0.3)).is_equal(0.075)
	assert_bool(HaniwaTalk.stops_at_end(a.DANCE, false, 0.1)).is_true()
	assert_bool(HaniwaTalk.stops_at_end(a.DANCE, false, 0.2)).is_false()
	assert_bool(HaniwaTalk.stops_at_end(a.TALK_END_WAIT, false, 0.0)).is_false()
	assert_bool(HaniwaTalk.stops_at_end(a.DANCE, true, 0.0)).is_false()


func test_speed_chases_up_faster_than_down() -> void:
	assert_float(HaniwaTalk.chase_speed(0.0, 0.45)).is_equal_approx(0.05, 0.0001)
	assert_float(HaniwaTalk.chase_speed(0.45, 0.3)).is_equal_approx(0.435, 0.0001)
	assert_float(HaniwaTalk.chase_speed(0.29, 0.3, 2.0)).is_equal_approx(0.3, 0.0001)


func test_empty_plot_looks_front_and_owner_tracks_the_player() -> void:
	var front: float = HaniwaTalk.short_to_rad(8000)
	assert_float(HaniwaTalk.look_yaw(0, false, HaniwaTalk.Action.WAIT, 1.0)).is_equal_approx(front, 0.0001)
	assert_float(HaniwaTalk.look_yaw(1, false, HaniwaTalk.Action.WAIT, 1.0)).is_equal_approx(-front, 0.0001)
	assert_float(HaniwaTalk.look_yaw(1, false, HaniwaTalk.Action.TALK_END_WAIT, 1.0)).is_equal(1.0)
	assert_float(HaniwaTalk.look_yaw(2, true, HaniwaTalk.Action.WAIT, 1.0)).is_equal(1.0)


func test_chase_yaw_turns_0x600_per_30hz_frame() -> void:
	var step: float = HaniwaTalk.short_to_rad(0x0600)
	assert_float(HaniwaTalk.chase_yaw(0.0, 1.0, 1.0 / 30.0)).is_equal_approx(step, 0.0001)
	assert_float(HaniwaTalk.chase_yaw(0.0, -1.0, 1.0 / 30.0)).is_equal_approx(-step, 0.0001)
	assert_float(HaniwaTalk.chase_yaw(0.9, 1.0, 1.0 / 30.0)).is_equal(1.0)


func test_door_walk_stage_flips_past_chk_pos() -> void:
	## West plot: stage 1 once the player is 35 GX or more east of the gyroid.
	assert_int(HaniwaTalk.door_stage(0, Vector2(0.0, 0.0))).is_equal(0)
	assert_int(HaniwaTalk.door_stage(0, Vector2(36.0, 30.0))).is_equal(1)
	## East plot mirrors it.
	assert_int(HaniwaTalk.door_stage(1, Vector2(-36.0, 30.0))).is_equal(1)
	assert_int(HaniwaTalk.door_stage(1, Vector2(36.0, 30.0))).is_equal(0)
	assert_that(HaniwaTalk.door_goal_gx(0, 1)).is_equal(Vector2(50.0, -26.0))
	assert_that(HaniwaTalk.door_goal_gx(3, 0)).is_equal(Vector2(-38.0, 40.0))


func test_friend_count_counts_villagers_the_player_has_talked_to() -> void:
	var book := RelationshipBook.new()
	assert_int(book.friend_count()).is_equal(0)
	book.get_or_create(&"filbert")
	assert_int(book.friend_count()).is_equal(0)
	book.record_talk(&"filbert", "2026-01-01")
	assert_int(book.friend_count()).is_equal(1)


func test_house_has_saved_round_trips() -> void:
	var house := House.new()
	house.has_saved = true
	var back := House.new()
	back.apply_snapshot(house.to_save())
	assert_bool(back.has_saved).is_true()
	back.apply_snapshot({})
	assert_bool(back.has_saved).is_true()


func _gotos(data: DialogueData, node: StringName) -> Array:
	var out: Array = []
	for opt: Dictionary in data.node(node).get("options", []):
		out.append(str(opt.get("goto", "")))
	return out


func _run_to_choice(runner: DialogueRunner) -> void:
	var guard := 0
	while not runner.waiting_choice and not runner.done and guard < 20:
		runner.advance()
		guard += 1


func test_graph_wires_every_owner_choice() -> void:
	var data: DialogueData = HaniwaTalk.graph()
	if data == null:
		## ROM banks not converted on this machine.
		return
	## Save / Store an item / Other things / Never mind.
	assert_array(_gotos(data, &"m2341_choice")).contains_exactly(["m2351_p0", "", "m2353_p0", "m2342_p0"])
	var store: Dictionary = (data.node(&"m2341_choice").get("options", []) as Array)[1]
	assert_str(str((store["events"] as Array)[0]["menu"])).is_equal(HaniwaTalk.MENU_ENTRUST)
	## Other things: About the door / Set message / Go back / Never mind.
	assert_array(_gotos(data, &"m2353_choice")).contains_exactly(["m2354_p0", "", "m2355_p0", "m2342_p0"])
	## Door: Post pattern (menu) / Remove pattern / Maybe not.
	assert_array(_gotos(data, &"m2354_choice")).contains_exactly(["", "m2343_p0", "m2343_p0"])
	var remove: Dictionary = (data.node(&"m2354_choice").get("options", []) as Array)[1]
	assert_str(str((remove["events"] as Array)[0]["op"])).is_equal(HaniwaTalk.EVENT_DOOR_REMOVE)
	## Visitor: Check items → branch on held items; Never mind → 0x92A.
	assert_array(_gotos(data, &"m2345_choice")).contains_exactly(["guest_check", "m2346_p0"])


func test_graph_runs_to_the_save_event() -> void:
	var data: DialogueData = HaniwaTalk.graph()
	if data == null:
		return
	var runner := DialogueRunner.new()
	var fired: Array[String] = []
	runner.event_fired.connect(func(e: Dictionary) -> void: fired.append(str(e.get("op", ""))))
	runner.start(data, DialogueContext.new())
	_run_to_choice(runner)
	runner.choose(0)  ## Save
	_run_to_choice(runner)
	runner.choose(0)  ## That's right!
	assert_array(fired).contains([HaniwaTalk.EVENT_SAVE])
	assert_str(runner.line).contains("enter the house")


func test_graph_resumes_and_hands_over_proceeds() -> void:
	var data: DialogueData = HaniwaTalk.graph()
	if data == null:
		return
	var ctx := DialogueContext.new()
	ctx.set_var(HaniwaTalk.VAR_START, HaniwaTalk.START_RESUME)
	var runner := DialogueRunner.new()
	runner.start(data, ctx)
	assert_str(runner.line).contains("Request processed")
	## Proceeds that did not fit: the "make space" line, then the talk ends.
	ctx = DialogueContext.new()
	ctx.set_var(HaniwaTalk.VAR_START, HaniwaTalk.START_PROCEEDS)
	ctx.set_var(HaniwaTalk.VAR_HANDOVER, "no")
	ctx.frees = PackedStringArray(["120000", "2"])
	runner = DialogueRunner.new()
	runner.start(data, ctx)
	var lines: Array[String] = []
	var guard := 0
	while not runner.done and guard < 20:
		lines.append(runner.line)
		runner.advance()
		guard += 1
	assert_str("\n".join(lines)).contains("120000 Bells")
	assert_str("\n".join(lines)).contains("appalling amount of cash")


func test_visitor_with_nothing_held_gets_the_apology() -> void:
	var data: DialogueData = HaniwaTalk.graph()
	if data == null:
		return
	var ctx := DialogueContext.new()
	ctx.set_var(HaniwaTalk.VAR_START, HaniwaTalk.START_GUEST)
	ctx.set_var(HaniwaTalk.VAR_HAS_ITEMS, "no")
	ctx.mail_text = "Thanks for coming!"
	ctx.frees = PackedStringArray(["", "", "Owner"])
	var runner := DialogueRunner.new()
	runner.start(data, ctx)
	assert_str(runner.line).contains("Owner")
	runner.advance()
	assert_str(runner.line).contains("Thanks for coming!")
	_run_to_choice(runner)
	runner.choose(0)  ## Check items
	assert_str(runner.line).contains("no articles")


func test_scene_builds_and_offers_talk() -> void:
	var node: Node = auto_free(load("res://scenes/world/haniwa.tscn").instantiate())
	node.name = "player_haniwa_1"
	add_child(node)
	assert_int(int(node.get("house_idx"))).is_equal(1)
	var verbs: Array[Interaction] = node.call("get_interactions", InteractionContext.new())
	assert_int(verbs.size()).is_equal(1)
	assert_that(verbs[0].id).is_equal(Interaction.TALK)


## --- the gyroid's consignment (`HaniwaStore`) -----------------------------------------


func _stocked_house() -> House:
	var house := House.new()
	HaniwaStore.ensure(house)
	return house


func test_owner_consigns_and_takes_back() -> void:
	var inv: Inventory = Game.inventory
	var apple: ItemData = ItemCatalog.get_item(&"apple")
	inv.add(apple, 1)
	var house: House = _stocked_house()
	assert_bool(HaniwaStore.entrust(house, 2, inv, 0, HaniwaStore.Exchange.SALE, 500)).is_true()
	assert_int(inv.count_of(&"apple")).is_equal(0)
	assert_that(HaniwaStore.item_at(house, 2)["item"]).is_equal(&"apple")
	assert_int(int(HaniwaStore.item_at(house, 2)["price"])).is_equal(500)
	assert_str(HaniwaStore.status_line(house, 2, true)).is_equal("It's 500 Bells")
	## Only an empty slot takes an item.
	inv.add(apple, 1)
	assert_bool(HaniwaStore.entrust(house, 2, inv, 0, HaniwaStore.Exchange.FREE)).is_false()
	## A sale at 0 is free; display only drops the price.
	HaniwaStore.set_terms(house, 2, HaniwaStore.Exchange.SALE, 0)
	assert_int(int(HaniwaStore.item_at(house, 2)["exchange"])).is_equal(HaniwaStore.Exchange.FREE)
	assert_str(HaniwaStore.status_line(house, 2, true)).is_equal("That's free")
	assert_str(HaniwaStore.status_line(house, 2, false)).is_equal("Give Away")
	assert_bool(HaniwaStore.take_back(house, 2, inv)).is_true()
	assert_int(inv.count_of(&"apple")).is_equal(2)
	assert_bool(HaniwaStore.has_items(house)).is_false()


func test_price_steps_by_digit_and_clamps() -> void:
	assert_int(HaniwaStore.step_price(0, 0, 1)).is_equal(10000)
	assert_int(HaniwaStore.step_price(0, 4, -1)).is_equal(0)
	assert_int(HaniwaStore.step_price(99990, 3, 1)).is_equal(99999)
	assert_int(HaniwaStore.step_price(150, 2, -1)).is_equal(50)


func test_visitor_pays_from_wallet_then_smallest_bags() -> void:
	var inv: Inventory = Game.inventory
	var house: House = _stocked_house()
	house.haniwa_items[0] = {"item": &"apple", "count": 1, "cond": 0,
		"exchange": HaniwaStore.Exchange.SALE, "price": 1500}
	house.haniwa_items[1] = {"item": &"apple", "count": 1, "cond": 0,
		"exchange": HaniwaStore.Exchange.DISPLAY, "price": 0}
	inv.set_wallet(300)
	assert_that(HaniwaStore.buy(house, 0, inv)).is_equal(&"no_money")
	inv.add(ItemCatalog.get_item(&"money_1000"), 1)
	inv.add(ItemCatalog.get_item(&"money_100"), 3)
	## 300 wallet + 3×100 + 1000 = 1600 ≥ 1500: wallet −1500 → −1200, +100 +100 +100 → −900,
	## +1000 → 100.
	assert_that(HaniwaStore.buy(house, 0, inv)).is_equal(&"ok")
	assert_int(inv.wallet).is_equal(100)
	assert_int(inv.count_of(&"money_100")).is_equal(0)
	assert_int(inv.count_of(&"money_1000")).is_equal(0)
	assert_int(inv.count_of(&"apple")).is_equal(1)
	assert_int(house.haniwa_bells).is_equal(1500)
	assert_that(HaniwaStore.buy(house, 1, inv)).is_equal(&"display")


func test_proceeds_fill_the_wallet_then_overflow_into_bags() -> void:
	var inv: Inventory = Game.inventory
	var house: House = _stocked_house()
	inv.set_wallet(1000)
	house.haniwa_bells = 2000
	assert_bool(bool(HaniwaStore.collect_proceeds(house, inv)["ok"])).is_true()
	assert_int(inv.wallet).is_equal(3000)
	assert_int(house.haniwa_bells).is_equal(0)
	## 99 000 + 40 000 = 139 000: (139 000 − 99 999) / 30 000 + 1 = 2 bags → wallet 79 000.
	inv.set_wallet(99000)
	house.haniwa_bells = 40000
	var got: Dictionary = HaniwaStore.collect_proceeds(house, inv)
	assert_bool(bool(got["ok"])).is_true()
	assert_int(inv.count_of(&"money_30000")).is_equal(2)
	assert_int(inv.wallet).is_equal(79000)
	## No room for the bags: nothing moves, and the talk asks for that many slots.
	for i: int in Inventory.POCKET_SLOTS:
		if inv.slot_at(i).is_empty():
			inv.slot_at(i).set_stack(&"apple", 1, InventoryItem.Condition.NORMAL)
	inv.set_wallet(99000)
	house.haniwa_bells = 40000
	got = HaniwaStore.collect_proceeds(house, inv)
	assert_bool(bool(got["ok"])).is_false()
	assert_int(int(got["bags"])).is_equal(2)
	assert_int(house.haniwa_bells).is_equal(40000)


func test_gyroid_data_round_trips_with_the_house() -> void:
	var house: House = _stocked_house()
	house.haniwa_items[3] = {"item": &"apple", "count": 1, "cond": 0,
		"exchange": HaniwaStore.Exchange.SALE, "price": 250}
	house.haniwa_message = "Back soon!"
	house.haniwa_bells = 777
	house.door_original = 5
	var back := House.new()
	back.apply_snapshot(house.to_save())
	assert_that(HaniwaStore.item_at(back, 3)["item"]).is_equal(&"apple")
	assert_int(int(HaniwaStore.item_at(back, 3)["price"])).is_equal(250)
	assert_str(back.haniwa_message).is_equal("Back soon!")
	assert_int(back.haniwa_bells).is_equal(777)
	assert_int(back.door_original).is_equal(5)


func test_default_message_is_the_rom_lines() -> void:
	var msg: String = HaniwaStore.default_message()
	if msg == "":
		return
	assert_str(msg).is_equal(
		"Thanks for coming!\nSorry I'm not in right now,\nbut please come in and\nmake yourself at home."
	)
	## An unset message falls back to it.
	assert_str(HaniwaStore.message(House.new())).is_equal(msg)
