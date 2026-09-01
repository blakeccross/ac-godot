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
	FieldCatalog.warn_grass_pattern_pack_missing()
	print(
		"Grass pattern: %s (%d)" % [
			WorldData.grass_pattern_label(layout.grass_pattern), layout.grass_pattern
		]
	)
	print(WorldGenerator.map_text(layout))
	WorldBuilder.new().build(self, layout, grid)
	HoleUse.restore(self, grid)
	PlantGrowth.restore(self, grid)
	_build_navigation()
	Clock.time_changed.connect(_apply_time_of_day)
	Clock.field_renewed.connect(_on_field_renewed)
	Clock.hour_changed.connect(_on_hour_changed)
	Clock.season_changed.connect(_on_season_changed)
	Game.weather_changed.connect(_on_weather_changed)
	_apply_time_of_day()
	_play_outdoor_bgm()
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


func _exit_tree() -> void:
	if Clock.hour_changed.is_connected(_on_hour_changed):
		Clock.hour_changed.disconnect(_on_hour_changed)
	if Clock.season_changed.is_connected(_on_season_changed):
		Clock.season_changed.disconnect(_on_season_changed)
	if Game.weather_changed.is_connected(_on_weather_changed):
		Game.weather_changed.disconnect(_on_weather_changed)


func _on_hour_changed(_hour: int) -> void:
	_play_outdoor_bgm()


func _on_weather_changed(_weather: StringName) -> void:
	_play_outdoor_bgm()


func _play_outdoor_bgm() -> void:
	Audio.play_bgm(BgmCatalog.outdoor_id(Clock.hour, Game.weather))


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
	GeneratedVisual.refresh_window_lights(self)
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
	PlantGrowth.refresh_world(self)


func _on_season_changed(_season: Clock.Season) -> void:
	## Acre CI banks (`grd_s_*` / `grd_w_*`) and seasonal tree meshes (`obj_s/f/w_*`).
	_refresh_seasonal_visuals()


func _refresh_seasonal_visuals() -> void:
	var acres: Node = get_node_or_null("Terrain/Acres")
	if acres == null:
		var single: Node = get_node_or_null("Terrain/Acre")
		if single is Node3D and single.has_meta("visual_id"):
			_reattach_visual(single as Node3D, single.get_meta("visual_id") as StringName)
	else:
		for child in acres.get_children():
			if child is Node3D and child.has_meta("visual_id"):
				_reattach_visual(child as Node3D, child.get_meta("visual_id") as StringName)
	for node in get_tree().get_nodes_in_group("plant"):
		if node.has_method("refresh_seasonal_visual"):
			node.call("refresh_seasonal_visual")
		elif node.has_method("apply_growth"):
			node.call("apply_growth")
	for root_name: String in ["Buildings", "Objects"]:
		var root: Node = get_node_or_null(root_name)
		if root == null:
			continue
		for child in root.get_children():
			if child.is_in_group("plant"):
				continue
			_refresh_env_visual(child)


func _refresh_env_visual(node: Node) -> void:
	if node.has_method("refresh_seasonal_visual"):
		node.call("refresh_seasonal_visual")
		return
	if not (node is Node3D) or not ("visual_id" in node):
		return
	var visual_id: StringName = node.get("visual_id") as StringName
	if not FieldCatalog.is_seasonal_env_visual(visual_id):
		return
	GeneratedVisual.refresh(node as Node3D, visual_id)


func _reattach_visual(host: Node3D, visual_id: StringName) -> void:
	GeneratedVisual.refresh(host, visual_id)
