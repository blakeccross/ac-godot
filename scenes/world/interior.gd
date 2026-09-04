extends Node3D

## Indoor field. Same `WorldGrid` as outdoor; layout comes from `Interior`.
## Prefer authored room scenes from `InteriorCatalog.scene_path` when present.

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const VILLAGER_SCENE := preload("res://scenes/actors/villager.tscn")

var grid: WorldGrid
var session: Interior
var _exiting: bool = false
var _room_content: Node3D = null

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
	_build_room(room)
	_apply_indoor_light(room)
	_spawn_player()
	_spawn_resident(room)
	Audio.play_bgm(BgmCatalog.room_id(room.kind))


func _build_room(room: Room) -> void:
	var path: String = InteriorCatalog.scene_path(room.id)
	if path != "" and ResourceLoader.exists(path):
		_mount_authored(path)
		return
	InteriorBuilder.new().build(self, session)


func _mount_authored(path: String) -> void:
	for name: String in ["Terrain", "Furniture", "Doors"]:
		var stale: Node = get_node_or_null(name)
		if stale != null:
			remove_child(stale)
			stale.free()
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		InteriorBuilder.new().build(self, session)
		return
	_room_content = packed.instantiate() as Node3D
	if _room_content == null:
		InteriorBuilder.new().build(self, session)
		return
	_room_content.name = "RoomContent"
	add_child(_room_content)
	if _room_content.has_method("populate"):
		_room_content.call("populate")
	else:
		InteriorBuilder.new().populate_authored(_room_content, session)


func _physics_process(_delta: float) -> void:
	## `EXIT_DOOR` warp: stepping onto the outdoor exit cell leaves
	## (`Player_actor_check_nextgoto`). Museum uses Exit auto-enter sensors instead.
	if _exiting or session == null or grid == null or session.room == null:
		return
	if session.room.kind == Room.Kind.MUSEUM:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not (player is Node3D):
		return
	if bool(player.get("_busy")) or bool(player.get("_door_entering")):
		return
	var cell: Vector2i = grid.world_to_cell((player as Node3D).global_position)
	if not session.room.is_exit_cell(cell):
		return
	_exiting = true
	await _play_indoor_exit(player as Node3D)
	await DoorTransition.play_wipe_out()
	Game.exit_interior()


func _play_indoor_exit(player: Node3D) -> void:
	## Face south and walk into the exit (`mPlayer_INDEX_DOOR` / INTO_S1).
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("run_indoor_exit"):
		return
	## Midpoint of the EXIT_DOOR pair so leave aims at the alcove center.
	var door_pos: Vector3 = (
		grid.cell_to_world(session.room.door_cell)
		+ grid.cell_to_world(session.room.door_cell + Vector2i(1, 0))
	) * 0.5
	var south_yaw: float = WorldGrid.yaw_for_facing(WorldGrid.Facing.SOUTH)
	var target: Vector3 = door_pos + Vector3(0.0, 0.0, StructureDoor.INTO_GX * FieldCatalog.GX_TO_METERS)
	target.y = player.global_position.y
	await player.call("run_indoor_exit", target, south_yaw)


func _exit_tree() -> void:
	if Game.interior_session == session:
		Game.bind_interior(null)


func _furniture_root() -> Node3D:
	if _room_content != null:
		var authored: Node3D = _room_content.get_node_or_null("Furniture") as Node3D
		if authored != null:
			return authored
	return get_node_or_null("Furniture") as Node3D


func spawn_placement(entry: FurniturePlacement) -> void:
	if entry == null:
		return
	var root: Node3D = _furniture_root()
	if root == null:
		return
	InteriorBuilder.new().add_furniture(root, session, entry)


func despawn_placement(placement_id: StringName) -> void:
	var root: Node = _furniture_root()
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
	var root: Node3D = _furniture_root()
	if root == null or session == null:
		return
	var stale: Array[Node] = []
	for child: Node in root.get_children():
		if child.is_in_group("shop_set"):
			stale.append(child)
	for node: Node in stale:
		root.remove_child(node)
		## Never `free()` here — buy can refresh while `shop_stock.interact` is still on the stack.
		node.queue_free()
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
		## Homes frame the shell (never closer than Camera2 620). Museum / shops /
		## other public rooms keep outdoor focus distance — `Camera2_InDoorCheck`
		## is only NPCROOM0 / ROOM0 / PLAYER0_ROOM.
		if pins_follow_camera(room):
			var bounds: AABB = InteriorBuilder.new()._shell_bounds(room, grid)
			var span: float = maxf(bounds.size.x, bounds.size.z)
			if _camera.has_method("offset_to_frame_span"):
				_camera.set("offset", _camera.call("offset_to_frame_span", span))
			elif _camera.has_method("offset_for_ground_span"):
				_camera.set("offset", _camera.call("offset_for_ground_span", span))
			else:
				_camera.set("offset", Vector3(0.0, span, span))
		else:
			## Restore Camera2 620 when leaving a framed home for a public room.
			_camera.set("offset", preload("res://scenes/world/follow_camera.gd").DEFAULT_OFFSET)
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
	if Game.has_interior_spawn and session != null and session.grid != null:
		pos = MuseumDisplay.gx_to_world(session.grid, Game.interior_spawn_gx)
		pos.y = 0.1
		yaw = Game.interior_spawn_yaw
		Game.has_interior_spawn = false
	elif Game.spawn_at_room_door and session != null and session.room != null:
		pos = session.grid.cell_to_world(session.room.spawn_cell)
		pos.y = 0.1
		yaw = WorldGrid.yaw_for_facing(WorldGrid.Facing.NORTH)
		Game.spawn_at_room_door = false
	elif not Game.player_position.is_equal_approx(Game.DEFAULT_SPAWN):
		pos = Game.player_position
	player.apply_spawn(pos, yaw)
	if not pins_follow_camera(session.room if session != null else null):
		if _camera.has_method("set_target"):
			_camera.call("set_target", player)
	DoorTransition.play_wipe_in_if_pending()
	if Game.play_door_arrive:
		Game.play_door_arrive = false
		call_deferred("_play_door_arrive", player)


func _spawn_resident(room: Room) -> void:
	## Indoor `ac_npc2`: show the homeowner when awake at home.
	if room == null or room.kind != Room.Kind.NPC:
		return
	var occupant: StringName = &""
	var house: House = InteriorCatalog.house_template(room.id)
	if house != null:
		occupant = house.occupant_id
	if occupant == &"":
		var raw := String(room.id)
		if raw.begins_with("npc_"):
			occupant = StringName(raw.substr(4))
	if not VillagerHome.should_spawn_indoor(occupant):
		return
	var data: VillagerData = VillagerCatalog.get_villager(occupant)
	if data == null:
		return
	var villager: Node = VILLAGER_SCENE.instantiate()
	if villager == null:
		return
	villager.set("data", data)
	villager.set("indoor_resident", true)
	villager.name = "Resident"
	$Characters.add_child(villager)
	if villager is Node3D:
		var stand: Vector3 = VillagerHome.indoor_stand(session)
		stand.y = 0.1
		(villager as Node3D).global_position = stand
		(villager as Node3D).rotation.y = WorldGrid.yaw_for_facing(WorldGrid.Facing.SOUTH)


func _play_door_arrive(player: Node) -> void:
	## Museum wing / outdoor→entrance: continue INTO_S1 past the door sensor.
	await StructureDoor.play_arrive(player)
