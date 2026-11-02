class_name TestTouchDriver
extends GdUnitTestSuite

## Touch through the player's `PlayerInput`: drag a joystick, hold to follow, tap the player for A.

const PLAYER_SCENE := preload("res://features/player/player.tscn")

var _cam: Camera3D


func before_test() -> void:
	TestIsolation.forget_groups(get_tree(), [Player.GROUP, World.GROUP, TouchHud.GROUP])
	InputDeviceTracker.on_mobile = OS.has_feature("android") or OS.has_feature("ios")


func _setup() -> Player:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(auto_free(floor_body))
	var player: Player = auto_free(PLAYER_SCENE.instantiate()) as Player
	add_child(player)
	player.global_position = Vector3.ZERO
	_cam = auto_free(Camera3D.new()) as Camera3D
	add_child(_cam)
	## The game's framing: 20° field of view, 620 GX (31 m) back at 45°.
	_cam.fov = 20.0
	_cam.global_position = FollowCamera.DEFAULT_OFFSET
	_cam.look_at(Vector3.ZERO)
	_cam.current = true
	return player


func _driver(player: Player) -> TouchDriver:
	return player.get_node("TouchDriver") as TouchDriver


func _screen(world: Vector3) -> Vector2:
	return _cam.unproject_position(world)


func test_holding_on_the_ground_steers_toward_it() -> void:
	var player: Player = _setup()
	await get_tree().process_frame
	var driver: TouchDriver = _driver(player)
	driver.press(_screen(Vector3(2, 0, 0)))
	driver._physics_process(TouchDriver.HOLD_SEC + 0.01)
	assert_bool(driver.is_following()).is_true()
	assert_object(player.scripted_input).is_same(driver.source)
	var wish: Vector3 = player._camera_wish(driver.source.move)
	assert_float(wish.normalized().dot(Vector3.RIGHT)).is_greater(0.99)
	assert_bool(driver.source.dash_held).is_false()
	assert_bool(driver.is_sticking()).is_false()
	driver.lift(driver._now)
	## Far ahead, still held in place: run.
	driver.press(_screen(Vector3(6, 0, 0)))
	driver._physics_process(TouchDriver.HOLD_SEC + 0.01)
	assert_bool(driver.is_following()).is_true()
	assert_bool(driver.source.dash_held).is_true()
	driver.lift(driver._now)
	## On the spot: stand. A point this close can also count as a tap on the player.
	driver.press(_screen(Vector3(0.1, 0, 0)))
	driver._on_self = false
	driver._physics_process(TouchDriver.HOLD_SEC + 0.01)
	assert_vector(driver.source.move).is_equal(Vector2.ZERO)
	driver.lift(driver._now)
	assert_vector(driver.source.move).is_equal(Vector2.ZERO)
	assert_bool(driver.is_following()).is_false()


func test_the_player_walks_to_a_held_point() -> void:
	var player: Player = _setup()
	await get_tree().process_frame
	var driver: TouchDriver = _driver(player)
	var goal := Vector3(3, 0, 1)
	driver.press(_screen(goal))
	for _i: int in 150:
		## Keep the finger on the same ground point as the camera stays put.
		driver._now = _screen(goal)
		await get_tree().physics_frame
	var off := Vector2(player.global_position.x - goal.x, player.global_position.z - goal.z)
	assert_float(off.length()).is_less(0.6)


func test_a_short_tap_on_the_player_is_one_a() -> void:
	var player: Player = _setup()
	await get_tree().process_frame
	var driver: TouchDriver = _driver(player)
	var me: Vector2 = _screen(player.global_position + Vector3.UP * TouchDriver.BODY_MID)
	driver.press(me)
	driver._physics_process(0.05)
	driver.lift(me)
	assert_bool(driver.is_following()).is_false()
	assert_bool(driver.source.consume_a_pressed()).is_true()
	assert_bool(driver.source.consume_a_pressed()).is_false()


func test_a_key_hands_the_player_back() -> void:
	var player: Player = _setup()
	await get_tree().process_frame
	var driver: TouchDriver = _driver(player)
	driver.press(_screen(Vector3(2, 0, 0)))
	assert_object(player.scripted_input).is_same(driver.source)
	driver._on_device_changed(InputDeviceTracker.Device.KEYS)
	assert_object(player.scripted_input).is_null()


func test_the_title_demo_recording_is_never_replaced() -> void:
	var player: Player = _setup()
	await get_tree().process_frame
	var demo := TitleDemoInput.new()
	player.scripted_input = demo
	var driver: TouchDriver = _driver(player)
	driver.press(_screen(Vector3(2, 0, 0)))
	assert_object(player.scripted_input).is_same(demo)
	player.scripted_input = null


func test_a_drag_steers_with_the_joystick_until_the_finger_lifts() -> void:
	var was_mobile: bool = InputDeviceTracker.on_mobile
	var was_demo: bool = Game.title_demo_active
	InputDeviceTracker.on_mobile = true
	InputDeviceTracker._set_device(InputDeviceTracker.Device.TOUCH)
	Game.title_demo_active = false
	var player: Player = _setup()
	var hud: TouchHud = auto_free(load("res://scenes/ui/touch_hud.tscn").instantiate()) as TouchHud
	add_child(hud)
	await get_tree().process_frame
	var driver: TouchDriver = _driver(player)
	var start := Vector2(200, 80)
	driver.press(start)
	## Well past the ring: full tilt to the right runs, and the knob is on screen.
	driver._now = start + Vector2(2000, 0)
	driver._physics_process(0.016)
	assert_bool(driver.is_sticking()).is_true()
	assert_bool(driver.is_following()).is_false()
	assert_bool(driver.is_walking()).is_false()
	assert_bool(hud.stick_showing()).is_true()
	assert_bool(hud.get_node("Root/Stick").is_visible_in_tree()).is_true()
	var wish: Vector3 = player._camera_wish(driver.source.move)
	assert_float(wish.normalized().dot(Vector3.RIGHT)).is_greater(0.99)
	assert_float(driver.source.move.length()).is_equal_approx(1.0, 0.02)
	assert_bool(driver.source.dash_held).is_true()
	## Up the screen is away from the camera.
	driver._now = start + Vector2(0, -2000)
	driver._physics_process(0.016)
	wish = player._camera_wish(driver.source.move)
	assert_float(wish.normalized().dot(Vector3(0, 0, -1))).is_greater(0.99)
	## Just outside a tap: the stick is up, but not yet a run.
	var slop: float = TouchDriver.TAP_SLOP_PX * driver._px() + 1.0
	var travel: float = driver._stick_measures().x - driver._stick_measures().y
	if slop < travel:
		driver._now = start + Vector2(slop, 0)
		driver._physics_process(0.016)
		assert_bool(driver.is_sticking()).is_true()
		assert_float(driver.source.move.length()).is_less(TouchDriver.STICK_RUN)
		assert_bool(driver.source.dash_held).is_false()
	var from: Vector3 = player.global_position
	driver._now = start + Vector2(2000, 0)
	for _i: int in 40:
		await get_tree().physics_frame
	assert_float(player.global_position.x).is_greater(from.x + 0.2)
	driver.lift(driver._now)
	assert_bool(driver.is_sticking()).is_false()
	assert_bool(hud.stick_showing()).is_false()
	assert_vector(driver.source.move).is_equal(Vector2.ZERO)
	assert_bool(driver.source.dash_held).is_false()
	InputDeviceTracker.on_mobile = was_mobile
	InputDeviceTracker._set_device(InputDeviceTracker.Device.KEYS)
	Game.title_demo_active = was_demo


func test_the_hud_sends_real_actions() -> void:
	var hud: TouchHud = auto_free(load("res://scenes/ui/touch_hud.tscn").instantiate()) as TouchHud
	add_child(hud)
	assert_object(hud.get_node_or_null("Root/Stick/Base")).is_not_null()
	assert_object(hud.get_node_or_null("Root/Stick/Knob")).is_not_null()
	assert_bool(hud.stick_showing()).is_false()
	for node: Node in hud.find_children("*", "", true, false):
		var node_name := String(node.name).to_lower()
		assert_bool(node_name.contains("dpad") or node_name == "pad").is_false()
	var seen: Array[StringName] = []
	var catcher := _ActionCatcher.new()
	catcher.seen = seen
	add_child(auto_free(catcher))
	hud.send_action(&"map")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(seen.has(&"map")).is_true()


class _ActionCatcher extends Node:
	var seen: Array[StringName] = []

	func _input(event: InputEvent) -> void:
		if event is InputEventAction and (event as InputEventAction).pressed:
			seen.append((event as InputEventAction).action)


func test_a_tap_on_the_ground_walks_there() -> void:
	var player: Player = _setup()
	await get_tree().process_frame
	var driver: TouchDriver = _driver(player)
	var goal := Vector3(4, 0, 2)
	var at: Vector2 = _screen(goal)
	driver.press(at)
	driver.lift(at)
	assert_bool(driver.is_walking()).is_true()
	for _i: int in 180:
		await get_tree().physics_frame
		if not driver.is_walking():
			break
	assert_bool(driver.is_walking()).is_false()
	var off := Vector2(player.global_position.x - goal.x, player.global_position.z - goal.z)
	assert_float(off.length()).is_less(0.5)
	assert_bool(driver.source.dash_held).is_false()
