extends Node3D

## Completed-museum harness. Instances each wing `.tscn` under `Rooms/`;
## rooms own their own shell, doors, collision, and exhibits.
##
##   $GODOT_BIN --path . res://scenes/dev/museum_complete.tscn
##
## Keys 1–5 switch rooms. Walk south from the entrance to leave → title.

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const WING_IDS: Array[StringName] = [
	&"museum_entrance",
	&"museum_painting",
	&"museum_fossil",
	&"museum_insect",
	&"museum_fish",
]

var grid: WorldGrid
var session: Interior

@onready var _camera: Camera3D = $FollowCamera
@onready var _rooms: Node3D = $Rooms
@onready var _characters: Node3D = $Characters
@onready var _missing: Label = %MissingBanner


func _ready() -> void:
	add_to_group("museum_complete_stage")
	add_to_group("interior")
	_bootstrap_session()
	_refresh_missing_banner()
	_populate_rooms()
	Game.notify_world_ready()
	switch_wing(&"museum_entrance")
	print(
		(
			"Museum complete: fossils=%d art=%d fish=%d insects=%d (total %d)"
			% [
				Game.museum.count_fossils(),
				Game.museum.count_art(),
				Game.museum.count_fish(),
				Game.museum.count_insects(),
				Game.museum.count_all(),
			]
		)
	)
	print("Keys 1–5 switch rooms. Walk out south → title.")


func switch_wing(room_id: StringName) -> bool:
	var room: Room = Game.interiors.room(room_id)
	if room == null or room.kind != Room.Kind.MUSEUM:
		return false
	var room_node: Node3D = _room_node(room_id)
	if room_node == null:
		return false
	Game.current_room_id = room_id
	_show_room(room_id)
	session = Interior.new()
	session.bind(room)
	grid = session.grid
	Game.bind_interior(session)
	_spawn_or_move_player(room_node)
	Audio.play_bgm(BgmCatalog.room_id(room.kind))
	return true


func _populate_rooms() -> void:
	## Each room scene fills its own Terrain / Furniture.
	for room_id: StringName in WING_IDS:
		var room_node: Node3D = _room_node(room_id)
		if room_node != null and room_node.has_method("populate"):
			room_node.call("populate")


func _bootstrap_session() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.month = 6
	Clock.day = 15
	Clock.hour = 12
	Clock.minute = 0
	Game.museum.fill_complete()
	Game.world_mode = WorldData.Mode.TEST
	Game.give_test_tools()
	_give_sample_donations()
	Game.current_room_id = &"museum_entrance"
	Game.has_interior_spawn = true
	Game.interior_spawn_gx = MuseumDisplay.ENTRANCE_SPAWN_GX
	Game.interior_spawn_yaw = WorldGrid.yaw_for_furniture(MuseumDisplay.ENTRANCE_SPAWN_FACING)
	Game.spawn_at_room_door = false
	Game.block_auto_enter_doors = true
	Game.outdoor_return = Vector3(0.0, 0.1, 6.0)


func _room_node(room_id: StringName) -> Node3D:
	if _rooms == null:
		return null
	return _rooms.get_node_or_null(String(room_id)) as Node3D


func _show_room(room_id: StringName) -> void:
	if _rooms == null:
		return
	for child: Node in _rooms.get_children():
		if child is Node3D:
			_set_room_active(child as Node3D, child.name == String(room_id))


func _set_room_active(room: Node3D, active: bool) -> void:
	## `visible` does not disable StaticBody / Area3D.
	room.visible = active
	room.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_set_collision_enabled(room, active)


func _set_collision_enabled(node: Node, enabled: bool) -> void:
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		if not body.has_meta("_museum_layer"):
			body.set_meta("_museum_layer", body.collision_layer)
			body.set_meta("_museum_mask", body.collision_mask)
		if enabled:
			body.collision_layer = int(body.get_meta("_museum_layer"))
			body.collision_mask = int(body.get_meta("_museum_mask"))
		else:
			body.collision_layer = 0
			body.collision_mask = 0
	for child: Node in node.get_children():
		_set_collision_enabled(child, enabled)


func _spawn_or_move_player(room_node: Node3D) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	var spawn_marker: Marker3D = room_node.get_node_or_null("PlayerSpawn") as Marker3D
	var pos: Vector3 = (
		spawn_marker.global_position if spawn_marker != null else Vector3(12.0, 0.1, 22.0)
	)
	var yaw: float = Game.player_yaw
	if Game.has_interior_spawn and grid != null:
		pos = MuseumDisplay.gx_to_world(grid, Game.interior_spawn_gx)
		pos.y = 0.1
		yaw = Game.interior_spawn_yaw
		Game.has_interior_spawn = false
	elif Game.spawn_at_room_door and session != null and session.room != null:
		pos = grid.cell_to_world(session.room.spawn_cell)
		pos.y = 0.1
		yaw = WorldGrid.yaw_for_facing(WorldGrid.Facing.NORTH)
		Game.spawn_at_room_door = false
	if player == null:
		player = PLAYER_SCENE.instantiate()
		_characters.add_child(player)
	if player.has_method("apply_spawn"):
		player.call("apply_spawn", pos, yaw)
	elif player is Node3D:
		(player as Node3D).global_position = pos
		(player as Node3D).rotation.y = yaw
	if _camera != null and _camera.has_method("set_target"):
		_camera.call("set_target", player as Node3D)
	if _camera != null and "offset" in _camera:
		_camera.set("offset", preload("res://scenes/world/follow_camera.gd").DEFAULT_OFFSET)


func _refresh_missing_banner() -> void:
	if _missing == null or _rooms == null:
		return
	var any := false
	for room_id: StringName in WING_IDS:
		var room_node: Node = _room_node(room_id)
		if room_node == null:
			continue
		var vis: Node = room_node.get_node_or_null("Shell/GeneratedVisual")
		if vis != null and vis.get_child_count() > 0:
			any = true
			break
	_missing.visible = not any


func _give_sample_donations() -> void:
	for fish_id: StringName in [&"carp", &"goldfish", &"coelacanth"]:
		var fish: FishData = FishCatalog.get_fish(fish_id)
		if fish != null:
			Game.inventory.add(fish, 1)
	for bug_id: StringName in [&"common_butterfly", &"firefly"]:
		var bug: BugData = BugCatalog.get_bug(bug_id)
		if bug != null:
			Game.inventory.add(bug, 1)


func _exit_tree() -> void:
	if Game.interior_session == session:
		Game.bind_interior(null)
