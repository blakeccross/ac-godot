extends Node3D

## Playable acre. Owns a WorldGrid; children are presentation only.
## Layout comes from WorldData (test town or generator), not a catalog in this .tscn.

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")

var grid: WorldGrid = WorldGrid.new()
var layout: WorldData

@onready var _sun: DirectionalLight3D = $Sun
@onready var _moon: DirectionalLight3D = $Moon
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _spawn: Marker3D = $Characters/PlayerSpawn
@onready var _camera: Camera3D = $FollowCamera
@onready var _navigation: NavigationRegion3D = $Navigation


func _ready() -> void:
	add_to_group("world")
	Game.notify_world_ready()
	layout = Game.resolve_world_data()
	print(WorldGenerator.map_text(layout))
	WorldBuilder.new().build(self, layout, grid)
	HoleUse.restore(self, grid)
	_build_navigation()
	Clock.time_changed.connect(_apply_time_of_day)
	Clock.field_renewed.connect(_on_field_renewed)
	_apply_time_of_day()
	_spawn_player()


func release_occupant(occupant_id: StringName) -> void:
	grid.remove(occupant_id)


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
	## `Global_kankyo_set` / `mEnv_SetBaseLight`: blended fine-weather colors + fog + dual lights.
	var pal: Dictionary = Clock.outdoor_light()
	_aim_directional(_sun, pal["sun_dir"] as Vector3)
	_sun.light_color = pal["sun"] as Color
	_sun.light_energy = float(pal["sun_energy"])
	_sun.shadow_enabled = _sun.light_energy > 0.08
	_aim_directional(_moon, pal["moon_dir"] as Vector3)
	_moon.light_color = pal["moon"] as Color
	_moon.light_energy = float(pal["moon_energy"])
	_moon.visible = _moon.light_energy > 0.02
	var env: Environment = _world_env.environment
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = pal["ambient"] as Color
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = pal["fog"] as Color
	env.fog_depth_begin = float(pal["fog_begin"])
	env.fog_depth_end = float(pal["fog_end"])
	env.fog_depth_curve = 1.0
	var bg: Color = pal["bg"] as Color
	env.background_color = bg
	env.background_mode = Environment.BG_SKY
	## Soft sky from `background_color` so dawn/dusk match the kankyo clear fill.
	var sky_mat: ProceduralSkyMaterial = env.sky.sky_material as ProceduralSkyMaterial
	if sky_mat != null:
		sky_mat.sky_top_color = bg.lightened(0.15)
		sky_mat.sky_horizon_color = bg.lerp(Color(0.75, 0.82, 0.9), 0.35)
		sky_mat.ground_horizon_color = bg.darkened(0.1)
		sky_mat.ground_bottom_color = bg.darkened(0.35)


func _aim_directional(light: DirectionalLight3D, dir: Vector3) -> void:
	## Decomp sun/moon dirs point toward the body; Godot shines along −Z.
	if light == null:
		return
	var d: Vector3 = dir
	if d.length_squared() < 0.0001:
		return
	d = d.normalized()
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.95:
		up = Vector3.RIGHT
	light.look_at(light.global_position - d, up)


func _on_field_renewed(_days: int) -> void:
	## Plant growth, shop restock, and weather roll subscribe here when those slices exist.
	pass
