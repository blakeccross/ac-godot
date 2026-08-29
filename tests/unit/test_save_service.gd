class_name TestSaveService
extends GdUnitTestSuite

const PATH := "user://test_phase1_save.json"


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


func test_save_and_load_clock_and_inventory() -> void:
	var apple: ItemData = load("res://data/items/apple.tres")
	Clock.advance_minutes(125)
	Game.inventory.add(apple, 3)
	assert_int(SaveService.save_game(PATH)).is_equal(OK)
	Clock.reset_to_default()
	Game.inventory.clear()
	assert_int(SaveService.load_game(PATH)).is_equal(OK)
	assert_int(Clock.hour).is_equal(14)
	assert_int(Clock.minute).is_equal(5)
	assert_int(Game.inventory.count_of(&"apple")).is_equal(3)


func test_save_and_load_player_pose_and_removed_pickup() -> void:
	Game.player_position = Vector3(2.0, 0.1, 1.5)
	Game.player_yaw = 0.5
	Game.mark_interactable_removed(&"ground_apple")
	Game.mark_stump(&"tree_1")
	Game.mark_hole(&"hole_8_9")
	assert_int(SaveService.save_game(PATH)).is_equal(OK)
	Game.reset_session()
	assert_int(SaveService.load_game(PATH)).is_equal(OK)
	assert_vector(Game.player_position).is_equal_approx(Vector3(2.0, 0.1, 1.5), Vector3(0.001, 0.001, 0.001))
	assert_float(Game.player_yaw).is_equal_approx(0.5, 0.001)
	assert_bool(Game.is_interactable_removed(&"ground_apple")).is_true()
	assert_bool(Game.is_stump(&"tree_1")).is_true()
	assert_bool(Game.is_hole(&"hole_8_9")).is_true()


func test_save_and_load_villager_friendship() -> void:
	var pip: VillagerState = Game.villagers.get_or_create(&"pip")
	pip.friendship = 7
	pip.last_spoke_day = "2001-01-02"
	assert_int(SaveService.save_game(PATH)).is_equal(OK)
	Game.reset_session()
	assert_int(SaveService.load_game(PATH)).is_equal(OK)
	assert_int(Game.villagers.get_or_create(&"pip").friendship).is_equal(7)
	assert_str(Game.villagers.get_or_create(&"pip").last_spoke_day).is_equal("2001-01-02")


func test_missing_save_is_not_found() -> void:
	assert_int(SaveService.load_game(PATH)).is_equal(ERR_FILE_NOT_FOUND)
