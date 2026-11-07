class_name TestGameState
extends GdUnitTestSuite

## `PlayerState` / `TownState`: the resident's and the town's saved fields, written under
## the same keys `Game.to_save` always used.


func test_the_resident_round_trips_through_its_save_keys() -> void:
	var a := PlayerState.new()
	a.player_name = "Ana"
	a.player_gender = &"female"
	a.player_face = 3
	a.cloth_id = &"cloth_042"
	a.destiny_type = PlayerState.Destiny.MONEY_LUCK
	a.destiny_date = Vector3i(2002, 4, 1)
	a.player_position = Vector3(1.5, 0.1, -2.0)
	a.player_yaw = 1.25
	a.diary[3] = "a page"
	a.has_map = true
	a.complete_flags = 0x5
	var out: Dictionary = {}
	a.write_save(out)
	## the flat keys the roster splits a resident's part on
	for key: String in ["player", "player_name", "player_gender", "player_face", "cloth_id", "destiny", "diary", "has_map", "complete_flags"]:
		assert_bool(out.has(key)).override_failure_message("missing " + key).is_true()
	var b := PlayerState.new()
	b.read_save(JSON.parse_string(JSON.stringify(out)))
	assert_str(b.player_name).is_equal("Ana")
	assert_that(b.player_gender).is_equal(&"female")
	assert_int(b.player_face).is_equal(3)
	assert_that(b.cloth_id).is_equal(&"cloth_042")
	assert_int(b.destiny_type).is_equal(PlayerState.Destiny.MONEY_LUCK)
	assert_vector(Vector3(b.destiny_date)).is_equal(Vector3(2002, 4, 1))
	assert_vector(b.player_position).is_equal_approx(Vector3(1.5, 0.1, -2.0), Vector3.ONE * 0.0001)
	assert_float(b.player_yaw).is_equal_approx(1.25, 0.0001)
	assert_str(str(b.diary.get(3, ""))).is_equal("a page")
	assert_bool(b.has_map).is_true()
	assert_int(b.complete_flags).is_equal(0x5)


func test_a_resident_missing_from_the_save_takes_the_defaults() -> void:
	var s := PlayerState.new()
	s.player_name = "Old"
	s.read_save({})
	assert_str(s.player_name).is_equal(PlayerState.DEFAULT_PLAYER_NAME)
	assert_vector(s.player_position).is_equal(PlayerState.DEFAULT_SPAWN)
	assert_that(s.cloth_id).is_equal(FirstJob.DEFAULT_CLOTH_ID)


func test_the_town_round_trips_through_its_save_keys() -> void:
	var a := TownState.new()
	a.town_name = "Elm"
	a.town_fruit = &"cherry"
	a.station_type = 11
	a.weeds["weed_3_4"] = 2
	a.mushrooms["mushroom_1_1"] = 1
	a.field_rank = 4
	a.weather = &"rain"
	a.weather_intensity = 2
	a.fish_season_term = 7
	a.fish_season_offset = 3
	a.removed_interactables.append("tree_2_2")
	var out: Dictionary = {}
	a.write_save(out)
	var b := TownState.new()
	b.read_save(JSON.parse_string(JSON.stringify(out)))
	assert_str(b.town_name).is_equal("Elm")
	assert_that(b.town_fruit).is_equal(&"cherry")
	assert_int(b.station_type).is_equal(11)
	assert_int(int(b.weeds.get("weed_3_4", -1))).is_equal(2)
	assert_bool(b.mushrooms.has("mushroom_1_1")).is_true()
	assert_int(b.field_rank).is_equal(4)
	assert_that(b.weather).is_equal(&"rain")
	assert_int(b.weather_intensity).is_equal(2)
	assert_int(b.fish_season_term).is_equal(7)
	assert_int(b.fish_season_offset).is_equal(3)
	assert_array(b.removed_interactables).contains_exactly(["tree_2_2"])


func test_reset_gives_a_new_towns_values() -> void:
	var t := TownState.new()
	t.weeds["weed_1_1"] = 1
	t.field_rank = 6
	t.town_name = "Elm"
	t.reset()
	assert_bool(t.weeds.is_empty()).is_true()
	assert_int(t.field_rank).is_equal(0)
	assert_str(t.town_name).is_equal(TownState.DEFAULT_TOWN_NAME)
	assert_int(t.town_id).is_not_equal(0)


func test_game_saves_through_both_resources() -> void:
	Game.resident.player_name = "Kip"
	Game.town.town_name = "Oak"
	var save: Dictionary = Game.to_save()
	assert_str(str(save["player_name"])).is_equal("Kip")
	assert_str(str(save["town_name"])).is_equal("Oak")
	## the roster still finds every resident key in the flat save
	for key: String in PlayerRoster.PRIVATE_KEYS:
		assert_bool(save.has(key)).override_failure_message("roster key " + key).is_true()
	Game.reset_session()


## Every `SaveBook` is written under its key, and a save written before a book existed
## gives that book its new-town start (the police box's three items, the first handbills).
func test_every_book_saves_under_its_key_and_old_saves_start_fresh() -> void:
	Game.reset_session()
	var save: Dictionary = Game.to_save()
	for key: String in Game._save_books():
		assert_bool(save.has(key)).override_failure_message("book key " + key).is_true()
	save.erase("police")
	save.erase("notice_board")
	Game.police.clear()
	Game.notice_board.clear()
	Game.apply_snapshot(save)
	var stocked: int = 0
	for i: int in PoliceBook.STORAGE_COUNT:
		if Game.police.item_at(i) != &"":
			stocked += 1
	assert_int(stocked).is_equal(3)
	assert_int(Game.notice_board.count()).is_greater(0)
	Game.reset_session()


func test_a_new_town_starts_a_new_session() -> void:
	Game.session.shells_owed = 0
	Game.session.nook_code_gifts = 4
	Game.reset_session()
	assert_int(Game.session.shells_owed).is_equal(ShellUse.FIRST_NUM)
	assert_int(Game.session.nook_code_gifts).is_equal(0)
	Game.session.nook_code_gifts = 2
	Game.session.roach_shocked = true
	Game.apply_snapshot(Game.to_save())
	## a load starts the per-load flags again, not the whole session
	assert_bool(Game.session.roach_shocked).is_false()
	assert_int(Game.session.nook_code_gifts).is_equal(2)
	Game.reset_session()
