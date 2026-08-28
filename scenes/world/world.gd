extends Node3D

## Playable acre. Owns a WorldGrid; children are presentation only.

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")

@export var data: AcreData

var grid: WorldGrid = WorldGrid.new()

@onready var _sun: DirectionalLight3D = $Sun
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _spawn: Marker3D = $Characters/PlayerSpawn
@onready var _camera: Camera3D = $FollowCamera
@onready var _objects: Node3D = $Objects
@onready var _buildings: Node3D = $Buildings
@onready var _terrain: Node3D = $Terrain
@onready var _navigation: NavigationRegion3D = $Navigation


func _ready() -> void:
	add_to_group("world")
	Game.notify_world_ready()
	_setup_grid()
	_register_occupants(_objects)
	_register_occupants(_buildings)
	_build_water_visuals()
	_build_navigation()
	Clock.time_changed.connect(_apply_time_of_day)
	_apply_time_of_day()
	_spawn_player()


func release_occupant(occupant_id: StringName) -> void:
	grid.remove(occupant_id)


func _setup_grid() -> void:
	grid.configure_from_acre(data)


func _register_occupants(root: Node) -> void:
	for child: Node in root.get_children():
		if child.is_queued_for_deletion() or not (child is Node3D):
			continue
		var node := child as Node3D
		if node.get("occupy_grid") == false:
			continue
		var occupant_id: StringName = _occupant_id_for(node)
		var footprint := Vector2i.ONE
		var fp: Variant = node.get("footprint")
		if typeof(fp) == TYPE_VECTOR2I and fp != Vector2i.ZERO:
			footprint = fp
		var facing := WorldGrid.Facing.SOUTH
		var facing_val: Variant = node.get("grid_facing")
		if typeof(facing_val) == TYPE_INT:
			facing = facing_val as WorldGrid.Facing
		var kind: WorldGrid.PlaceKind = _kind_for(node)
		var anchor: Vector2i = grid.anchor_from_world_center(node.global_position, footprint, facing)
		if not grid.place(occupant_id, anchor, footprint, facing, kind):
			anchor = grid.world_to_cell(node.global_position)
			if not grid.place(occupant_id, anchor, Vector2i.ONE, WorldGrid.Facing.SOUTH, kind):
				continue
			footprint = Vector2i.ONE
			facing = WorldGrid.Facing.SOUTH
		var snapped: Vector3 = grid.footprint_center(anchor, footprint, facing)
		node.global_position = Vector3(snapped.x, node.global_position.y, snapped.z)
		if node.has_method("apply_grid_yaw"):
			node.call("apply_grid_yaw", facing)


func _occupant_id_for(node: Node) -> StringName:
	var explicit: Variant = node.get("occupant_id")
	if typeof(explicit) == TYPE_STRING_NAME and explicit != &"":
		return explicit
	if typeof(explicit) == TYPE_STRING and str(explicit) != "":
		return StringName(str(explicit))
	var persist: Variant = node.get("persist_id")
	if typeof(persist) == TYPE_STRING_NAME and persist != &"":
		return persist
	return StringName(node.name)


func _kind_for(node: Node) -> WorldGrid.PlaceKind:
	var kind_val: Variant = node.get("place_kind")
	if typeof(kind_val) == TYPE_INT:
		return kind_val as WorldGrid.PlaceKind
	if node is StaticBody3D and node.get_parent() == _buildings:
		return WorldGrid.PlaceKind.BUILDING
	if node.has_method("interact_prompt"):
		return WorldGrid.PlaceKind.ITEM
	return WorldGrid.PlaceKind.PLANT


func _build_water_visuals() -> void:
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.28, 0.52, 0.78, 1)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(grid.cell_size * 0.96, 0.06, grid.cell_size * 0.96)
	for x: int in grid.columns:
		for z: int in grid.rows:
			var cell := Vector2i(x, z)
			if grid.terrain_at(cell) != WorldGrid.Terrain.WATER:
				continue
			var vis := MeshInstance3D.new()
			vis.mesh = mesh
			vis.material_override = water_mat
			vis.position = grid.cell_to_world(cell) + Vector3(0.0, 0.03, 0.0)
			_terrain.add_child(vis)


func _build_navigation() -> void:
	var min_c := grid.cell_corner(Vector2i(0, 0))
	var max_c := grid.cell_corner(Vector2i(grid.columns, grid.rows))
	var y: float = 0.05
	var nav := NavigationMesh.new()
	nav.vertices = PackedVector3Array([
		Vector3(min_c.x, y, min_c.z),
		Vector3(max_c.x, y, min_c.z),
		Vector3(max_c.x, y, max_c.z),
		Vector3(min_c.x, y, max_c.z),
	])
	nav.add_polygon(PackedInt32Array([0, 1, 2]))
	nav.add_polygon(PackedInt32Array([0, 2, 3]))
	_navigation.navigation_mesh = nav


func _spawn_player() -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate() as CharacterBody3D
	$Characters.add_child(player)
	var pos := Game.player_position
	if pos.is_equal_approx(Game.DEFAULT_SPAWN):
		pos = _spawn.global_position
	player.apply_spawn(pos, Game.player_yaw)
	if _camera.has_method("set_target"):
		_camera.call("set_target", player)


func _apply_time_of_day() -> void:
	var hour_frac: float = float(Clock.hour) + float(Clock.minute) / 60.0
	var angle: float = deg_to_rad((hour_frac / 24.0) * 360.0 - 90.0)
	_sun.rotation.x = -angle
	_sun.rotation.y = deg_to_rad(-40.0)

	var pal: Dictionary = Clock.outdoor_light()
	_sun.light_energy = float(pal["energy"])
	_sun.light_color = pal["sun"] as Color
	var env: Environment = _world_env.environment
	env.ambient_light_color = pal["ambient"] as Color
	env.ambient_light_energy = float(pal["energy"]) * 0.45 + 0.15
