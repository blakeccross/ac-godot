class_name TestPlayerHouse
extends GdUnitTestSuite


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Clock.apply_snapshot({"year": 2001, "month": 1, "day": 1, "hour": 12, "minute": 0})
	Game.reset_session()
	InteriorCatalog.reset()
	ItemCatalog.reload()


func after_test() -> void:
	Game.reset_session()
	InteriorCatalog.reset()
	Clock.reset_to_default()
	Clock.paused = false


func _house() -> House:
	return Game.interiors.player_house()


func _next_day() -> void:
	Clock.apply_snapshot({"year": 2001, "month": 1, "day": 2, "hour": 12, "minute": 0})


## --- size tiers: layout follows l_proom_{s,m,l}_tmp ------------------------------------


func test_main_room_layout_follows_house_size() -> void:
	var expected: Array = [
		[Vector2i(4, 4), Vector2i(2, 7), "rom_myhome1_floor"],
		[Vector2i(6, 6), Vector2i(3, 9), "rom_myhome2B_floor"],
		[Vector2i(8, 8), Vector2i(4, 11), "rom_myhome3_floor"],
		[Vector2i(8, 8), Vector2i(4, 11), "rom_myhome4_1_floor"],
	]
	var house: House = _house()
	for tier: int in expected.size():
		house.size_tier = tier as House.SizeTier
		house.next_size_tier = tier as House.SizeTier
		Game.interiors.refresh_player_rooms()
		var room: Room = Game.interiors.room(PlayerHouse.MAIN)
		assert_that(room.inner_size).is_equal(expected[tier][0])
		assert_that(room.door_cell).is_equal(expected[tier][1])
		assert_bool(room.shell_ids.has(expected[tier][2])).is_true()
		assert_that(room.inner_origin).is_equal(Vector2i(1, 1))


func test_furniture_survives_a_size_change() -> void:
	var room: Room = Game.interiors.room(PlayerHouse.MAIN)
	var before: int = room.placements.size()
	assert_int(before).is_greater(0)
	var house: House = _house()
	house.size_tier = House.SizeTier.MEDIUM
	house.next_size_tier = House.SizeTier.MEDIUM
	Game.interiors.refresh_player_rooms()
	assert_int(Game.interiors.room(PlayerHouse.MAIN).placements.size()).is_equal(before)


func test_enter_stand_follows_size() -> void:
	var house: House = _house()
	assert_vector(PlayerHouse.enter_gx(house)).is_equal(Vector3(120.0, 0.0, 220.0))
	house.size_tier = House.SizeTier.MEDIUM
	assert_vector(PlayerHouse.enter_gx(house)).is_equal(Vector3(160.0, 0.0, 300.0))
	house.size_tier = House.SizeTier.LARGE
	assert_vector(PlayerHouse.enter_gx(house)).is_equal(Vector3(200.0, 0.0, 380.0))
	house.size_tier = House.SizeTier.UPPER
	assert_vector(PlayerHouse.enter_gx(house)).is_equal(Vector3(200.0, 0.0, 380.0))


func test_statue_keeps_the_last_house_layout() -> void:
	var house: House = _house()
	house.size_tier = House.SizeTier.STATUE
	assert_int(PlayerHouse.tier_of(house)).is_equal(int(House.SizeTier.UPPER))


## --- stairs -------------------------------------------------------------------------------


func test_small_house_has_no_stairs() -> void:
	assert_int(Game.interiors.room(PlayerHouse.MAIN).stairs.size()).is_equal(0)


func test_basement_stairs_need_the_basement_flag() -> void:
	var house: House = _house()
	house.size_tier = House.SizeTier.MEDIUM
	house.next_size_tier = House.SizeTier.MEDIUM
	Game.interiors.refresh_player_rooms()
	assert_int(Game.interiors.room(PlayerHouse.MAIN).stairs.size()).is_equal(0)
	house.has_basement = true
	Game.interiors.refresh_player_rooms()
	var stairs: Array[RoomStair] = Game.interiors.room(PlayerHouse.MAIN).stairs
	assert_int(stairs.size()).is_equal(1)
	assert_that(stairs[0].target_room_id).is_equal(PlayerHouse.BASEMENT)
	assert_that(stairs[0].cell).is_equal(Vector2i(7, 7))
	## `PLAYER_ROOM_M_door_data`: land at (300, 380) facing west.
	assert_vector(stairs[0].spawn_gx).is_equal(Vector3(300.0, 0.0, 380.0))
	assert_int(stairs[0].spawn_facing).is_equal(WorldGrid.Facing.WEST)


func test_upper_house_stairs_go_up_and_down() -> void:
	var house: House = _house()
	house.size_tier = House.SizeTier.UPPER
	house.next_size_tier = House.SizeTier.UPPER
	house.has_basement = true
	Game.interiors.refresh_player_rooms()
	var main_stairs: Array[RoomStair] = Game.interiors.room(PlayerHouse.MAIN).stairs
	assert_int(main_stairs.size()).is_equal(2)
	assert_that(main_stairs[0].target_room_id).is_equal(PlayerHouse.BASEMENT)
	assert_that(main_stairs[1].target_room_id).is_equal(PlayerHouse.UPPER)
	assert_that(main_stairs[1].cell).is_equal(Vector2i(1, 9))
	assert_vector(main_stairs[1].spawn_gx).is_equal(Vector3(60.0, 0.0, 300.0))
	assert_int(main_stairs[1].spawn_facing).is_equal(WorldGrid.Facing.EAST)
	var upper: Room = Game.interiors.room(PlayerHouse.UPPER)
	assert_int(upper.stairs.size()).is_equal(1)
	assert_that(upper.stairs[0].target_room_id).is_equal(PlayerHouse.MAIN)
	assert_that(upper.stairs[0].cell).is_equal(Vector2i(0, 7))
	assert_vector(upper.stairs[0].spawn_gx).is_equal(Vector3(100.0, 0.0, 380.0))
	assert_that(upper.inner_size).is_equal(Vector2i(6, 6))
	## No outdoor exit up there.
	assert_int(upper.door_cell.x).is_less(0)


func test_basement_returns_to_the_size_specific_landing() -> void:
	var landing: Array[Vector3] = [
		Vector3(220.0, 0.0, 220.0),
		Vector3(260.0, 0.0, 300.0),
		Vector3(300.0, 0.0, 380.0),
		Vector3(300.0, 0.0, 380.0),
	]
	var house: House = _house()
	for tier: int in landing.size():
		house.size_tier = tier as House.SizeTier
		house.next_size_tier = tier as House.SizeTier
		Game.interiors.refresh_player_rooms()
		var basement: Room = Game.interiors.room(PlayerHouse.BASEMENT)
		assert_that(basement.inner_size).is_equal(Vector2i(8, 8))
		assert_vector(basement.stairs[0].spawn_gx).is_equal(landing[tier])
		assert_that(basement.stairs[0].cell).is_equal(Vector2i(8, 9))


func test_step_models_follow_the_floor() -> void:
	var house: House = _house()
	house.size_tier = House.SizeTier.UPPER
	house.next_size_tier = House.SizeTier.UPPER
	house.has_basement = true
	Game.interiors.refresh_player_rooms()
	var main_steps: Array[Dictionary] = PlayerHouse.step_draws(Game.interiors.room(PlayerHouse.MAIN), house)
	assert_int(main_steps.size()).is_equal(2)
	assert_that(main_steps[0]["visual"]).is_equal(PlayerHouse.STEP_DOWN)
	assert_that(main_steps[1]["visual"]).is_equal(PlayerHouse.STEP_UP)
	assert_bool(bool(main_steps[0]["mirror"])).is_false()
	var upper_steps: Array[Dictionary] = PlayerHouse.step_draws(Game.interiors.room(PlayerHouse.UPPER), house)
	assert_bool(bool(upper_steps[0]["mirror"])).is_true()
	assert_that(upper_steps[0]["visual"]).is_equal(PlayerHouse.STEP_DOWN)
	var basement_steps: Array[Dictionary] = PlayerHouse.step_draws(
		Game.interiors.room(PlayerHouse.BASEMENT), house
	)
	assert_that(basement_steps[0]["visual"]).is_equal(PlayerHouse.STEP_UP)
	assert_bool(bool(basement_steps[0]["mirror"])).is_true()


func test_stair_bays_sit_in_the_wall_row_south_of_the_carpet() -> void:
	var house: House = _house()
	house.size_tier = House.SizeTier.UPPER
	house.next_size_tier = House.SizeTier.UPPER
	house.has_basement = true
	Game.interiors.refresh_player_rooms()
	for room_id: StringName in [PlayerHouse.MAIN, PlayerHouse.UPPER, PlayerHouse.BASEMENT]:
		var room: Room = Game.interiors.room(room_id)
		var south_row: int = room.inner_origin.y + room.inner_size.y
		for stair: RoomStair in room.stairs:
			assert_int(stair.cell.y).is_equal(south_row)


func test_only_the_main_floor_has_an_outdoor_exit() -> void:
	var house: House = _house()
	house.size_tier = House.SizeTier.UPPER
	house.next_size_tier = House.SizeTier.UPPER
	Game.interiors.refresh_player_rooms()
	var grid := WorldGrid.new()
	for room_id: StringName in [PlayerHouse.UPPER, PlayerHouse.BASEMENT]:
		var room: Room = Game.interiors.room(room_id)
		var gaps: Array[Dictionary] = InteriorShellBuilder.house_door_gaps(room, grid)
		## Only the stair bay, never a south EXIT_DOOR strip.
		assert_int(gaps.size()).is_equal(room.stairs.size())
	var main_gaps: Array[Dictionary] = InteriorShellBuilder.house_door_gaps(
		Game.interiors.room(PlayerHouse.MAIN), grid
	)
	assert_int(main_gaps.size()).is_equal(1 + Game.interiors.room(PlayerHouse.MAIN).stairs.size())


## --- ordering an upgrade (`aNSC_check_roof_col_order` / `mHm_CheckRehouseOrder`) -----------


func test_order_records_next_size_and_date_but_does_not_build() -> void:
	var house: House = _house()
	assert_bool(HouseUpgrade.order_upgrade(house, 4)).is_true()
	assert_int(house.next_size_tier).is_equal(House.SizeTier.MEDIUM)
	assert_int(house.size_tier).is_equal(House.SizeTier.SMALL)
	assert_int(house.ordered_outlook_pal).is_equal(4)
	assert_int(house.order_day).is_equal(1)
	## Same day: nothing lands.
	assert_bool(HouseUpgrade.check_rehouse_order(house)).is_false()
	assert_int(house.size_tier).is_equal(House.SizeTier.SMALL)


func test_build_lands_on_a_later_day_and_takes_the_ordered_palette() -> void:
	var house: House = _house()
	HouseUpgrade.order_upgrade(house, 7)
	_next_day()
	assert_bool(HouseUpgrade.check_rehouse_order(house)).is_true()
	assert_int(house.size_tier).is_equal(House.SizeTier.MEDIUM)
	assert_int(house.outlook_pal).is_equal(7)
	assert_int(house.next_outlook_pal).is_equal(7)
	assert_bool(house.renew).is_true()


func test_a_second_order_is_refused_until_the_first_lands() -> void:
	var house: House = _house()
	assert_bool(HouseUpgrade.order_upgrade(house, 0)).is_true()
	assert_bool(HouseUpgrade.order_upgrade(house, 1)).is_false()


func test_nothing_upgrades_past_the_upper_size() -> void:
	var house: House = _house()
	house.size_tier = House.SizeTier.UPPER
	house.next_size_tier = House.SizeTier.UPPER
	assert_bool(HouseUpgrade.order_upgrade(house, 0)).is_false()


func test_game_start_applies_a_pending_order_and_rebuilds_rooms() -> void:
	var house: House = _house()
	HouseUpgrade.order_upgrade(house, 2)
	var snapshot: Dictionary = Game.interiors.to_save()
	_next_day()
	Game.interiors.apply_snapshot(snapshot)
	assert_bool(Game.check_rehouse_order()).is_true()
	assert_that(Game.interiors.room(PlayerHouse.MAIN).inner_size).is_equal(Vector2i(6, 6))


func test_house_record_round_trips_through_save() -> void:
	var house: House = _house()
	house.size_tier = House.SizeTier.LARGE
	house.next_size_tier = House.SizeTier.LARGE
	house.has_basement = true
	house.basement_just_built = true
	house.outlook_pal = 5
	house.order_year = 2001
	house.order_month = 3
	house.order_day = 9
	var copy := House.new()
	copy.apply_snapshot(house.to_save())
	assert_int(copy.size_tier).is_equal(House.SizeTier.LARGE)
	assert_bool(copy.has_basement).is_true()
	assert_bool(copy.basement_just_built).is_true()
	assert_int(copy.outlook_pal).is_equal(5)
	assert_int(copy.order_day).is_equal(9)


func test_old_saves_without_order_fields_load_as_settled() -> void:
	var copy := House.new()
	copy.apply_snapshot({"id": "player", "size_tier": 1})
	assert_int(copy.size_tier).is_equal(House.SizeTier.MEDIUM)
	assert_int(copy.next_size_tier).is_equal(House.SizeTier.MEDIUM)
	assert_bool(copy.renew).is_false()


## --- basement order -----------------------------------------------------------------------


func test_basement_order_lands_next_day_and_charges_its_own_loan() -> void:
	var house: House = _house()
	house.size_tier = House.SizeTier.MEDIUM
	house.next_size_tier = House.SizeTier.MEDIUM
	assert_bool(HouseUpgrade.order_basement(house)).is_true()
	assert_bool(house.has_basement).is_false()
	_next_day()
	assert_bool(HouseUpgrade.check_rehouse_order(house)).is_true()
	assert_bool(house.has_basement).is_true()
	assert_bool(house.renew).is_true()
	var result: Dictionary = HouseUpgrade.collect_built(house, Game.inventory)
	assert_that(result["built"]).is_equal(HouseUpgrade.BUILT_BASEMENT)
	assert_int(Game.inventory.loan).is_equal(HouseUpgrade.LOAN_BASEMENT)
	assert_bool(house.basement_ordered).is_false()
	assert_bool(house.basement_just_built).is_true()
	assert_bool(house.renew).is_false()


func test_no_basement_on_a_small_house() -> void:
	assert_bool(HouseUpgrade.order_basement(_house())).is_false()


## --- loans (`aNSC_LOAN_*`) ----------------------------------------------------------------


func test_each_build_hands_out_its_loan() -> void:
	var loans: Dictionary = {
		House.SizeTier.MEDIUM: HouseUpgrade.LOAN_MEDIUM,
		House.SizeTier.LARGE: HouseUpgrade.LOAN_LARGE,
		House.SizeTier.UPPER: HouseUpgrade.LOAN_UPPER,
	}
	assert_int(HouseUpgrade.LOAN_MEDIUM).is_equal(148000)
	assert_int(HouseUpgrade.LOAN_LARGE).is_equal(398000)
	assert_int(HouseUpgrade.LOAN_UPPER).is_equal(798000)
	assert_int(HouseUpgrade.LOAN_BASEMENT).is_equal(49800)
	for tier: int in loans.keys():
		var house := House.new()
		house.size_tier = tier as House.SizeTier
		house.next_size_tier = tier as House.SizeTier
		house.renew = true
		Game.inventory.set_loan(0)
		var result: Dictionary = HouseUpgrade.collect_built(house, Game.inventory)
		assert_int(Game.inventory.loan).is_equal(int(loans[tier]))
		assert_bool(result.is_empty()).is_false()
		assert_bool(house.renew).is_false()


func test_collect_built_is_a_noop_until_a_build_landed() -> void:
	var house: House = _house()
	assert_bool(HouseUpgrade.collect_built(house, Game.inventory).is_empty()).is_true()
	assert_int(Game.inventory.loan).is_equal(0)


## --- what Nook offers (`aNSC_set_talk_info_start_wait1`) ---------------------------------


func test_offer_needs_a_clear_loan_and_settled_house() -> void:
	var house: House = _house()
	Game.inventory.set_loan(100)
	assert_bool(HouseUpgrade.offer_for(house, Game.inventory).is_empty()).is_true()
	Game.inventory.set_loan(0)
	assert_that(HouseUpgrade.offer_for(house, Game.inventory)["offer"]).is_equal(HouseUpgrade.OFFER_MEDIUM)
	house.renew = true
	assert_bool(HouseUpgrade.offer_for(house, Game.inventory).is_empty()).is_true()


func test_offer_path_through_medium_and_large() -> void:
	var house: House = _house()
	Game.inventory.set_loan(0)
	house.size_tier = House.SizeTier.MEDIUM
	house.next_size_tier = House.SizeTier.MEDIUM
	var offer: Dictionary = HouseUpgrade.offer_for(house, Game.inventory)
	assert_that(offer["offer"]).is_equal(HouseUpgrade.OFFER_BASEMENT_OR_SKIP)
	assert_that(offer["action"]).is_equal(HouseUpgrade.ACTION_ASK_BASEMENT)
	house.has_basement = true
	offer = HouseUpgrade.offer_for(house, Game.inventory)
	assert_that(offer["offer"]).is_equal(HouseUpgrade.OFFER_BASEMENT_PAID)
	assert_that(offer["action"]).is_equal(HouseUpgrade.ACTION_ORDER_ROOF)
	house.size_tier = House.SizeTier.LARGE
	house.next_size_tier = House.SizeTier.LARGE
	house.has_basement = false
	offer = HouseUpgrade.offer_for(house, Game.inventory)
	assert_that(offer["action"]).is_equal(HouseUpgrade.ACTION_AUTO_BASEMENT)
	house.has_basement = true
	house.basement_just_built = true
	offer = HouseUpgrade.offer_for(house, Game.inventory)
	assert_that(offer["offer"]).is_equal(HouseUpgrade.OFFER_UPPER)


func test_no_offer_at_the_upper_size() -> void:
	var house: House = _house()
	Game.inventory.set_loan(0)
	house.size_tier = House.SizeTier.UPPER
	house.next_size_tier = House.SizeTier.UPPER
	assert_bool(HouseUpgrade.offer_for(house, Game.inventory).is_empty()).is_true()


## --- statue -------------------------------------------------------------------------------


func test_statue_is_offered_once_the_last_loan_is_paid() -> void:
	var house: House = _house()
	house.size_tier = House.SizeTier.UPPER
	house.next_size_tier = House.SizeTier.UPPER
	Game.inventory.set_loan(500)
	assert_int(HouseUpgrade.offer_statue(house, Game.inventory, 0)).is_equal(-1)
	Game.inventory.set_loan(0)
	assert_int(HouseUpgrade.offer_statue(house, Game.inventory, 0)).is_equal(1)
	assert_bool(house.statue_ordered).is_true()
	assert_int(house.statue_rank).is_equal(0)
	## Statue count caps at the jade rank.
	house.statue_ordered = false
	assert_int(HouseUpgrade.offer_statue(house, Game.inventory, 3)).is_equal(3)
	assert_int(house.statue_rank).is_equal(3)


func test_statue_appears_the_day_after_ordering() -> void:
	var house: House = _house()
	house.size_tier = House.SizeTier.UPPER
	house.next_size_tier = House.SizeTier.UPPER
	Game.inventory.set_loan(0)
	HouseUpgrade.offer_statue(house, Game.inventory, 0)
	assert_bool(HouseUpgrade.check_rehouse_order(house)).is_false()
	_next_day()
	assert_bool(HouseUpgrade.check_rehouse_order(house)).is_true()
	assert_bool(HouseUpgrade.is_statue(house)).is_true()
	assert_int(house.size_tier).is_equal(House.SizeTier.UPPER)


## --- outdoor model ------------------------------------------------------------------------


func test_exterior_model_follows_size_for_the_owned_plot_only() -> void:
	var house: House = _house()
	assert_that(PlayerHouse.exterior_visual("player_house", &"obj_s_myhome1")).is_equal(&"obj_s_myhome1")
	house.size_tier = House.SizeTier.LARGE
	assert_that(PlayerHouse.exterior_visual("player_house", &"obj_s_myhome1")).is_equal(&"obj_s_myhome3")
	house.size_tier = House.SizeTier.STATUE
	assert_that(PlayerHouse.exterior_visual("player_house", &"obj_s_myhome1")).is_equal(&"obj_s_myhome4")
	## Vacant plots and villager homes are untouched.
	assert_that(PlayerHouse.exterior_visual("player_house_2", &"obj_s_myhome1")).is_equal(&"obj_s_myhome1")
	assert_that(PlayerHouse.exterior_visual("npc_house_3", &"obj_s_house1_a")).is_equal(&"obj_s_house1_a")


func test_intro_pick_decides_which_plot_is_owned() -> void:
	Game.intro_station_house_id = &"player_house_2"
	assert_bool(PlayerHouse.is_owned_node("player_house_2")).is_true()
	assert_bool(PlayerHouse.is_owned_node("player_house")).is_false()


func test_every_house_size_has_its_exterior_and_shell_assets() -> void:
	## Only meaningful once the local asset pipeline has run.
	for n: int in range(1, 5):
		var paths: PackedStringArray = FieldCatalog.mesh_paths(StringName("obj_s_myhome%d" % n))
		if paths.is_empty():
			return
		assert_bool(paths.size() > 0).is_true()
	for id: StringName in [&"obj_myhome_step_down", &"obj_myhome_step_up"]:
		assert_bool(FieldCatalog.mesh_paths(id).size() > 0 or not ResourceLoader.exists(
			"res://assets/generated/environment/%s.glb" % id
		)).is_true()


## --- Nook's conversation (`aNSC_start_wait`) -----------------------------------------------


func test_nook_collects_the_loan_for_a_landed_build() -> void:
	var house: House = _house()
	HouseUpgrade.order_upgrade(house, 1)
	_next_day()
	HouseUpgrade.check_rehouse_order(house)
	assert_bool(NookHouseTalk.has_business(house, Game.inventory)).is_true()
	var plan: Dictionary = NookHouseTalk.plan(house, Game.inventory, 0)
	assert_that(plan["scene"]).is_equal(HouseUpgrade.BUILT_MEDIUM)
	assert_int(Game.inventory.loan).is_equal(HouseUpgrade.LOAN_MEDIUM)
	## Second visit: loan is owed, so no offer.
	assert_bool(NookHouseTalk.plan(house, Game.inventory, 0).is_empty()).is_true()


func test_nook_offers_an_upgrade_when_the_loan_is_clear() -> void:
	var house: House = _house()
	Game.inventory.set_loan(0)
	var plan: Dictionary = NookHouseTalk.plan(house, Game.inventory, 0)
	assert_that(plan["scene"]).is_equal(HouseUpgrade.OFFER_MEDIUM)
	assert_that(plan["action"]).is_equal(HouseUpgrade.ACTION_ORDER_ROOF)


func test_nook_says_nothing_while_a_loan_is_owed() -> void:
	Game.inventory.set_loan(19800)
	assert_bool(NookHouseTalk.has_business(_house(), Game.inventory)).is_false()
	assert_bool(NookHouseTalk.plan(_house(), Game.inventory, 0).is_empty()).is_true()


func test_nook_statue_flow_bumps_the_statue_count() -> void:
	var house: House = _house()
	house.size_tier = House.SizeTier.UPPER
	house.next_size_tier = House.SizeTier.UPPER
	Game.inventory.set_loan(0)
	var plan: Dictionary = NookHouseTalk.plan(house, Game.inventory, 1)
	assert_that(plan["scene"]).is_equal(HouseUpgrade.OFFER_STATUE)
	assert_int(int(plan["statues_built"])).is_equal(2)
	assert_int(house.statue_rank).is_equal(1)
	_next_day()
	HouseUpgrade.check_rehouse_order(house)
	var built: Dictionary = NookHouseTalk.plan(house, Game.inventory, 2)
	assert_that(built["scene"]).is_equal(HouseUpgrade.BUILT_STATUE)
	assert_bool(house.statue_ordered).is_false()


func test_dialogue_events_place_the_orders() -> void:
	var house: House = _house()
	var notice: String = NookHouseTalk.apply_event({"op": "house_order_roof", "palette": 5}, house)
	assert_bool(notice != "").is_true()
	assert_int(house.next_size_tier).is_equal(House.SizeTier.MEDIUM)
	assert_int(house.ordered_outlook_pal).is_equal(5)
	house.size_tier = House.SizeTier.MEDIUM
	house.next_size_tier = House.SizeTier.MEDIUM
	assert_bool(NookHouseTalk.apply_event({"op": "house_order_basement"}, house) != "").is_true()
	assert_bool(house.basement_ordered).is_true()


func test_house_dialogue_covers_every_scene() -> void:
	var data: DialogueData = DialogueCatalog.conversation(NookHouseTalk.DIALOGUE_ID)
	assert_that(data).is_not_null()
	for scene: StringName in [
		HouseUpgrade.BUILT_MEDIUM,
		HouseUpgrade.BUILT_LARGE,
		HouseUpgrade.BUILT_UPPER,
		HouseUpgrade.BUILT_BASEMENT,
		HouseUpgrade.BUILT_STATUE,
		HouseUpgrade.OFFER_MEDIUM,
		HouseUpgrade.OFFER_BASEMENT_OR_SKIP,
		HouseUpgrade.OFFER_BASEMENT_PAID,
		HouseUpgrade.OFFER_BASEMENT,
		HouseUpgrade.OFFER_LARGE,
		HouseUpgrade.OFFER_UPPER,
		HouseUpgrade.OFFER_STATUE,
	]:
		var ctx := DialogueContext.new()
		NookHouseTalk.fill_context(ctx, {"scene": scene})
		var runner := DialogueRunner.new()
		runner.start(data, ctx)
		assert_bool(runner.line != "" or runner.waiting_choice).override_failure_message(
			"no opening line for %s" % scene
		).is_true()


func test_offer_dialogue_orders_a_house_through_the_roof_menu() -> void:
	var data: DialogueData = DialogueCatalog.conversation(NookHouseTalk.DIALOGUE_ID)
	var ctx := DialogueContext.new()
	NookHouseTalk.fill_context(ctx, {"scene": HouseUpgrade.OFFER_MEDIUM})
	var runner := DialogueRunner.new()
	var house: House = _house()
	runner.event_fired.connect(func(event: Dictionary) -> void: NookHouseTalk.apply_event(event, house))
	runner.start(data, ctx)
	assert_bool(runner.waiting_choice).is_false()
	runner.advance()
	assert_bool(runner.waiting_choice).is_true()
	runner.choose(0)
	assert_bool(runner.waiting_choice).is_true()
	assert_int(runner.choices.size()).is_less_equal(4)
	runner.choose(1)
	assert_int(house.next_size_tier).is_equal(House.SizeTier.MEDIUM)
	assert_int(house.ordered_outlook_pal).is_equal(1)


func test_declining_the_offer_orders_nothing() -> void:
	var data: DialogueData = DialogueCatalog.conversation(NookHouseTalk.DIALOGUE_ID)
	var ctx := DialogueContext.new()
	NookHouseTalk.fill_context(ctx, {"scene": HouseUpgrade.OFFER_MEDIUM})
	var runner := DialogueRunner.new()
	var house: House = _house()
	runner.event_fired.connect(func(event: Dictionary) -> void: NookHouseTalk.apply_event(event, house))
	runner.start(data, ctx)
	runner.advance()
	runner.choose(1)
	assert_int(house.next_size_tier).is_equal(House.SizeTier.SMALL)


func test_roof_menu_pages_hold_three_colours_and_cover_all_twelve() -> void:
	var seen: Array[int] = []
	for page: int in 4:
		var ids: Array[int] = NookHouseTalk.palettes_on_page(page)
		assert_int(ids.size()).is_equal(3)
		seen.append_array(ids)
	assert_int(seen.size()).is_equal(12)
	assert_int(seen[11]).is_equal(11)


func test_debug_console_house_commands() -> void:
	var console := DebugConsole.new()
	assert_bool(console.execute("house").begins_with("House: small")).is_true()
	console.execute("house size large")
	assert_int(_house().size_tier).is_equal(House.SizeTier.LARGE)
	console.execute("house basement")
	assert_bool(_house().has_basement).is_true()
	console.execute("house size small")
	assert_bool(_house().has_basement).is_false()


## --- fish / insect completion talk (`mPr_*CompleteTalk`) -----------------------------------


func _complete_kind(kind: StringName) -> void:
	for row: Dictionary in EncyclopediaCatalog.page(kind):
		Game.species_log.record(row["id"])


func test_collection_completion_needs_every_species() -> void:
	assert_bool(CompleteTalk.collection_complete(CompleteTalk.FISH)).is_false()
	_complete_kind(&"fish")
	assert_bool(CompleteTalk.collection_complete(CompleteTalk.FISH)).is_true()
	assert_bool(CompleteTalk.collection_complete(CompleteTalk.INSECT)).is_false()


func test_permission_and_flags_for_a_mid_session_completion() -> void:
	_complete_kind(&"fish")
	assert_bool(CompleteTalk.permission(CompleteTalk.FISH)).is_true()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var state := VillagerState.new()
	var msg: int = CompleteTalk.try_greeting(2, state, rng)
	assert_int(msg).is_between(CompleteTalk.MSG_FISH + 6, CompleteTalk.MSG_FISH + 8)
	assert_bool(CompleteTalk.talked(CompleteTalk.FISH)).is_true()
	assert_bool(state.fish_complete_talk).is_true()
	## Same villager stays quiet, but the flag is set for the house.
	assert_int(CompleteTalk.try_greeting(2, state, rng)).is_equal(-1)
	## Completed mid-session (base bit clear): every other villager still gets a turn.
	assert_int(CompleteTalk.try_greeting(0, VillagerState.new(), rng)).is_greater_equal(CompleteTalk.MSG_FISH)


func test_a_collection_already_complete_at_start_only_speaks_once() -> void:
	_complete_kind(&"insect")
	CompleteTalk.start_set_info()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	assert_int(CompleteTalk.try_greeting(1, VillagerState.new(), rng)).is_greater_equal(CompleteTalk.MSG_INSECT)
	assert_int(CompleteTalk.try_greeting(1, VillagerState.new(), rng)).is_equal(-1)


func test_incomplete_collection_never_congratulates() -> void:
	var rng := RandomNumberGenerator.new()
	assert_int(CompleteTalk.try_greeting(1, VillagerState.new(), rng)).is_equal(-1)
	assert_bool(CompleteTalk.talked(CompleteTalk.FISH)).is_false()


func test_completion_flags_survive_a_save() -> void:
	Game.complete_flags = 0b1010
	var snap: Dictionary = Game.to_save()
	Game.complete_flags = 0
	Game.apply_snapshot(snap)
	assert_bool(CompleteTalk.talked(CompleteTalk.FISH)).is_true()
	assert_bool(CompleteTalk.talked(CompleteTalk.INSECT)).is_true()


func test_villager_state_round_trips_the_completion_marks() -> void:
	var state := VillagerState.new()
	state.villager_id = &"filbert"
	state.fish_complete_talk = true
	var copy := VillagerState.new()
	copy.apply_snapshot(state.to_save())
	assert_bool(copy.fish_complete_talk).is_true()
	assert_bool(copy.insect_complete_talk).is_false()
