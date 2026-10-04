extends GdUnitTestSuite

## Up to four human residents in one town (`private_data[PLAYER_NUM]`, `ac_npc_p_sel2`).

const PATH := "user://test_residents_save.json"


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	SaveService.delete_save(PATH)


func after_test() -> void:
	SaveService.delete_save(PATH)
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func _apple() -> ItemData:
	return load("res://data/items/apple.tres") as ItemData


## Resident A in slot 0 on plot 0, resident B in slot 1 on plot 1, both saved.
func _two_residents() -> void:
	Game.player_name = "Ann"
	Game.town_name = "Pine"
	Game.interiors.player_house().outdoor_building_id = &"player_house"
	Game.inventory.add(_apple(), 2)
	Game.mark_interactable_removed(&"town_thing")
	assert_int(SaveService.save_game(PATH)).is_equal(OK)
	Game.reset_session()
	assert_int(SaveService.load_game(PATH, 1)).is_equal(OK)
	Game.player_name = "Bob"
	Game.interiors.player_house().outdoor_building_id = &"player_house_1"
	Game.interiors.player_house().size_tier = House.SizeTier.MEDIUM
	assert_int(SaveService.save_game(PATH)).is_equal(OK)


func test_the_town_part_has_no_resident_in_it() -> void:
	Game.player_name = "Ann"
	Game.inventory.add(_apple(), 1)
	var world: Dictionary = Game.to_save()
	var priv: Dictionary = PlayerRoster.split(world)
	assert_bool(world.has("player_name")).is_false()
	assert_str(str(priv.get("player_name", ""))).is_equal("Ann")
	assert_bool(priv.has(PlayerRoster.KEY_HOUSE)).is_true()
	var merged: Dictionary = PlayerRoster.merge(world, priv)
	assert_str(str(merged.get("player_name", ""))).is_equal("Ann")
	assert_bool((merged["interiors"]["houses"] as Dictionary).has(String(InteriorCatalog.PLAYER_HOUSE_ID))).is_true()


func test_each_resident_keeps_their_own_things_and_shares_the_town() -> void:
	_two_residents()
	## A newcomer started with nothing of Ann's but in Ann's town.
	Game.reset_session()
	assert_int(SaveService.load_game(PATH, 1)).is_equal(OK)
	assert_str(Game.player_name).is_equal("Bob")
	assert_int(Game.inventory.count_of(&"apple")).is_equal(0)
	assert_bool(Game.is_interactable_removed(&"town_thing")).is_true()
	assert_str(String(PlayerHouse.owned_building_id())).is_equal("player_house_1")
	Game.reset_session()
	assert_int(SaveService.load_game(PATH, 0)).is_equal(OK)
	assert_str(Game.player_name).is_equal("Ann")
	assert_int(Game.inventory.count_of(&"apple")).is_equal(2)
	assert_str(String(PlayerHouse.owned_building_id())).is_equal("player_house")
	assert_int(Game.roster.count()).is_equal(2)
	## The other resident's plot is lived in and shows their house size.
	assert_int(Game.roster.slot_on_plot(&"player_house_1")).is_equal(1)
	assert_int(Game.roster.slot_on_plot(&"player_house_2")).is_equal(-1)
	assert_str(String(PlayerHouse.exterior_visual("player_house_1", &"obj_s_myhome1"))).is_equal("obj_s_myhome2")


func test_a_one_resident_save_from_before_is_resident_one() -> void:
	var legacy := {
		"version": 1,
		"clock": Clock.to_dict(),
		"inventory": {},
		"world": {"player_name": "Old", "town_name": "Elm", "removed_interactables": ["x"]},
		"reset_code": 0,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(legacy))
	f.close()
	var roster: PlayerRoster = SaveService.read_roster(PATH)
	assert_int(roster.count()).is_equal(1)
	assert_str(roster.name_of(0)).is_equal("Old")
	assert_str(SaveService.read_town_name(PATH)).is_equal("Elm")
	assert_int(SaveService.load_game(PATH)).is_equal(OK)
	assert_str(Game.player_name).is_equal("Old")
	assert_bool(Game.is_interactable_removed(&"x")).is_true()


func _talk(roster: PlayerRoster) -> PlayerSelectTalk:
	var talk := PlayerSelectTalk.new(roster, "Pine")
	talk.context = DialogueContext.new()
	return talk


func _roster(names: Array) -> PlayerRoster:
	var roster := PlayerRoster.new()
	for i: int in names.size():
		roster.slots[i] = {"player_name": names[i]}
	return roster


func test_kk_asks_who_from_the_residents_and_newcomers() -> void:
	var talk := _talk(_roster(["Ann", "Bob"]))
	var step: Dictionary = talk.pick_step(PlayerSelectTalk.at(PlayerSelectTalk.SHALL_WE), 0)
	assert_int(int(step["msg"])).is_equal(PlayerSelectTalk.at(PlayerSelectTalk.WHO))
	assert_array(step["choices"]).contains_exactly(["Ann", "Bob", PlayerSelectTalk.NEW_PLAYER])
	assert_int(int(talk.choose(1)["msg"])).is_equal(PlayerSelectTalk.at(PlayerSelectTalk.KNOWN))
	assert_int(talk.result).is_equal(PlayerSelectTalk.Result.LOAD)
	assert_int(talk.chosen).is_equal(1)
	assert_str(talk.context.player_name).is_equal("Bob")
	talk.pick_step(PlayerSelectTalk.at(PlayerSelectTalk.SHALL_WE), 0)
	assert_int(int(talk.choose(2)["msg"])).is_equal(PlayerSelectTalk.at(PlayerSelectTalk.NEWCOMER))
	assert_int(talk.result).is_equal(PlayerSelectTalk.Result.NEW)
	assert_int(talk.chosen).is_equal(2)


func test_a_full_town_has_no_room_for_a_newcomer() -> void:
	var talk := _talk(_roster(["A", "B", "C", "D"]))
	var step: Dictionary = talk.pick_step(PlayerSelectTalk.at(PlayerSelectTalk.SHALL_WE), 0)
	assert_array(step["choices"]).contains_exactly(["A", "B", "C", "D"])


func test_demolishing_a_house_two_names_a_page_when_full() -> void:
	var roster := _roster(["A", "B", "C", "D"])
	var talk := _talk(roster)
	var step: Dictionary = talk.pick_step(PlayerSelectTalk.at(PlayerSelectTalk.OTHER_THINGS), 0)
	assert_int(int(step["msg"])).is_equal(PlayerSelectTalk.at(PlayerSelectTalk.DEMOLISH_WHO))
	assert_int((step["choices"] as Array).size()).is_equal(4)
	assert_str(str(step["choices"][0])).is_equal("A")
	## "Someone else." turns to C and D.
	step = talk.choose(2)
	assert_int(int(step["msg"])).is_equal(PlayerSelectTalk.at(PlayerSelectTalk.DEMOLISH_OTHER))
	assert_str(str(step["choices"][0])).is_equal("C")
	assert_int(int(talk.choose(1)["msg"])).is_equal(PlayerSelectTalk.at(PlayerSelectTalk.DEMOLISH_SURE))
	assert_int(talk.picked(PlayerSelectTalk.at(PlayerSelectTalk.DEMOLISH_SURE), 1)).is_equal(
		PlayerSelectTalk.at(PlayerSelectTalk.TEARING)
	)
	talk.entered(PlayerSelectTalk.at(PlayerSelectTalk.TORN))
	assert_bool(PlayerRoster.is_resident(roster.slots[3])).is_false()
	assert_array(talk.demolished).contains_exactly([3])


func test_the_last_house_stays() -> void:
	var talk := _talk(_roster(["Ann"]))
	var step: Dictionary = talk.pick_step(PlayerSelectTalk.at(PlayerSelectTalk.OTHER_THINGS), 0)
	assert_int(int(step["msg"])).is_equal(PlayerSelectTalk.at(PlayerSelectTalk.LAST_HOUSE))


func test_a_letter_to_a_housemate_reaches_their_mailbox() -> void:
	_two_residents()
	Game.reset_session()
	assert_int(SaveService.load_game(PATH, 0)).is_equal(OK)
	var candidates: Array[Dictionary] = PostUse.resident_candidates()
	assert_int(candidates.size()).is_equal(1)
	assert_str(str(candidates[0]["name"])).is_equal("Bob")
	var mail := MailData.make_send(StringName(str(candidates[0]["id"])), "Bob", "Hi!", "Ann", &"player")
	assert_bool(Game.roster.deliver_mail(1, mail)).is_true()
	assert_int(SaveService.save_game(PATH)).is_equal(OK)
	Game.reset_session()
	assert_int(SaveService.load_game(PATH, 1)).is_equal(OK)
	var got: bool = false
	for i: int in Inventory.MAIL_SLOTS:
		var m: MailData = Game.inventory.mail_at(i)
		if m != null and m.body == "Hi!":
			got = true
	assert_bool(got).is_true()


func test_visiting_a_housemate_swaps_their_house_in_and_back() -> void:
	_two_residents()
	Game.reset_session()
	assert_int(SaveService.load_game(PATH, 0)).is_equal(OK)
	Game.enter_resident_house(1)
	assert_str(String(Game.interiors.player_house().outdoor_building_id)).is_equal("player_house_1")
	Game.leave_resident_house()
	assert_str(String(Game.interiors.player_house().outdoor_building_id)).is_equal("player_house")
	assert_int(Game.visiting_slot).is_equal(-1)


func test_the_disc_talk_runs_from_hello_to_loading_a_resident() -> void:
	if DialogueCatalog.conversation(&"msg_5106") == null:
		return
	var talk := _talk(_roster(["Ann", "Bob"]))
	var runner := DialogueRunner.new()
	runner.talk_manager = talk
	talk.prepare()
	runner.start(DialogueCatalog.conversation(&"msg_5106"), talk.context)
	var guard := 0
	while not runner.waiting_choice and not runner.done and guard < 40:
		guard += 1
		runner.advance()
	## "Shall we get started?" → "Yes!"
	assert_bool(runner.waiting_choice).is_true()
	runner.choose(0)
	guard = 0
	while not runner.waiting_choice and not runner.done and guard < 40:
		guard += 1
		runner.advance()
	assert_int(runner.choices.size()).is_equal(3)
	assert_str(str(runner.choices[1]["text"])).is_equal("Bob")
	runner.choose(1)
	guard = 0
	while not runner.done and guard < 60:
		guard += 1
		runner.advance()
	assert_bool(runner.done).is_true()
	assert_int(talk.result).is_equal(PlayerSelectTalk.Result.LOAD)
	assert_int(talk.chosen).is_equal(1)
