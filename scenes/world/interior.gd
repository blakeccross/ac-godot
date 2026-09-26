extends Node3D

## Indoor field. Same `WorldGrid` as outdoor; layout comes from `IndoorSession`.
## Prefer authored room scenes from `InteriorCatalog.scene_path` when present.

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const VILLAGER_SCENE := preload("res://scenes/actors/villager.tscn")
const GOKI_SCENE := preload("res://scenes/world/house_goki.tscn")

var grid: WorldGrid
var session: IndoorSession
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
	session = IndoorSession.new()
	session.bind(room)
	grid = session.grid
	Game.bind_interior(session)
	if not Game.weather_changed.is_connected(_on_weather_changed):
		Game.weather_changed.connect(_on_weather_changed)
	_sync_rain_se()
	_build_room(room)
	_apply_indoor_light(room)
	_spawn_player()
	_spawn_resident(room)
	_spawn_gokis(room)
	refresh_bgm()


func _build_room(room: Room) -> void:
	var path: String = InteriorCatalog.scene_path(room.id)
	if path != "" and ResourceLoader.exists(path):
		_mount_authored(path)
		return
	InteriorBuilder.build(self, session)


func _mount_authored(path: String) -> void:
	for name: String in ["Terrain", "Furniture", "Doors"]:
		var stale: Node = get_node_or_null(name)
		if stale != null:
			remove_child(stale)
			stale.free()
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		InteriorBuilder.build(self, session)
		return
	_room_content = packed.instantiate() as Node3D
	if _room_content == null:
		InteriorBuilder.build(self, session)
		return
	_room_content.name = "RoomContent"
	add_child(_room_content)
	if _room_content.has_method("populate"):
		_room_content.call("populate")
	else:
		InteriorBuilder.populate_authored(_room_content, session)


func _physics_process(_delta: float) -> void:
	## `EXIT_DOOR` warp: stepping onto the outdoor exit cell leaves
	## (`Player_actor_check_nextgoto`). Museum uses Exit auto-enter sensors instead.
	if _exiting or session == null or grid == null or session.room == null:
		return
	if session.room.kind == Room.Kind.MUSEUM:
		return
	## Just entered: keep EXIT_DOOR armed until the player walks clear of the strip.
	if Game.block_auto_enter_doors:
		return
	var player := Player.find(get_tree())
	if player == null or not (player is Node3D):
		return
	if player.is_busy() or player.is_door_entering():
		return
	var cell: Vector2i = grid.world_to_cell((player as Node3D).global_position)
	if not session.room.is_exit_cell(cell):
		return
	_exiting = true
	## Decomp's `goto_other_scene` fires the same frame the exit-cell check lands —
	## the player just stops, then the wipe warps the scene (no walk-through clip).
	player.stop_for_door()
	await SceneTransition.play_wipe_out(SceneTransition.Style.IRIS)
	Game.exit_interior()


## The weather actor runs in rooms too (`mAc_PROFILE_WEATHER` in every room scene): rain keeps
## playing indoors at 0.4, silenced only in the player's basement (`basement_event`). A room
## starts at the saved intensity — no ramp.
func _sync_rain_se() -> void:
	var room_id: StringName = session.room.id if session != null and session.room != null else &""
	Audio.sync_rain_syslev(
		Weather.kind_from_name(Game.weather),
		int(Game.weather_intensity),
		true,
		room_id == PlayerHouse.BASEMENT
	)


func _on_weather_changed(_weather: StringName) -> void:
	_sync_rain_se()


func _exit_tree() -> void:
	if Game.weather_changed.is_connected(_on_weather_changed):
		Game.weather_changed.disconnect(_on_weather_changed)
	Audio.stop_syslev()
	## Whatever is still scuttling goes back into the walls (`aMR_GokiInfoDt`).
	if session != null and session.room != null and PlayerHouse.is_player_room(session.room.id):
		HouseGoki.return_survivors(Game.interiors.player_house(), _live_gokis())
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
	InteriorBuilder.add_furniture(root, session, entry)


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


## Cockroaches on entering a player floor (`aMR_GokiInfoCt`).
func _spawn_gokis(room: Room) -> void:
	if room == null or not PlayerHouse.is_player_room(room.id):
		return
	var player := Player.find(get_tree())
	if player == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var spawns: Array[Dictionary] = HouseGoki.entry_spawns(
		session, Game.interiors.player_house(), player.global_position, rng
	)
	for spawn: Dictionary in spawns:
		add_goki(spawn["pos"] as Vector3, bool(spawn["fade"]))
	if not spawns.is_empty() and not Game.goki_shocked:
		Game.goki_shocked = true
		player.request_surprise()


func add_goki(pos: Vector3, fade: bool) -> Node:
	var goki: Node3D = GOKI_SCENE.instantiate() as Node3D
	$Characters.add_child(goki)
	goki.global_position = pos
	goki.call("setup", session, fade)
	return goki


func _live_gokis() -> int:
	var n: int = 0
	for node: Node in get_tree().get_nodes_in_group("house_goki") if get_tree() != null else []:
		if bool(node.get("alive")):
			n += 1
	return n


## Furniture moved off these cells: a waiting roach may run out (`aMR_MakeGokiburi`).
func on_furniture_moved(vacated: Array) -> void:
	if session == null or session.room == null or not PlayerHouse.is_player_room(session.room.id):
		return
	for entry: Variant in vacated:
		var spawn: Dictionary = HouseGoki.furniture_spawn(
			session, Game.interiors.player_house(), entry as Vector2i, _live_gokis()
		)
		if not spawn.is_empty():
			add_goki(spawn["pos"] as Vector3, true)
			return


## The node standing for a placement (a gripped piece is not always inside the probe's reach).
func furniture_node(placement_id: StringName) -> Node:
	var root: Node = _furniture_root()
	return root.get_node_or_null(String(placement_id)) if root != null else null


## Room music, or the song of whichever music player is switched on (`aMR_ChangeMDBgm`).
func refresh_bgm() -> void:
	if session == null or session.room == null:
		return
	var song: StringName = FurnitureMusic.active_bgm(session.room)
	Audio.play_bgm(song if song != &"" else BgmCatalog.room_id(session.room.kind))


## Glide every piece to where the session now has it after a push / pull / turn
## (`aMR_FtrPush` / `aMR_FtrPull` / `aMR_FtrRotate`).
func sync_placements(duration: float) -> void:
	if session == null or session.room == null:
		return
	var root: Node = _furniture_root()
	if root == null:
		return
	for entry: FurniturePlacement in session.room.placements:
		if entry == null:
			continue
		var node: Node3D = root.get_node_or_null(String(entry.id)) as Node3D
		if node == null:
			continue
		var data: FurnitureData = session.furniture_of(entry.furniture_id)
		var size: Vector2i = entry.resolved_footprint(data)
		var target: Vector3 = session.grid.furniture_world(entry.cell, size, entry.facing)
		target.y = node.position.y
		var yaw: float = WorldGrid.yaw_for_furniture(entry.facing)
		node.set("grid_facing", entry.facing)
		var moved: bool = not node.position.is_equal_approx(target)
		var turned: bool = absf(angle_difference(node.rotation.y, yaw)) > 0.001
		if not moved and not turned:
			continue
		if duration <= 0.0:
			node.position = target
			node.rotation.y = yaw
			continue
		var tween: Tween = node.create_tween().set_parallel(true)
		if moved:
			tween.tween_property(node, "position", target, duration).set_trans(Tween.TRANS_SINE).set_ease(
				Tween.EASE_IN_OUT
			)
		if turned:
			var start: float = node.rotation.y
			tween.tween_method(
				func(t: float) -> void: node.rotation.y = lerp_angle(start, yaw, t),
				0.0,
				1.0,
				duration
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func refresh_shop_set() -> void:
	InteriorRefresh.shop_set(_furniture_root(), _room_content, session)


func refresh_public_set() -> void:
	InteriorRefresh.public_set(_furniture_root(), _room_content, session)


func _apply_indoor_light(room: Room) -> void:
	InteriorLighting.apply(self, _world_env, _camera, grid, room)


func _spawn_player() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
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
	if not InteriorLighting.pins_follow_camera(session.room if session != null else null):
		if _camera.has_method("set_target"):
			_camera.call("set_target", player)
	SceneTransition.play_wipe_in_if_pending()
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


func _play_door_arrive(player: Player) -> void:
	## Museum wing / outdoor→entrance: continue INTO_S1 past the door sensor.
	await StructureDoor.play_arrive(player)
