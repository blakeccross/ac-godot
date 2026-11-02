class_name TestTouchMenuPad
extends GdUnitTestSuite

## A tap advances a waiting page. The pad has no on-screen buttons.


class _KeyLog extends Node:
	var keys: Array[Key] = []

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.is_pressed():
			keys.append((event as InputEventKey).keycode)


class _Menu extends Node:
	var open: bool = true

	func is_open() -> bool:
		return open


func before_test() -> void:
	InputDeviceTracker.on_mobile = true


func after_test() -> void:
	InputDeviceTracker._set_device(InputDeviceTracker.Device.KEYS)
	InputDeviceTracker.on_mobile = OS.has_feature("android") or OS.has_feature("ios")


func _pad() -> TouchMenuPad:
	return TouchMenuPad.find(get_tree())


func test_the_pad_has_no_buttons() -> void:
	var pad: TouchMenuPad = _pad()
	assert_object(pad).is_not_null()
	assert_object(pad.get_node_or_null("Root")).is_null()
	assert_int(pad.get_child_count()).is_equal(0)


func test_menu_open_tracks_an_overlay() -> void:
	var menu := auto_free(_Menu.new()) as _Menu
	menu.add_to_group(&"bank_ui")
	add_child(menu)
	assert_bool(TouchMenuPad.menu_open(get_tree())).is_true()
	menu.open = false
	assert_bool(TouchMenuPad.menu_open(get_tree())).is_false()


func test_a_tap_is_ok_on_the_title() -> void:
	TestIsolation.forget_groups(get_tree(), [Player.GROUP])
	var trace := auto_free(_KeyLog.new()) as _KeyLog
	add_child(trace)
	InputDeviceTracker._set_device(InputDeviceTracker.Device.TOUCH)
	var pad: TouchMenuPad = _pad()
	assert_bool(pad.taps_accept()).is_true()
	var tap := InputEventScreenTouch.new()
	tap.position = Vector2(640, 200)
	tap.pressed = false
	pad._unhandled_input(tap)
	await get_tree().process_frame
	assert_array(trace.keys).contains([KEY_ENTER])
	assert_bool(InputDeviceTracker.is_touch()).is_true()


func test_a_tap_is_start_on_the_title_even_with_the_demo_player() -> void:
	var marker := auto_free(Node.new()) as Node
	marker.add_to_group(TouchMenuPad.TITLE_GROUP)
	add_child(marker)
	assert_bool(_pad().taps_accept()).is_true()


func test_map_does_not_take_taps() -> void:
	var map := auto_free(_Menu.new()) as _Menu
	map.add_to_group(MapOverlay.GROUP)
	add_child(map)
	assert_bool(_pad().wanted()).is_false()


func test_a_talk_page_is_not_also_accepted_by_the_pad() -> void:
	## The finger's click already turns the page. Enter from the pad would turn
	## a second one and can dismiss the house-payment pockets as they open.
	var ui: DialogueOverlay = load("res://scenes/ui/dialogue_overlay.tscn").instantiate()
	auto_free(ui)
	add_child(ui)
	ui.say("The house comes to 19,800 Bells.")
	assert_bool(ui.is_open()).is_true()
	assert_bool(_pad().taps_accept()).is_false()
	ui.close(true)
	assert_bool(ui.is_open()).is_false()


func test_title_taps_do_not_accept_while_an_overlay_is_open() -> void:
	var title := auto_free(Node.new()) as Node
	title.add_to_group(TouchMenuPad.TITLE_GROUP)
	add_child(title)
	var map := auto_free(_Menu.new()) as _Menu
	map.add_to_group(MapOverlay.GROUP)
	add_child(map)
	assert_bool(_pad().taps_accept()).is_false()
