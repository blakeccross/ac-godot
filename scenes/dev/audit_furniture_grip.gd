extends Node3D

## Drives the real player + interior through grip → push → pull → turn → pick up and prints
## what happened, saving a frame after each step.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/dev/audit_furniture_grip.tscn
##
## Output: `res://recordings/furniture_grip/*.png`

const OUT_DIR := "res://recordings/furniture_grip"
const INTERIOR := preload("res://scenes/world/interior.tscn")


func _ready() -> void:
	Clock.paused = true
	get_viewport().size = Vector2i(960, 540)
	call_deferred("_run")


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().physics_frame


func _shot(label: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, label]))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	Game.reset_session()
	Clock.apply_snapshot({"year": 2001, "month": 7, "day": 15, "hour": 12, "minute": 0})
	var house: House = Game.interiors.player_house()
	house.size_tier = House.SizeTier.LARGE
	house.next_size_tier = House.SizeTier.LARGE
	Game.interiors.refresh_player_rooms()
	var room: Room = Game.interiors.room(&"player_main")
	room.placements.clear()
	var chair: FurnitureData = ItemCatalog.get_item(&"wood_chair") as FurnitureData
	var table: FurnitureData = ItemCatalog.get_item(&"wood_table") as FurnitureData
	Game.current_room_id = &"player_main"
	Game.spawn_at_room_door = true
	var interior: Node = INTERIOR.instantiate()
	add_child(interior)
	await _frames(6)
	var session: IndoorSession = Game.interior_session
	var chair_entry: FurniturePlacement = session.place(chair, Vector2i(4, 4), WorldGrid.Facing.SOUTH)
	interior.call("spawn_placement", chair_entry)
	var table_entry: FurniturePlacement = session.place(table, Vector2i(6, 6), WorldGrid.Facing.SOUTH)
	interior.call("spawn_placement", table_entry)
	var player := Player.find(get_tree())
	player.global_position = session.grid.cell_to_world(Vector2i(4, 5)) + Vector3(0, 0.1, 0)
	player.set_facing(WorldGrid.yaw_for_facing(WorldGrid.Facing.NORTH))
	await _frames(4)
	print("start   chair ", chair_entry.cell)
	await _shot("0_start")

	print("grip    ", player._try_grip())
	Input.action_press("interact")
	await _frames(20)
	await _shot("1_gripped")

	## Stick north = into the chair: push.
	Input.action_press("move_forward")
	await _frames(30)
	print("push    chair ", chair_entry.cell, " player ", session.grid.world_to_cell(player.global_position))
	await _frames(40)
	await _shot("2_pushed")
	Input.action_release("move_forward")
	await _frames(4)

	## Stick south = away: pull.
	Input.action_press("move_back")
	await _frames(30)
	print("pull    chair ", chair_entry.cell, " player ", session.grid.world_to_cell(player.global_position))
	await _frames(45)
	await _shot("3_pulled")
	Input.action_release("move_back")
	await _frames(6)

	## Stick east: turn.
	Input.action_press("move_right")
	await _frames(12)
	print("turn    chair facing ", chair_entry.facing)
	await _frames(40)
	await _shot("4_turned")
	Input.action_release("move_right")
	await _frames(4)

	Input.action_release("interact")
	await _frames(4)
	print("released gripping=", player._gripping, " busy=", player._busy)

	## B picks it up.
	player.set_facing(WorldGrid.yaw_for_facing(WorldGrid.Facing.NORTH))
	Input.action_press("sprint")
	await _frames(2)
	Input.action_release("sprint")
	await _frames(70)
	print("pickup  chair in room: ", session.room.placement_by_id(chair_entry.id) != null)
	await _shot("5_pickup")

	## Walk into a chair: sit, then stick to stand.
	var seat_entry: FurniturePlacement = session.place(chair, Vector2i(4, 4), WorldGrid.Facing.SOUTH)
	interior.call("spawn_placement", seat_entry)
	player.global_position = session.grid.cell_to_world(Vector2i(4, 5)) + Vector3(0, 0.1, 0)
	player.set_facing(WorldGrid.yaw_for_facing(WorldGrid.Facing.NORTH))
	await _frames(4)
	Input.action_press("move_forward")
	await _frames(70)
	print("sit     rest=", (player._rest).get("phase"), " pos cell ", session.grid.world_to_cell(player.global_position))
	await _shot("6_seated")
	Input.action_release("move_forward")
	await _frames(20)
	Input.action_press("move_back")
	await _frames(70)
	Input.action_release("move_back")
	await _frames(30)
	print("stand   rest empty=", (player._rest).is_empty(), " busy=", player._busy, " cell ", session.grid.world_to_cell(player.global_position))
	await _shot("7_stood")
	## Tap a dresser: the conversation opens, "Take it out" moves the apple to the pockets.
	## The chair picked up above is still the selected pocket item; A would place it.
	Game.inventory.remove(&"wood_chair", 99)
	var dresser: FurnitureData = ItemCatalog.get_item(&"wood_dresser") as FurnitureData
	var chest_entry: FurniturePlacement = session.place(dresser, Vector2i(6, 4), WorldGrid.Facing.SOUTH)
	chest_entry.stored = PackedStringArray(["apple"])
	interior.call("spawn_placement", chest_entry)
	player.global_position = session.grid.cell_to_world(Vector2i(6, 5)) + Vector3(0, 0.1, 0)
	player.set_facing(WorldGrid.yaw_for_facing(WorldGrid.Facing.NORTH))
	await _frames(4)
	var apples_before: int = Game.inventory.count_of(&"apple")
	var probe_hit: InteractionQuery = player._resolve_interact()
	print("tap     probe host=", probe_hit.host if probe_hit else null, " action=", probe_hit.action.id if probe_hit and probe_hit.action else null, " held=", Game.held_furniture())
	print("tap     grip=", player._try_grip())
	Input.action_press("interact")
	await _frames(5)
	Input.action_release("interact")
	await _frames(40)
	var ui := DialogueOverlay.find(get_tree())
	print("chest   dialogue open=", ui.is_open())
	await _shot("8_chest_talk")
	ui._choice_index = 1
	for _i: int in 12:
		ui.fast_advance()
		await _frames(20)
	await _frames(60)
	print("chest   stored=", chest_entry.stored.size(), " apples ", apples_before, "->", Game.inventory.count_of(&"apple"), " busy=", player._busy)

	## A music player with a song switched on replaces the room music.
	var stereo: FurnitureData = ItemCatalog.furniture_for_visual(&"int_sum_stereo01")
	var stereo_entry: FurniturePlacement = session.place(stereo, Vector2i(2, 2), WorldGrid.Facing.SOUTH)
	print("stereo  music player=", stereo.is_music_player(), " footprint ", stereo.footprint)
	FurnitureMusic.select_song(session, stereo_entry, 4)
	interior.call("refresh_bgm")
	print("stereo  bgm=", Audio.current_id, " expected ", MinidiskCatalog.bgm_id(4))
	## Grip from the east side (player heading +90° = east): must catch the chair and push it west.
	var side_chair: FurniturePlacement = session.place(chair, Vector2i(7, 7), WorldGrid.Facing.SOUTH)
	interior.call("spawn_placement", side_chair)
	player.global_position = session.grid.cell_to_world(Vector2i(8, 7)) + Vector3(0, 0.1, 0)
	player.set_facing(atan2(-1.0, 0.0))
	await _frames(4)
	print("east    grip=", player._try_grip())
	Input.action_press("interact")
	Input.action_press("move_left")
	await _frames(40)
	Input.action_release("move_left")
	Input.action_release("interact")
	await _frames(50)
	print("east    chair ", side_chair.cell)

	## Cockroaches: five waiting → three come out, the player is startled, one gets trodden on.
	Game.interiors.player_house().goki_count = 5
	Game.goki_shocked = false
	player.global_position = session.grid.cell_to_world(Vector2i(4, 6)) + Vector3(0, 0.1, 0)
	interior.call("_spawn_gokis", session.room)
	await _frames(30)
	print("goki    out=", get_tree().get_nodes_in_group("house_goki").size(), " stored=", Game.interiors.player_house().goki_count, " startled busy=", player._busy)
	for g: Node in get_tree().get_nodes_in_group("house_goki"):
		print("goki    node ", (g as Node3D).position, " children=", g.get_child_count(), " paths=", FieldCatalog.mesh_paths(&"act_m_house_goki"))
	await _shot("9_goki")
	await _frames(90)
	var target: Node3D = get_tree().get_nodes_in_group("house_goki")[0] as Node3D
	player.global_position = target.global_position + Vector3(0.1, 0.1, 0.0)
	Input.action_press("move_right")
	await _frames(20)
	Input.action_release("move_right")
	await _frames(10)
	var alive: int = 0
	for node: Node in get_tree().get_nodes_in_group("house_goki"):
		if bool(node.get("alive")):
			alive += 1
	print("goki    alive after stomp=", alive)
	Game.reset_session()
	get_tree().quit()
