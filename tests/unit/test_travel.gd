extends GdUnitTestSuite

## Travelling between two towns: Porter's passport (`mCD_SaveStation_*`), the visitor
## (`mPr_FOREIGNER`) and the way home (`aNPS2_TALK_START_TYPE1`).

const A := "user://test_travel_a.json"
const B := "user://test_travel_b.json"
const PASSPORT := "user://test_travel_passport.json"

var _saved_paths: Array[String] = []
var _saved_current: String = ""


func before_test() -> void:
	_saved_paths = SaveService.slot_paths.duplicate()
	_saved_current = SaveService.current_path
	SaveService.slot_paths = [A, B]
	Travel.passport_path = PASSPORT
	Clock.reset_to_default()
	Clock.paused = true
	_clean()
	Game.reset_session()


func after_test() -> void:
	_clean()
	SaveService.slot_paths = _saved_paths
	SaveService.current_path = _saved_current
	Travel.passport_path = Travel.PASSPORT_PATH
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func _clean() -> void:
	SaveService.delete_save(A)
	SaveService.delete_save(B)
	Travel.delete_passport()


func _apple() -> ItemData:
	return load("res://data/items/apple.tres") as ItemData


## Town A with Ann carrying two apples, town B with Zed.
func _two_towns() -> void:
	SaveService.current_path = B
	Game.player_name = "Zed"
	Game.town_name = "Elm"
	assert_int(SaveService.save_game()).is_equal(OK)
	Game.reset_session()
	SaveService.current_path = A
	Game.player_name = "Ann"
	Game.town_name = "Pine"
	Game.inventory.add(_apple(), 2)
	assert_int(SaveService.save_game()).is_equal(OK)


func test_porter_needs_another_town_to_go_to() -> void:
	SaveService.current_path = A
	Game.player_name = "Ann"
	SaveService.save_game()
	assert_str(Travel.departure_problem()).is_equal("no_town")
	var talk := PorterTalk.new(false, true)
	talk.context = DialogueContext.new()
	assert_int(talk.picked(PorterTalk.ASK_TRIP, 0)).is_equal(PorterTalk.NO_TOWN)
	assert_int(talk.picked(PorterTalk.ASK_TRIP, 1)).is_equal(PorterTalk.NOT_GOING)
	assert_int(PorterTalk.new(false, false).start_msg()).is_equal(PorterTalk.NEVER_SAVED)


func test_departing_takes_the_pockets_and_leaves_them_away_at_home() -> void:
	_two_towns()
	assert_str(Travel.departure_problem()).is_equal("")
	var home_id: int = Game.town_id
	assert_int(Travel.depart()).is_equal(OK)
	var passport: Dictionary = Travel.read_passport()
	assert_str(str(passport["player_name"])).is_equal("Ann")
	assert_int(int(passport["home_town_id"])).is_equal(home_id)
	var roster: PlayerRoster = SaveService.read_roster(A)
	assert_bool(Travel.is_away(roster, 0)).is_true()
	## Home keeps Ann without her apples.
	Game.reset_session()
	assert_int(SaveService.load_game(A, 0)).is_equal(OK)
	assert_int(Game.inventory.count_of(&"apple")).is_equal(0)


func test_kk_welcomes_a_visitor_and_the_shop_counts_them() -> void:
	_two_towns()
	Travel.depart()
	Game.reset_session()
	SaveService.current_path = B
	var talk := PlayerSelectTalk.new(SaveService.read_roster(B), "Elm", 1)
	talk.context = DialogueContext.new()
	talk.passport = Travel.read_passport()
	talk.town_id = SaveService.read_town_id(B)
	var step: Dictionary = talk.pick_step(PlayerSelectTalk.at(PlayerSelectTalk.SHALL_WE), 0)
	assert_int(int(step["msg"])).is_equal(PlayerSelectTalk.at(PlayerSelectTalk.CARD_VISIT))
	assert_int(talk.result).is_equal(PlayerSelectTalk.Result.VISIT)
	assert_int(SaveService.load_visitor(talk.passport)).is_equal(OK)
	assert_bool(Game.foreigner).is_true()
	assert_str(Game.player_name).is_equal("Ann")
	assert_str(Game.town_name).is_equal("Elm")
	assert_int(Game.inventory.count_of(&"apple")).is_equal(2)
	## No house of her own here; Zed's plot is still Zed's.
	assert_str(String(PlayerHouse.owned_building_id())).is_equal("")
	assert_int(Game.roster.slot_on_plot(&"player_house")).is_equal(0)
	## Porter asks a visitor whether they are leaving, and saves this town without her.
	var porter := PorterTalk.new(true, false)
	assert_int(porter.start_msg()).is_equal(PorterTalk.LEAVING)
	assert_int(porter.continue_to(0, PorterTalk.SAVE_PASSPORT)).is_equal(PorterTalk.SAVE_NEXTLAND)
	Game.inventory.add(_apple(), 1)
	Game.shops.set_visitor()
	assert_int(Travel.leave_as_visitor()).is_equal(OK)
	assert_str(SaveService.read_roster(B).name_of(0)).is_equal("Zed")
	assert_int(SaveService.read_roster(B).count()).is_equal(1)
	Game.reset_session()
	assert_int(SaveService.load_game(B, 0)).is_equal(OK)
	assert_bool(Game.shops.has_visitor()).is_true()


func test_back_home_with_what_she_carried() -> void:
	_two_towns()
	Travel.depart()
	Game.reset_session()
	SaveService.current_path = B
	SaveService.load_visitor(Travel.read_passport())
	Game.inventory.add(_apple(), 3)
	Travel.leave_as_visitor()
	Game.reset_session()
	SaveService.current_path = A
	var talk := PlayerSelectTalk.new(SaveService.read_roster(A), "Pine", 0)
	talk.context = DialogueContext.new()
	talk.passport = Travel.read_passport()
	talk.town_id = SaveService.read_town_id(A)
	var step: Dictionary = talk.pick_step(PlayerSelectTalk.at(PlayerSelectTalk.SHALL_WE), 0)
	assert_int(int(step["msg"])).is_equal(PlayerSelectTalk.at(PlayerSelectTalk.CARD_HOME))
	assert_int(talk.result).is_equal(PlayerSelectTalk.Result.RETURN)
	assert_int(Travel.adopt_passport()).is_equal(0)
	assert_bool(Travel.has_passport()).is_false()
	Game.reset_session()
	assert_int(SaveService.load_game(A, 0)).is_equal(OK)
	assert_str(Game.player_name).is_equal("Ann")
	assert_int(Game.inventory.count_of(&"apple")).is_equal(5)
	assert_bool(Travel.is_away(Game.roster, 0)).is_false()


func test_playing_the_left_behind_data_is_asked_first() -> void:
	_two_towns()
	Travel.depart()
	var roster: PlayerRoster = SaveService.read_roster(A)
	var talk := PlayerSelectTalk.new(roster, "Pine", 0)
	talk.context = DialogueContext.new()
	talk.pick_step(PlayerSelectTalk.at(PlayerSelectTalk.SHALL_WE), 0)
	## The passport is home's: K.K. would copy it back. Picking Ann from the list instead:
	talk.passport = {}
	talk.pick_step(PlayerSelectTalk.at(PlayerSelectTalk.SHALL_WE), 0)
	assert_int(int(talk.choose(0)["msg"])).is_equal(PlayerSelectTalk.at(PlayerSelectTalk.TRAVELLER))
	assert_int(talk.picked(PlayerSelectTalk.at(PlayerSelectTalk.TRAVELLER), 0)).is_equal(
		PlayerSelectTalk.at(PlayerSelectTalk.TRAVELLER_OK)
	)
	assert_int(talk.result).is_equal(PlayerSelectTalk.Result.LOAD)
