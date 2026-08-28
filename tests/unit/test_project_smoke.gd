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
