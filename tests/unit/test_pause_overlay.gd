class_name TestPauseOverlay
extends GdUnitTestSuite

## Esc confirm overlay hosted by the HUD.


func test_hud_hosts_pause_overlay_and_it_pauses_while_open() -> void:
	var hud: Node = auto_free(load("res://scenes/ui/clock_hud.tscn").instantiate())
	add_child(hud)
	var pause: Node = hud.get_node("PauseOverlay")
	assert_bool(pause.is_in_group("pause_ui")).is_true()
	assert_bool(bool(pause.call("is_open"))).is_false()
	pause.call("open")
	assert_bool(bool(pause.call("is_open"))).is_true()
	assert_bool(get_tree().paused).is_true()
	pause.call("close")
	assert_bool(bool(pause.call("is_open"))).is_false()
	assert_bool(get_tree().paused).is_false()


func test_continue_leaves_title_demo_mode() -> void:
	## Regression: Continue from the attract-mode title left `title_demo_active` set, so the
	## loaded world reported phase TITLE and Esc did nothing.
	Game.begin_title_demo(0)
	assert_bool(Game.title_demo_active).is_true()
	SaveService.save_game("user://_test_continue.json")
	Game.reset_session()
	Game.begin_title_demo(0)
	## Same steps as `continue_game` without the scene change.
	Game.reset_session()
	SaveService.load_game("user://_test_continue.json")
	Game.notify_world_ready()
	assert_bool(Game.title_demo_active).is_false()
	assert_int(Game.phase).is_equal(Game.Phase.PLAYING)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://_test_continue.json"))
	Game.reset_session()
	Game.phase = Game.Phase.TITLE
