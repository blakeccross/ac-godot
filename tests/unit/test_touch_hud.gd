class_name TestTouchHud
extends GdUnitTestSuite

## The touch tab bar: Map, Inventory and Settings stay up over their own
## screens with that tab lit, and switch between them.

const PLAYER_SCENE := preload("res://features/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/touch_hud.tscn")
const SETTINGS_SCENE := preload("res://scenes/ui/settings_overlay.tscn")


class _ActionLog extends Node:
	var actions: Array[StringName] = []

	func _unhandled_input(event: InputEvent) -> void:
		for action: StringName in [&"map", &"inventory", &"pause_menu"]:
			if event.is_action_pressed(action):
				actions.append(action)


class _Screen extends Node:
	var open: bool = false

	func is_open() -> bool:
		return open


var _hud: TouchHud
var _settings: SettingsOverlay
var _was_title_demo: bool


func before_test() -> void:
	_was_title_demo = Game.title_demo_active
	Game.title_demo_active = false
	TestIsolation.forget_groups(
		get_tree(), [
			Player.GROUP, TouchHud.GROUP, SettingsOverlay.GROUP,
			&"map_ui", &"inventory_ui", &"pause_ui", &"bank_ui",
		]
	)
	InputDeviceTracker.on_mobile = true
	InputDeviceTracker._set_device(InputDeviceTracker.Device.TOUCH)
	add_child(auto_free(PLAYER_SCENE.instantiate()))
	_hud = auto_free(HUD_SCENE.instantiate()) as TouchHud
	add_child(_hud)
	_settings = auto_free(SETTINGS_SCENE.instantiate()) as SettingsOverlay
	add_child(_settings)


func after_test() -> void:
	_settings.close()
	Game.title_demo_active = _was_title_demo
	InputDeviceTracker._set_device(InputDeviceTracker.Device.KEYS)
	InputDeviceTracker.on_mobile = OS.has_feature("android") or OS.has_feature("ios")


func _screen(group: StringName) -> _Screen:
	var screen := auto_free(_Screen.new()) as _Screen
	screen.add_to_group(group)
	add_child(screen)
	return screen


func _log() -> _ActionLog:
	var trace := auto_free(_ActionLog.new()) as _ActionLog
	add_child(trace)
	return trace


func test_the_joystick_is_a_knob_inside_a_circle() -> void:
	_hud._refresh()
	var center := Vector2(400, 300)
	_hud.show_stick(center, center + Vector2(800, 0), 100.0, 36.0)
	assert_bool(_hud.stick_showing()).is_true()
	var base := _hud.get_node("Root/Stick/Base") as Control
	var knob := _hud.get_node("Root/Stick/Knob") as Control
	assert_float(knob.size.x).is_less(base.size.x)
	assert_float(knob.size.y).is_less(base.size.y)
	var base_style := base.get_theme_stylebox(&"panel") as StyleBoxFlat
	var knob_style := knob.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_int(base_style.corner_radius_top_left).is_greater_equal(int(base.size.x * 0.5) - 1)
	assert_int(knob_style.corner_radius_top_left).is_greater_equal(int(knob.size.x * 0.5) - 1)
	assert_bool(base.get_global_rect().grow(1.0).encloses(knob.get_global_rect())).is_true()
	## Back toward the middle, the knob follows and still sits inside the ring.
	_hud.show_stick(center, center + Vector2(20, -10), 100.0, 36.0)
	assert_bool(base.get_global_rect().grow(1.0).encloses(knob.get_global_rect())).is_true()
	_hud.hide_stick()
	assert_bool(_hud.stick_showing()).is_false()


func test_three_tabs_and_no_b() -> void:
	_hud._refresh()
	assert_bool(_hud.get_node("Root/TabBar").visible).is_true()
	assert_object(_hud.get_node_or_null("Root/TabBar/Tabs/Map")).is_not_null()
	var tabs := _hud.get_node("Root/TabBar/Tabs")
	assert_int(tabs.get_child_count()).is_equal(3)
	var labels: Array[String] = []
	for button: Button in tabs.get_children():
		labels.append(button.tooltip_text)
	assert_array(labels).contains_exactly(["Map", "Inventory", "Settings"])
	assert_object(_hud.get_node_or_null("Root/Buttons/B")).is_null()


func test_mobile_title_demo_hides_the_bar_before_and_after_touch() -> void:
	Game.title_demo_active = true
	InputDeviceTracker._set_device(InputDeviceTracker.Device.KEYS)
	_hud._refresh()
	assert_bool((_hud.get_node("Root/TabBar") as Control).is_visible_in_tree()).is_false()
	InputDeviceTracker._set_device(InputDeviceTracker.Device.TOUCH)
	_hud._refresh()
	assert_bool((_hud.get_node("Root/TabBar") as Control).is_visible_in_tree()).is_false()
	assert_bool(_hud.is_showing()).is_false()
	Game.title_demo_active = false
	_hud._refresh()
	assert_bool((_hud.get_node("Root/TabBar") as Control).is_visible_in_tree()).is_true()


func test_a_tab_sends_its_action() -> void:
	var trace: _ActionLog = _log()
	(_hud.get_node("Root/TabBar/Tabs/Inventory") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(trace.actions).contains_exactly([&"inventory"])


func test_another_tab_switches_the_open_screen() -> void:
	var map: _Screen = _screen(&"map_ui")
	map.open = true
	_hud._refresh()
	assert_str(String(_hud.open_tab())).is_equal("map")
	## Its own screen keeps the bar up, with that tab lit.
	assert_bool(_hud.get_node("Root/TabBar").visible).is_true()
	assert_bool((_hud.get_node("Root/TabBar/Tabs/Map") as Button).button_pressed).is_true()
	assert_bool((_hud.get_node("Root/TabBar/Tabs/Settings") as Button).button_pressed).is_false()
	var trace: _ActionLog = _log()
	await _hud.press_tab(&"settings")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(trace.actions).contains_exactly([&"map"])
	assert_bool(_settings.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()


func test_settings_button_opens_directly_and_stays_lit() -> void:
	(_hud.get_node("Root/TabBar/Tabs/Settings") as Button).pressed.emit()
	_hud._refresh()
	assert_bool(_settings.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_str(String(_hud.open_tab())).is_equal("settings")
	assert_bool(_hud.get_node("Root/TabBar").visible).is_true()
	assert_bool((_hud.get_node("Root/TabBar/Tabs/Settings") as Button).button_pressed).is_true()
	await _hud.press_tab(&"settings")
	assert_bool(_settings.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()


func test_settings_back_resumes_gameplay() -> void:
	await _hud.press_tab(&"settings")
	(_settings.get_node("%BackButton") as Button).pressed.emit()
	_hud._refresh()
	assert_bool(_settings.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_str(String(_hud.open_tab())).is_empty()


func test_settings_close_keeps_an_existing_pause() -> void:
	get_tree().paused = true
	await _hud.press_tab(&"settings")
	await _hud.press_tab(&"settings")
	assert_bool(_settings.is_open()).is_false()
	assert_bool(get_tree().paused).is_true()
	get_tree().paused = false


func test_switching_from_settings_resumes_before_sending_inventory_action() -> void:
	await _hud.press_tab(&"settings")
	var trace: _ActionLog = _log()
	await _hud.press_tab(&"inventory")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(_settings.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_array(trace.actions).contains_exactly([&"inventory"])


func test_map_button_sends_the_map_action() -> void:
	var trace: _ActionLog = _log()
	(_hud.get_node("Root/TabBar/Tabs/Map") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(trace.actions).contains_exactly([&"map"])


func test_the_lit_tab_closes_its_screen() -> void:
	var pockets: _Screen = _screen(&"inventory_ui")
	pockets.open = true
	var trace: _ActionLog = _log()
	await _hud.press_tab(&"inventory")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(trace.actions).contains_exactly([&"inventory"])


func test_buttons_are_round_white_circles_stacked_in_the_top_right() -> void:
	await get_tree().process_frame
	_hud._apply_tab_layout(1.0, 0.0)
	await get_tree().process_frame
	var root := (_hud.get_node("Root") as Control).get_global_rect()
	var map := (_hud.get_node("Root/TabBar/Tabs/Map") as Control).get_global_rect()
	var inventory := (_hud.get_node("Root/TabBar/Tabs/Inventory") as Control).get_global_rect()
	var settings := (_hud.get_node("Root/TabBar/Tabs/Settings") as Control).get_global_rect()
	assert_float(map.size.x).is_equal_approx(TouchHud.BUTTON_PT, 1.0)
	assert_float(map.size.y).is_equal_approx(map.size.x, 1.0)
	assert_float(map.end.x).is_equal_approx(root.end.x - TouchHud.MARGIN_PT, 1.0)
	assert_float(map.position.y).is_equal_approx(root.position.y + TouchHud.MARGIN_PT, 1.0)
	assert_float(inventory.position.x).is_equal_approx(map.position.x, 1.0)
	assert_float(inventory.position.y).is_greater_equal(map.end.y)
	assert_float(settings.position.y).is_greater_equal(inventory.end.y)
	var idle := (_hud.get_node("Root/TabBar/Tabs/Map") as Button).get_theme_stylebox(&"normal") as StyleBoxFlat
	assert_object(idle).is_not_null()
	assert_bool(idle.bg_color.is_equal_approx(Color.WHITE)).is_true()
	assert_int(idle.corner_radius_top_left).is_greater_equal(int(TouchHud.BUTTON_PT * 0.5))


func test_the_stack_stays_inside_the_safe_area() -> void:
	## The stack hangs off the safe-fitted root, so an inset on that root moves it in.
	var root := _hud.get_node("Root") as Control
	root.offset_right = -40.0
	root.offset_top = 30.0
	await get_tree().process_frame
	_hud._apply_tab_layout(1.0, 40.0)
	await get_tree().process_frame
	var screen := get_viewport().get_visible_rect()
	var map := (_hud.get_node("Root/TabBar/Tabs/Map") as Control).get_global_rect()
	assert_float(map.end.x).is_equal_approx(screen.end.x - 40.0 - TouchHud.MARGIN_PT, 1.0)
	assert_float(map.position.y).is_equal_approx(30.0 + TouchHud.MARGIN_PT, 1.0)


func test_walking_slides_the_bar_away_and_standing_brings_it_back() -> void:
	await get_tree().process_frame
	_hud._apply_tab_layout(1.0, 0.0)
	var player := Player.find(get_tree())
	## Drive the walk by hand; the frame loop would see the idle player in between.
	_hud.set_process(false)
	_hud._update_tuck(0.0)
	assert_bool(_hud.is_tucked()).is_false()
	player.velocity = Vector3(2.0, 0.0, 0.0)
	_hud._update_tuck(0.016)
	assert_bool(_hud.is_tucked()).is_true()
	await get_tree().create_timer(TouchHud.TUCK_SEC + 0.1).timeout
	var screen := get_viewport().get_visible_rect()
	var bar := (_hud.get_node("Root/TabBar") as Control).get_global_rect()
	assert_float(bar.position.x).is_greater_equal(screen.end.x - 1.0)
	## Stopped: it waits a beat, then returns.
	player.velocity = Vector3.ZERO
	_hud._update_tuck(TouchHud.RETURN_DELAY_SEC * 0.5)
	assert_bool(_hud.is_tucked()).is_true()
	_hud._update_tuck(TouchHud.RETURN_DELAY_SEC)
	assert_bool(_hud.is_tucked()).is_false()
	await get_tree().create_timer(TouchHud.UNTUCK_SEC + 0.1).timeout
	bar = (_hud.get_node("Root/TabBar") as Control).get_global_rect()
	assert_float(bar.end.x).is_equal_approx(screen.end.x - TouchHud.MARGIN_PT, 1.0)


func test_a_dragged_stick_tucks_the_bar() -> void:
	_hud._update_tuck(0.0)
	_hud.show_stick(Vector2(300, 300), Vector2(340, 300), 100.0, 36.0)
	_hud._update_tuck(0.016)
	assert_bool(_hud.is_tucked()).is_true()
	_hud.hide_stick()


func test_an_open_tab_screen_keeps_the_bar_up_while_walking() -> void:
	var map: _Screen = _screen(&"map_ui")
	map.open = true
	Player.find(get_tree()).velocity = Vector3(2.0, 0.0, 0.0)
	_hud._update_tuck(0.016)
	assert_bool(_hud.is_tucked()).is_false()


func test_px_per_point_uses_the_phone_screen_scale() -> void:
	var portrait := TouchHud.px_per_point(Vector2(1179, 2556), 3.0, Vector2(1280, 2775))
	assert_float(portrait).is_equal_approx(1280.0 / 393.0, 0.02)
	var landscape := TouchHud.px_per_point(Vector2(2556, 1179), 3.0, Vector2(1561, 720))
	assert_float(landscape).is_equal_approx(1561.0 / 852.0, 0.02)
	var desktop := TouchHud.px_per_point(Vector2(2560, 1440), 2.0, Vector2(1280, 720))
	assert_float(desktop).is_equal_approx(1.0, 0.01)


func test_phone_scale_sizes_the_buttons_in_points() -> void:
	await get_tree().process_frame
	var px := 1280.0 / 393.0
	_hud._apply_tab_layout(px, 0.0)
	await get_tree().process_frame
	var map := _hud.get_node("Root/TabBar/Tabs/Map") as Button
	assert_int(map.get_theme_constant(&"icon_max_width")).is_equal(int(round(TouchHud.ICON_PT * px)))
	assert_float(map.size.x).is_equal_approx(TouchHud.BUTTON_PT * px, 1.0)


func test_hidden_under_other_screens_and_on_a_desktop() -> void:
	var bank: _Screen = _screen(&"bank_ui")
	bank.open = true
	_hud._refresh()
	assert_bool(_hud.get_node("Root/TabBar").visible).is_false()
	bank.open = false
	InputDeviceTracker.on_mobile = false
	_hud._refresh()
	assert_bool(_hud.get_node("Root").visible).is_false()
