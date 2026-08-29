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
	Game.villagers.get_or_create(&"pip").friendship = 8
	Game.player_position = Vector3(3, 0.1, -2)
	Game.player_yaw = 1.2
	Game.mark_interactable_removed(&"ground_apple")
	Game.mark_stump(&"tree_1")
	Game.mark_hole(&"hole_8_9")
	Game.reset_session()
	assert_int(Game.inventory.count_of_occupied()).is_equal(0)
	assert_bool(Game.villagers.has_id(&"pip")).is_false()
	assert_vector(Game.player_position).is_equal(Game.DEFAULT_SPAWN)
	assert_float(Game.player_yaw).is_equal(0.0)
	assert_bool(Game.is_interactable_removed(&"ground_apple")).is_false()
	assert_bool(Game.is_stump(&"tree_1")).is_false()
	assert_bool(Game.is_hole(&"hole_8_9")).is_false()
	assert_that(Game.world_mode).is_equal(WorldData.Mode.TEST)


func test_test_world_gets_starter_tools() -> void:
	ItemCatalog.reload()
	assert_int(Game.inventory.count_of_occupied()).is_equal(0)
	Game.notify_world_ready()
	assert_int(Game.inventory.count_of(&"shovel")).is_equal(1)
	assert_int(Game.inventory.count_of(&"axe")).is_equal(1)
	assert_int(Game.inventory.count_of(&"net")).is_equal(1)
	assert_int(Game.inventory.count_of(&"fishing_rod")).is_equal(1)
	assert_int(Game.inventory.count_of(&"watering_can")).is_equal(1)
	Game.notify_world_ready()
	assert_int(Game.inventory.count_of(&"axe")).is_equal(1)
	Game.reset_session()
	Game.world_mode = WorldData.Mode.GENERATED
	Game.notify_world_ready()
	assert_int(Game.inventory.count_of_occupied()).is_equal(0)


func test_world_snapshot_round_trip() -> void:
	Game.player_position = Vector3(4.5, 0.1, -3.25)
	Game.player_yaw = 0.75
	Game.mark_interactable_removed(&"ground_apple")
	Game.mark_stump(&"tree_1")
	Game.mark_hole(&"hole_8_9")
	Game.world_mode = WorldData.Mode.GENERATED
	Game.world_seed = 12345
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(snap)
	assert_vector(Game.player_position).is_equal(Vector3(4.5, 0.1, -3.25))
	assert_float(Game.player_yaw).is_equal(0.75)
	assert_bool(Game.is_interactable_removed(&"ground_apple")).is_true()
	assert_bool(Game.is_stump(&"tree_1")).is_true()
	assert_bool(Game.is_hole(&"hole_8_9")).is_true()
	assert_that(Game.world_mode).is_equal(WorldData.Mode.GENERATED)
	assert_int(Game.world_seed).is_equal(12345)


func test_villager_roster_survives_world_snapshot() -> void:
	var pip: VillagerState = Game.villagers.get_or_create(&"pip")
	pip.friendship = 20
	pip.last_spoke_day = "2001-06-01"
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(snap)
	assert_int(Game.villagers.get_or_create(&"pip").friendship).is_equal(20)
	assert_str(Game.villagers.get_or_create(&"pip").last_spoke_day).is_equal("2001-06-01")


func test_empty_persist_id_is_never_removed() -> void:
	Game.mark_interactable_removed(&"")
	Game.mark_stump(&"")
	Game.mark_hole(&"")
	assert_bool(Game.is_interactable_removed(&"")).is_false()
	assert_bool(Game.is_stump(&"")).is_false()
	assert_bool(Game.is_hole(&"")).is_false()
