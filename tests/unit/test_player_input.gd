class_name TestPlayerInput
extends GdUnitTestSuite

## The seam touch and the title demo drive the player through.


func test_holding_a_latches_one_press() -> void:
	var source := PlayerInput.new()
	source.set_a(true)
	source.set_a(true)
	assert_bool(source.a_held).is_true()
	assert_bool(source.consume_a_pressed()).is_true()
	assert_bool(source.consume_a_pressed()).is_false()


func test_press_survives_release_before_the_tick() -> void:
	var source := PlayerInput.new()
	source.set_b(true)
	source.set_b(false)
	assert_bool(source.b_held).is_false()
	assert_bool(source.consume_b_pressed()).is_true()


func test_tap_presses_without_holding() -> void:
	var source := PlayerInput.new()
	source.tap_a()
	assert_bool(source.a_held).is_false()
	assert_bool(source.consume_a_pressed()).is_true()


func test_clear_keeps_the_demo_flag() -> void:
	var source := TitleDemoInput.new()
	source.move = Vector2.RIGHT
	source.set_a(true)
	source.dash_held = true
	source.clear()
	assert_vector(source.move).is_equal(Vector2.ZERO)
	assert_bool(source.a_held or source.a_pressed or source.dash_held).is_false()
	assert_bool(source.demo).is_true()


func test_device_tracker_follows_the_last_event() -> void:
	var changes: Array[int] = []
	var record := func(device: int) -> void: changes.append(device)
	InputDeviceTracker.device_changed.connect(record)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	InputDeviceTracker._input(touch)
	assert_bool(InputDeviceTracker.is_touch()).is_true()
	InputDeviceTracker._input(InputEventScreenDrag.new())
	var key := InputEventKey.new()
	key.pressed = true
	InputDeviceTracker._input(key)
	assert_bool(InputDeviceTracker.is_touch()).is_false()
	InputDeviceTracker.device_changed.disconnect(record)
	assert_array(changes).is_equal([1, 0])
