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
	var log := auto_free(_ActionLog.new()) as _ActionLog
	add_child(log)
	return log


func test_three_tabs_and_no_b() -> void:
	_hud._refresh()
	assert_bool(_hud.get_node("Root/TabBar").visible).is_true()
	assert_object(_hud.get_node_or_null("Root/TabBar/Tabs/Map")).is_not_null()
	var tabs := _hud.get_node("Root/TabBar/Tabs")
	assert_int(tabs.get_child_count()).is_equal(3)
	var labels: Array[String] = []
	for button: Button in tabs.get_children():
		labels.append(button.text)
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
	var log: _ActionLog = _log()
	(_hud.get_node("Root/TabBar/Tabs/Inventory") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(log.actions).contains_exactly([&"inventory"])


func test_another_tab_switches_the_open_screen() -> void:
	var map: _Screen = _screen(&"map_ui")
	map.open = true
	_hud._refresh()
	assert_str(String(_hud.open_tab())).is_equal("map")
	## Its own screen keeps the bar up, with that tab lit.
	assert_bool(_hud.get_node("Root/TabBar").visible).is_true()
	assert_bool((_hud.get_node("Root/TabBar/Tabs/Map") as Button).button_pressed).is_true()
	assert_bool((_hud.get_node("Root/TabBar/Tabs/Settings") as Button).button_pressed).is_false()
	var log: _ActionLog = _log()
	await _hud.press_tab(&"settings")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(log.actions).contains_exactly([&"map"])
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
	var log: _ActionLog = _log()
	await _hud.press_tab(&"inventory")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(_settings.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_array(log.actions).contains_exactly([&"inventory"])


func test_map_button_sends_the_map_action() -> void:
	var log: _ActionLog = _log()
	(_hud.get_node("Root/TabBar/Tabs/Map") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(log.actions).contains_exactly([&"map"])


func test_the_lit_tab_closes_its_screen() -> void:
	var pockets: _Screen = _screen(&"inventory_ui")
	pockets.open = true
	var log: _ActionLog = _log()
	await _hud.press_tab(&"inventory")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(log.actions).contains_exactly([&"inventory"])


func test_hidden_under_other_screens_and_on_a_desktop() -> void:
	var bank: _Screen = _screen(&"bank_ui")
	bank.open = true
	_hud._refresh()
	assert_bool(_hud.get_node("Root/TabBar").visible).is_false()
	bank.open = false
	InputDeviceTracker.on_mobile = false
	_hud._refresh()
	assert_bool(_hud.get_node("Root").visible).is_false()
