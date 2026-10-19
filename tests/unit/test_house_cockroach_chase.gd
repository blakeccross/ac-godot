class_name TestHouseCockroachChase
extends GdUnitTestSuite

## The real player in the real house can run roaches down, even when they hide in a corner
## (`aHG_check_dead`: 9 GX tread range; roaches keep 15 GX off walls, the player 18 GX).

const INTERIOR := preload("res://scenes/world/interior.tscn")
const MENU_GROUPS: Array[StringName] = [
	&"inventory_ui", &"map_ui", &"dialogue_ui", &"shop_ui", &"debug_console_ui",
	&"design_ui", &"design_list_ui", &"design_album_ui", &"name_entry_ui",
]


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func _alive() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("house_cockroaches"):
		if bool(node.get("alive")):
			out.append(node as Node3D)
	return out


func test_the_player_can_tread_on_every_roach() -> void:
	## Earlier suites can leak players (the roach looks for the first one in the group) and
	## open overlays (the player won't walk while a menu reports open).
	for group: StringName in [Player.GROUP] + MENU_GROUPS:
		for stale: Node in get_tree().get_nodes_in_group(group):
			stale.remove_from_group(group)
	Clock.paused = true
	Clock.apply_snapshot({"year": 2001, "month": 7, "day": 15, "hour": 12, "minute": 0})
	Game.reset_session()
	Game.interiors.refresh_player_rooms()
	var room: Room = Game.interiors.room(&"player_main")
	room.placements.clear()
	Game.current_room_id = &"player_main"
	Game.spawn_at_room_door = true
	Game.goki_shocked = true
	var interior: Node = auto_free(INTERIOR.instantiate())
	add_child(interior)
	await await_millis(1)
	for _i: int in 10:
		await get_tree().physics_frame
	Game.interiors.player_house().goki_count = 3
	interior.call("_spawn_gokis", room)
	assert_int(_alive().size()).is_greater(0)
	var player := Player.find(get_tree())
	var source := PlayerInput.new()
	player.scripted_input = source
	var cam: Camera3D = get_viewport().get_camera_3d()
	## Walk straight at the nearest live roach, as a stick held toward it would.
	for _frame: int in 600:
		await get_tree().physics_frame
		var alive: Array[Node3D] = _alive()
		if alive.is_empty():
			break
		var target: Node3D = alive[0]
		for roach: Node3D in alive:
			if roach.global_position.distance_to(player.global_position) < target.global_position.distance_to(player.global_position):
				target = roach
		var dir := target.global_position - player.global_position
		dir.y = 0.0
		var look := -cam.global_transform.basis.z
		look.y = 0.0
		var right := cam.global_transform.basis.x
		right.y = 0.0
		dir = dir.normalized()
		source.move = Vector2(dir.dot(right.normalized()), -dir.dot(look.normalized()))
	player.scripted_input = null
	assert_int(_alive().size()).is_equal(0)
