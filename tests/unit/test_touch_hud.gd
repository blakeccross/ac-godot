class_name TestTouchHud
extends GdUnitTestSuite

## The touch tab bar: Map, Pockets and Menu send their keys' actions, stay up over their own
## screens with that tab lit, and switch between them.

const PLAYER_SCENE := preload("res://features/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/touch_hud.tscn")


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


func before_test() -> void:
	TestIsolation.forget_groups(
		get_tree(), [Player.GROUP, TouchHud.GROUP, &"map_ui", &"inventory_ui", &"pause_ui", &"bank_ui"]
	)
	InputDeviceTracker.on_mobile = true
	InputDeviceTracker._set_device(InputDeviceTracker.Device.TOUCH)
	add_child(auto_free(PLAYER_SCENE.instantiate()))
	_hud = auto_free(HUD_SCENE.instantiate()) as TouchHud
	add_child(_hud)


func after_test() -> void:
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
	assert_object(_hud.get_node_or_null("Root/TabBar/Tabs/Pockets")).is_not_null()
	assert_object(_hud.get_node_or_null("Root/TabBar/Tabs/Menu")).is_not_null()
	assert_object(_hud.get_node_or_null("Root/Buttons/B")).is_null()


func test_a_tab_sends_its_action() -> void:
	var log: _ActionLog = _log()
	(_hud.get_node("Root/TabBar/Tabs/Pockets") as Button).pressed.emit()
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
	assert_bool((_hud.get_node("Root/TabBar/Tabs/Menu") as Button).button_pressed).is_false()
	var log: _ActionLog = _log()
	await _hud.press_tab(&"pause_menu")
	await get_tree().process_frame
	await get_tree().process_frame
	## Close the map, then open the menu.
	assert_array(log.actions).contains_exactly([&"map", &"pause_menu"])


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
