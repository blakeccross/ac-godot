class_name TestGame
extends GdUnitTestSuite


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	Game.notify_title_ready()


func after_test() -> void:
	Game.reset_session()
	Game.notify_title_ready()
	Clock.reset_to_default()
	Clock.paused = false


func test_reset_session_clears_pockets_and_world_deltas() -> void:
	var apple: ItemData = load("res://data/items/apple.tres")
	Game.inventory.add(apple, 1)
	Game.player_position = Vector3(3, 0.1, -2)
	Game.player_yaw = 1.2
	Game.mark_interactable_removed(&"ground_apple")
	Game.reset_session()
	assert_int(Game.inventory.count_of_occupied()).is_equal(0)
	assert_vector(Game.player_position).is_equal(Game.DEFAULT_SPAWN)
	assert_float(Game.player_yaw).is_equal(0.0)
	assert_bool(Game.is_interactable_removed(&"ground_apple")).is_false()
	assert_that(Game.world_mode).is_equal(WorldData.Mode.TEST)


func test_world_snapshot_round_trip() -> void:
	Game.player_position = Vector3(4.5, 0.1, -3.25)
	Game.player_yaw = 0.75
	Game.mark_interactable_removed(&"ground_apple")
	Game.world_mode = WorldData.Mode.GENERATED
	Game.world_seed = 12345
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(snap)
	assert_vector(Game.player_position).is_equal(Vector3(4.5, 0.1, -3.25))
	assert_float(Game.player_yaw).is_equal(0.75)
	assert_bool(Game.is_interactable_removed(&"ground_apple")).is_true()
	assert_that(Game.world_mode).is_equal(WorldData.Mode.GENERATED)
	assert_int(Game.world_seed).is_equal(12345)


func test_empty_persist_id_is_never_removed() -> void:
	Game.mark_interactable_removed(&"")
	assert_bool(Game.is_interactable_removed(&"")).is_false()
