class_name TestProjectSmoke
extends GdUnitTestSuite


func test_engine_is_godot_4() -> void:
	var info: Dictionary = Engine.get_version_info()
	assert_int(info.major).is_equal(4)


func test_project_name() -> void:
	assert_str(ProjectSettings.get_setting("application/config/name")).is_equal("AC Godot")


func test_main_scene_is_title() -> void:
	assert_str(ProjectSettings.get_setting("application/run/main_scene")).is_equal(
		"res://scenes/ui/title.tscn"
	)


func test_player_scene_is_character_body() -> void:
	var packed: PackedScene = load("res://scenes/actors/player.tscn")
	assert_that(packed).is_not_null()
	var player: Node = auto_free(packed.instantiate()) as Node
	assert_bool(player is CharacterBody3D).is_true()
	assert_bool(player.has_method("facing_yaw")).is_true()
	assert_bool(player.has_method("camera_look_position")).is_true()
