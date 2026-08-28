class_name TestSaveService
extends GdUnitTestSuite

const PATH := "user://test_phase1_save.json"


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.inventory.clear()
	SaveService.delete_save(PATH)


func after_test() -> void:
	SaveService.delete_save(PATH)
	Clock.reset_to_default()
	Clock.paused = false
	Game.inventory.clear()


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


func test_missing_save_is_not_found() -> void:
	assert_int(SaveService.load_game(PATH)).is_equal(ERR_FILE_NOT_FOUND)
