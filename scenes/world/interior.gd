extends Node3D

## Indoor field. Same `WorldGrid` as outdoor; layout comes from `Interior`.

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")

var grid: WorldGrid
var session: Interior

@onready var _camera: Camera3D = $FollowCamera
@onready var _spawn: Marker3D = $Characters/PlayerSpawn
@onready var _world_env: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	add_to_group("interior")
	Game.notify_world_ready()
	var room: Room = Game.interiors.room(Game.current_room_id)
	if room == null:
		Game.exit_interior()
		return
	session = Interior.new()
	session.bind(room)
	grid = session.grid
	Game.bind_interior(session)
	InteriorBuilder.new().build(self, session)
	_apply_indoor_light(room)
	_spawn_player()
	Audio.play_bgm(BgmCatalog.room_id(room.kind))


func _exit_tree() -> void:
	if Game.interior_session == session:
		Game.bind_interior(null)


func spawn_placement(entry: FurniturePlacement) -> void:
	if entry == null:
		return
	var root: Node3D = get_node_or_null("Furniture") as Node3D
	if root == null:
		return
	InteriorBuilder.new().add_furniture(root, session, entry)


func despawn_placement(placement_id: StringName) -> void:
	var root: Node = get_node_or_null("Furniture")
	if root == null:
		return
	var node: Node = root.get_node_or_null(String(placement_id))
	if node != null:
		node.queue_free()


func refresh_placement(placement_id: StringName) -> void:
	if session == null or session.room == null:
		return
	var entry: FurniturePlacement = session.room.placement_by_id(placement_id)
	despawn_placement(placement_id)
	spawn_placement(entry)


func refresh_shop_set() -> void:
	var root: Node3D = get_node_or_null("Furniture") as Node3D
	if root == null or session == null:
		return
	var stale: Array[Node] = []
	for child: Node in root.get_children():
		if child.is_in_group("shop_set"):
			stale.append(child)
	for node: Node in stale:
		root.remove_child(node)
		node.free()
	InteriorBuilder.new().add_shop_set(root, session)


func _apply_indoor_light(room: Room) -> void:
	var env: Environment = _world_env.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.18, 0.16, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.64, 0.52)
	env.ambient_light_energy = 1.0
	env.fog_enabled = false
	if _camera != null and "offset" in _camera:
		var bounds: AABB = InteriorBuilder.new()._shell_bounds(room, grid)
		var span: float = maxf(bounds.size.x, bounds.size.z)
		if _camera.has_method("offset_to_frame_span"):
			_camera.set("offset", _camera.call("offset_to_frame_span", span))
		elif _camera.has_method("offset_for_ground_span"):
			_camera.set("offset", _camera.call("offset_for_ground_span", span))
		else:
			_camera.set("offset", Vector3(0.0, span, span))
	if pins_follow_camera(room) and _camera.has_method("lock_at"):
		_camera.call("lock_at", _inner_look_point(room))


## Player and villager homes pin the 3/4 camera to the room (`Camera2` border invert).
static func pins_follow_camera(room: Room) -> bool:
	return room != null and (room.kind == Room.Kind.NPC or room.kind == Room.Kind.PLAYER)


func _inner_look_point(room: Room) -> Vector3:
	if grid == null or room == null:
		return Vector3.ZERO
	var nw: Vector3 = grid.cell_corner(room.inner_origin)
	var size := Vector3(
		float(maxi(room.inner_size.x, 1)) * grid.cell_size,
		0.0,
		float(maxi(room.inner_size.y, 1)) * grid.cell_size
	)
	return Vector3(nw.x + size.x * 0.5, 0.0, nw.z + size.z * 0.5)


func _spawn_player() -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate() as CharacterBody3D
	$Characters.add_child(player)
	var pos: Vector3 = _spawn.global_position
	var yaw: float = Game.player_yaw
	if Game.spawn_at_room_door and session != null and session.room != null:
		pos = session.grid.cell_to_world(session.room.spawn_cell)
		pos.y = 0.1
		yaw = WorldGrid.yaw_for_facing(WorldGrid.Facing.NORTH)
		Game.spawn_at_room_door = false
	elif not Game.player_position.is_equal_approx(Game.DEFAULT_SPAWN):
		pos = Game.player_position
	player.apply_spawn(pos, yaw)
	if pins_follow_camera(session.room if session != null else null):
		return
	if _camera.has_method("set_target"):
		_camera.call("set_target", player)
