class_name TestTouchInteract
extends GdUnitTestSuite

## Touch on things: tap a host, walk up, face it, press the button its verb is on.

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/touch_hud.tscn")


class _Host extends Node3D:
	var verbs: Array[Interaction] = []
	var used: Array[StringName] = []

	func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
		return verbs

	func interact(action: Interaction, _ctx: InteractionContext) -> bool:
		used.append(action.id)
		return true


var _cam: Camera3D


func before_test() -> void:
	TestIsolation.forget_groups(get_tree(), [Player.GROUP, World.GROUP, TouchHud.GROUP])
	Game.reset_session()
	## Chips are on-screen buttons: as on a phone.
	InputDeviceTracker.on_mobile = true


func after_test() -> void:
	Game.reset_session()
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
	_cam.fov = 20.0
	_cam.global_position = FollowCamera.DEFAULT_OFFSET
	_cam.look_at(Vector3.ZERO)
	_cam.current = true
	return player


func _host(at: Vector3, verbs: Array[Interaction], radius: float = 0.5) -> _Host:
	var host := _Host.new()
	host.verbs = verbs
	var volume := InteractVolume.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	shape.position = Vector3.UP * 0.5
	volume.add_child(shape)
	host.add_child(volume)
	add_child(auto_free(host))
	host.global_position = at
	return host


func _driver(player: Player) -> TouchDriver:
	return player.get_node("TouchDriver") as TouchDriver


func _screen(world: Vector3) -> Vector2:
	return _cam.unproject_position(world)


func _tap(driver: TouchDriver, at: Vector2) -> void:
	driver.press(at)
	driver.lift(at)


func _run(frames: int) -> void:
	for _i: int in frames:
		await get_tree().physics_frame


func test_object_pick_finds_the_volume_and_a_near_miss() -> void:
	_setup()
	var host: _Host = _host(Vector3(4, 0, 0), [Interaction.of(Interaction.TALK, "Talk")], 0.3)
	await _run(2)
	var mid: Vector3 = host.global_position + Vector3.UP * 0.5
	var hit: InteractVolume = TouchPick.object(_cam, _screen(mid))
	assert_object(hit).is_not_null()
	assert_object(hit.host).is_same(host)
	## 20 px off the edge still gets it through the ring.
	var edge: Vector2 = _screen(mid + Vector3.RIGHT * 0.3)
	var off: Vector2 = edge + (edge - _screen(mid)).normalized() * 20.0
	assert_object(TouchPick.object(_cam, off)).is_not_null()
	## Far from anything: nothing.
	assert_object(TouchPick.object(_cam, _screen(Vector3(-6, 0, 3)))).is_null()


func test_a_tap_on_a_host_walks_up_and_presses_a() -> void:
	var player: Player = _setup()
	var host: _Host = _host(Vector3(6, 0, 0), [Interaction.of(Interaction.TALK, "Talk", 5)])
	await _run(2)
	var driver: TouchDriver = _driver(player)
	_tap(driver, _screen(host.global_position + Vector3.UP * 0.5))
	assert_bool(driver.is_acting()).is_true()
	for _i: int in 300:
		await get_tree().physics_frame
		if not host.used.is_empty():
			break
	assert_array(host.used).contains_exactly([Interaction.TALK])
	var to: Vector3 = host.global_position - player.global_position
	assert_float(Vector2(to.x, to.z).length()).is_less_equal(TouchDriver.REACH + 0.2)
	## Facing it.
	var ahead := Vector3(sin(player.facing_yaw()), 0.0, cos(player.facing_yaw()))
	assert_float(ahead.dot(Vector3(to.x, 0.0, to.z).normalized())).is_greater(0.9)


func test_something_picked_up_goes_on_b() -> void:
	var player: Player = _setup()
	var host: _Host = _host(Vector3(-5, 0, 2), [Interaction.of(Interaction.PICK_UP, "Pick up", 5)])
	await _run(2)
	var driver: TouchDriver = _driver(player)
	var verbs: Dictionary = driver.buttons_for(InteractVolume.of(host))
	assert_object(verbs["a"]).is_null()
	assert_object(verbs["b"]).is_not_null()
	_tap(driver, _screen(host.global_position + Vector3.UP * 0.5))
	for _i: int in 300:
		await get_tree().physics_frame
		if not host.used.is_empty():
			break
	assert_array(host.used).contains_exactly([Interaction.PICK_UP])


func test_two_verbs_show_chips_and_a_chip_uses_its_button() -> void:
	var player: Player = _setup()
	var hud: TouchHud = auto_free(HUD_SCENE.instantiate()) as TouchHud
	add_child(hud)
	InputDeviceTracker._set_device(InputDeviceTracker.Device.TOUCH)
	var host: _Host = _host(
		Vector3(5, 0, -2),
		[Interaction.of(Interaction.SIT, "Sit", 5), Interaction.of(Interaction.PICK_UP, "Move", 5)]
	)
	await _run(2)
	var driver: TouchDriver = _driver(player)
	_tap(driver, _screen(host.global_position + Vector3.UP * 0.5))
	await get_tree().process_frame
	assert_bool(hud.chips_showing()).is_true()
	assert_bool(driver.is_acting()).is_false()
	assert_str(hud._chip_a.text).is_equal("Sit")
	assert_str(hud._chip_b.text).is_equal("Move")
	hud._chip_b.pressed.emit()
	assert_bool(hud.chips_showing()).is_false()
	for _i: int in 300:
		await get_tree().physics_frame
		if not host.used.is_empty():
			break
	assert_array(host.used).contains_exactly([Interaction.PICK_UP])
	InputDeviceTracker._set_device(InputDeviceTracker.Device.KEYS)


func test_a_tap_elsewhere_puts_the_chips_away() -> void:
	var player: Player = _setup()
	var hud: TouchHud = auto_free(HUD_SCENE.instantiate()) as TouchHud
	add_child(hud)
	InputDeviceTracker._set_device(InputDeviceTracker.Device.TOUCH)
	var host: _Host = _host(
		Vector3(5, 0, -2),
		[Interaction.of(Interaction.SIT, "Sit", 5), Interaction.of(Interaction.PICK_UP, "Move", 5)]
	)
	await _run(2)
	var driver: TouchDriver = _driver(player)
	_tap(driver, _screen(host.global_position + Vector3.UP * 0.5))
	await get_tree().process_frame
	assert_bool(hud.chips_showing()).is_true()
	_tap(driver, _screen(Vector3(-4, 0, 3)))
	assert_bool(hud.chips_showing()).is_false()
	assert_bool(driver.is_walking()).is_true()
	InputDeviceTracker._set_device(InputDeviceTracker.Device.KEYS)


func test_a_moving_host_is_followed() -> void:
	var player: Player = _setup()
	var host: _Host = _host(Vector3(6, 0, 0), [Interaction.of(Interaction.TALK, "Talk", 5)])
	await _run(2)
	var driver: TouchDriver = _driver(player)
	_tap(driver, _screen(host.global_position + Vector3.UP * 0.5))
	await _run(10)
	host.global_position = Vector3(0, 0, 7)
	for _i: int in 400:
		await get_tree().physics_frame
		if not host.used.is_empty():
			break
	assert_array(host.used).contains_exactly([Interaction.TALK])


func test_a_tool_stands_beside_the_tapped_cell() -> void:
	var player: Player = _setup()
	await _run(1)
	var driver: TouchDriver = _driver(player)
	var grid := WorldGrid.new()
	grid.configure(12, 12, 2.0, Vector3(-12, 0, -12))
	for z: int in 12:
		for x: int in 12:
			grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.GRASS)
	var here: Vector2i = grid.world_to_cell(player.global_position)
	var cell: Vector2i = here + Vector2i(2, 0)
	## The side nearest the player.
	assert_vector(Vector2(driver._stand_beside(null, grid, cell, here))).is_equal(Vector2(here + Vector2i(1, 0)))
	## That side blocked: another open side.
	grid.place(&"rock", here + Vector2i(1, 0), Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	var stand: Vector2i = driver._stand_beside(null, grid, cell, here)
	assert_bool(stand != here + Vector2i(1, 0) and stand != Vector2i(-1, -1)).is_true()
	assert_int(absi(stand.x - cell.x) + absi(stand.y - cell.y)).is_equal(1)


func test_on_a_desktop_two_verbs_use_a_without_chips() -> void:
	InputDeviceTracker.on_mobile = false
	var player: Player = _setup()
	var hud: TouchHud = auto_free(HUD_SCENE.instantiate()) as TouchHud
	add_child(hud)
	InputDeviceTracker._set_device(InputDeviceTracker.Device.TOUCH)
	var host: _Host = _host(
		Vector3(5, 0, -2),
		[Interaction.of(Interaction.SIT, "Sit", 5), Interaction.of(Interaction.PICK_UP, "Move", 5)]
	)
	await _run(2)
	var driver: TouchDriver = _driver(player)
	_tap(driver, _screen(host.global_position + Vector3.UP * 0.5))
	await get_tree().process_frame
	assert_bool(hud.chips_showing()).is_false()
	assert_bool(hud.is_showing()).is_false()
	for _i: int in 300:
		await get_tree().physics_frame
		if not host.used.is_empty():
			break
	assert_array(host.used).contains_exactly([Interaction.SIT])
	InputDeviceTracker._set_device(InputDeviceTracker.Device.KEYS)
