class_name TestTouchMenuPad
extends GdUnitTestSuite

## The menu pad sends the keys a keyboard would, marked as a finger's.


class _KeyLog extends Node:
	var keys: Array[Key] = []

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.is_pressed():
			keys.append((event as InputEventKey).keycode)


class _Menu extends Node:
	var open: bool = true

	func is_open() -> bool:
		return open


func after_test() -> void:
	InputDeviceTracker._set_device(InputDeviceTracker.Device.KEYS)


func _pad() -> TouchMenuPad:
	return TouchMenuPad.find(get_tree())


func test_ok_and_back_send_enter_and_escape_without_leaving_touch() -> void:
	var log := auto_free(_KeyLog.new()) as _KeyLog
	add_child(log)
	InputDeviceTracker._set_device(InputDeviceTracker.Device.TOUCH)
	var pad: TouchMenuPad = _pad()
	assert_object(pad).is_not_null()
	pad.get_node("Root/Confirm/Ok").pressed.emit()
	pad.get_node("Root/Confirm/Back").pressed.emit()
	await get_tree().process_frame
	assert_array(log.keys).contains_exactly([KEY_ENTER, KEY_ESCAPE])
	assert_bool(InputDeviceTracker.is_touch()).is_true()


func test_an_arrow_held_repeats_until_let_go() -> void:
	var log := auto_free(_KeyLog.new()) as _KeyLog
	add_child(log)
	InputDeviceTracker._set_device(InputDeviceTracker.Device.TOUCH)
	TestIsolation.forget_groups(get_tree(), [Player.GROUP])
	var pad: TouchMenuPad = _pad()
	pad._refresh()
	var up: Button = pad.get_node("Root/Arrows/Up")
	up.button_down.emit()
	await get_tree().create_timer(1.0).timeout
	up.button_up.emit()
	var count: int = log.keys.size()
	## The press, then at least one repeat.
	assert_int(count).is_greater(1)
	await get_tree().create_timer(0.3).timeout
	assert_int(log.keys.size()).is_equal(count)
	for key: Key in log.keys:
		assert_int(key).is_equal(KEY_UP)


func test_shown_only_for_touch_with_a_menu_up() -> void:
	var pad: TouchMenuPad = _pad()
	var menu := auto_free(_Menu.new()) as _Menu
	menu.add_to_group(&"bank_ui")
	add_child(menu)
	InputDeviceTracker._set_device(InputDeviceTracker.Device.KEYS)
	pad._refresh()
	assert_bool(pad.get_node("Root").visible).is_false()
	InputDeviceTracker._set_device(InputDeviceTracker.Device.TOUCH)
	pad._refresh()
	assert_bool(pad.get_node("Root").visible).is_true()
	assert_bool(TouchMenuPad.menu_open(get_tree())).is_true()
	menu.open = false
	assert_bool(TouchMenuPad.menu_open(get_tree())).is_false()


func test_a_tap_off_the_pad_is_ok_on_the_title() -> void:
	TestIsolation.forget_groups(get_tree(), [Player.GROUP])
	var log := auto_free(_KeyLog.new()) as _KeyLog
	add_child(log)
	InputDeviceTracker._set_device(InputDeviceTracker.Device.TOUCH)
	var pad: TouchMenuPad = _pad()
	pad._refresh()
	assert_bool(pad.taps_accept()).is_true()
	var tap := InputEventScreenTouch.new()
	tap.position = Vector2(640, 200)
	tap.pressed = false
	pad._unhandled_input(tap)
	await get_tree().process_frame
	assert_array(log.keys).contains([KEY_ENTER])
