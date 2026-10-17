extends Node3D

## Outdoor weather (`ac_weather_*`): rain, snow and cherry petals as `GPUParticles3D` emitters
## authored in `weather_fx.tscn`, plus the rain sound level, umbrella swap and summer
## lightning.
##
## - **Rain** streaks (`ef_ame02_04`) fall from a box 190 GX above the look-at for 10 ticks.
##   As many splashes (`ef_ame02_00`–`03`, a four-card flipbook) land on the ground under
##   random points in the same box (`aWeatherRain_MakePicha`): the `Splash` emitter emits
##   from an emission-points texture this node refills with ground heights.
## - **Snow** (`ef_yuki01`) and **petals** (`ef_hanabira01`) run `weather_floaters.gdshader`:
##   fall, wobble, wind or drift, and wrap round a box on the camera look-at.
##
## Emitters sit on `Camera2_getCenterPos_p` (the follow camera's look-at, which eases /
## acre-clamps with the view — not the player's marker), so the volume stays on screen.

const GX := FieldCatalog.GX_TO_METERS
## `70 + 120` GX above ground (`aWeatherRain_make`).
const RAIN_HEIGHT := 190.0 * GX
## The rain box round the look-at: ±130 GX across, 200 back to 160 in front.
const RAIN_X := 130.0 * GX
const RAIN_Z_BACK := 200.0 * GX
const RAIN_Z_FRONT := 160.0 * GX
## Splashes sit just above the ground, picked from this many points, refreshed this often.
const SPLASH_LIFT := 0.04
const SPLASH_POINTS := 128
const SPLASH_REFRESH := 0.2
## `ef_ame02_setmode` PRIM / ENV.
const RAIN_PRIM := Color(255 / 255.0, 50 / 255.0, 50 / 255.0, 80 / 255.0)
const RAIN_ENV := Color(100 / 255.0, 225 / 255.0, 225 / 255.0, 1.0)
const RAIN_TEX_FALLBACK := "res://assets/generated/effects/ef_ame02_0.png"
const RAIN_VISUAL := &"ef_ame02_04"
const SPLASH_VISUALS: Array[StringName] = [&"ef_ame02_00", &"ef_ame02_01", &"ef_ame02_02", &"ef_ame02_03"]
const SNOW_SPRITE := "res://assets/generated/effects/ef_yuki01_sprite.png"
const PETAL_SPRITE := "res://assets/generated/effects/ef_hanabira01_sprite.png"
## The rain sound steps one level toward its aim every 180 frames (`aWeather_RenewWeatherLevel`).
const LEVEL_STEP_TIME := Weather.LEVEL_STEP_FRAMES / 60.0
## `aWeatherSnow_SetWind2Snow`: flakes ride half the day's wind power, in GX a tick.
const SNOW_WIND_SCALE := 0.5 * GX * 60.0

## Share of each emitter's `amount` by intensity (rain 1/2/3 a frame; snow every 8/4/2
## frames; petals every 8 frames when light, else every 4).
const RAIN_SHARE := {Weather.Intensity.LIGHT: 1.0 / 3.0, Weather.Intensity.NORMAL: 2.0 / 3.0, Weather.Intensity.HEAVY: 1.0}
const SNOW_SHARE := {Weather.Intensity.LIGHT: 0.25, Weather.Intensity.NORMAL: 0.5, Weather.Intensity.HEAVY: 1.0}
const PETAL_SHARE := {Weather.Intensity.LIGHT: 0.5, Weather.Intensity.NORMAL: 1.0, Weather.Intensity.HEAVY: 1.0}

var _rng := RandomNumberGenerator.new()
## The weather actor's `current_level` for the rain SysLev: the saved intensity when the scene
## starts, then stepped toward the new aim every `LEVEL_STEP_TIME` after a change.
var _se_level: int = 0
var _level_wait: float = 0.0
## `weather->umbrella_flag`: the player's umbrella was open last frame.
var _umbrella_open: bool = false
var _lightning_left: float = 0.0
var _lightning_cooldown: float = 2.0
var _intensity: Weather.Intensity = Weather.Intensity.NONE
var _splash_points: Image = Image.create(SPLASH_POINTS, 1, false, Image.FORMAT_RGBF)
var _splash_texture: ImageTexture = null
var _splash_refresh: float = 0.0
var _kind: Weather.Kind = Weather.Kind.CLEAR

@onready var _rain: GPUParticles3D = $Rain
@onready var _splash: GPUParticles3D = $Splash
@onready var _snow: GPUParticles3D = $Snow
@onready var _petals: GPUParticles3D = $Petals


func _ready() -> void:
	add_to_group("weather_fx")
	_attach_art()
	if not Game.weather_changed.is_connected(_on_weather_changed):
		Game.weather_changed.connect(_on_weather_changed)
	_sync_from_game()
	_se_level = int(_intensity) if _kind != Weather.Kind.CLEAR else 0
	_sync_rain_se()


func _exit_tree() -> void:
	if Game.weather_changed.is_connected(_on_weather_changed):
		Game.weather_changed.disconnect(_on_weather_changed)
	Audio.stop_syslev()


func _process(delta: float) -> void:
	var center: Vector3 = _center()
	_rain.global_position = center + Vector3(0.0, RAIN_HEIGHT, 0.0)
	_snow.global_position = center
	_petals.global_position = center
	if _snow.emitting:
		var wind := Vector3(sin(Wind.yaw()), 0.0, cos(Wind.yaw())) * Wind.power() * SNOW_WIND_SCALE
		(_snow.process_material as ShaderMaterial).set_shader_parameter("drift", wind)
	_splash.global_position = center
	if _rain.emitting:
		_splash_refresh -= delta
		if _splash_refresh <= 0.0:
			_splash_refresh = SPLASH_REFRESH
			_place_splashes(center)
	_renew_level(delta)
	_check_umbrella()
	_tick_lightning(delta)


## Fresh splash points: random spots in the rain box, on the ground there, relative to the
## emitter at `center`.
func _place_splashes(center: Vector3) -> void:
	for i: int in SPLASH_POINTS:
		var at: Vector3 = center + Vector3(
			_rng.randf_range(-RAIN_X, RAIN_X), 0.0, _rng.randf_range(-RAIN_Z_BACK, RAIN_Z_FRONT))
		at.y = _ground_y(at, center.y) + SPLASH_LIFT
		var local: Vector3 = at - center
		_splash_points.set_pixel(i, 0, Color(local.x, local.y, local.z))
	if _splash_texture == null:
		_splash_texture = ImageTexture.create_from_image(_splash_points)
		var process := _splash.process_material as ParticleProcessMaterial
		process.emission_point_texture = _splash_texture
		process.emission_point_count = SPLASH_POINTS
	else:
		_splash_texture.update(_splash_points)


func _ground_y(at: Vector3, fallback: float) -> float:
	var world := World.find(get_tree())
	if world != null:
		var y: float = FieldCollision.ground_y_at(world.layout, world.grid, at)
		if FieldCollision.has_floor(y):
			return y
	return fallback - 0.85


func _on_weather_changed(_weather: StringName) -> void:
	var was: Weather.Kind = _kind
	_sync_from_game()
	## `aWeather_ChangeWeather`: a new type comes in at level 1 and ramps from there; the same
	## type only changes its aim.
	if _kind != was:
		_se_level = 1 if _kind != Weather.Kind.CLEAR and _intensity != Weather.Intensity.NONE else 0
		_level_wait = LEVEL_STEP_TIME
	_sync_rain_se()


func _sync_from_game() -> void:
	_kind = Weather.kind_from_name(Game.town.weather)
	_intensity = Game.town.weather_intensity as Weather.Intensity
	var on: bool = _kind != Weather.Kind.CLEAR and _intensity != Weather.Intensity.NONE
	_emit(_rain, on and _kind == Weather.Kind.RAIN, RAIN_SHARE)
	_emit(_splash, on and _kind == Weather.Kind.RAIN, RAIN_SHARE)
	_emit(_snow, on and _kind == Weather.Kind.SNOW, SNOW_SHARE)
	_emit(_petals, on and _kind == Weather.Kind.SAKURA, PETAL_SHARE)


## Turns `emitter` on at its share for the current intensity, or off; particles already in
## the air finish their fall.
func _emit(emitter: GPUParticles3D, on: bool, share: Dictionary) -> void:
	if on:
		emitter.amount_ratio = float(share.get(_intensity, 1.0))
	if emitter.emitting != on:
		emitter.emitting = on


func _sync_rain_se() -> void:
	## `aWeather_ChangeEnvSE` SysLev 7/8/9 by the current (ramping) level.
	Audio.sync_rain_syslev(_kind, _se_level, Game.is_indoors(), false, _umbrella_open)


## `Weather_Actor_move`: while it rains, an umbrella opening or closing swaps the rain loop for
## the under-the-umbrella one (`mPlib_check_player_open_umbrella` vs `umbrella_flag`).
func _check_umbrella() -> void:
	if _kind != Weather.Kind.RAIN:
		return
	var player := Player.find(get_tree())
	var open: bool = player != null and player.tools.is_umbrella_open()
	if open != _umbrella_open:
		_umbrella_open = open
		_sync_rain_se()


## `aWeather_RenewWeatherLevel`: one step toward the aim every `LEVEL_STEP_TIME`.
func _renew_level(delta: float) -> void:
	var aim: int = int(_intensity) if _kind != Weather.Kind.CLEAR else 0
	if _se_level == aim:
		_level_wait = LEVEL_STEP_TIME
		return
	_level_wait -= delta
	if _level_wait > 0.0:
		return
	_level_wait = LEVEL_STEP_TIME
	_se_level = Weather.step_level(_se_level, aim)
	_sync_rain_se()


## `Camera2_getCenterPos_p`: the follow camera's look-at centre, not the eye and not the
## player's marker (that marker drifts ahead of a lagging / acre-clamped view).
func _center() -> Vector3:
	var follow: FollowCamera = _follow_camera()
	if follow != null:
		return follow.look_center()
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is FollowCamera:
		return (cam as FollowCamera).look_center()
	if cam != null:
		## Demo / cutscene cameras: project the view ray to a ground-ish height.
		var forward: Vector3 = -cam.global_transform.basis.z
		var t: float = 8.0
		if absf(forward.y) > 0.001:
			t = clampf(-cam.global_position.y / forward.y, 8.0, 40.0)
		var at: Vector3 = cam.global_position + forward * t
		at.y = maxf(at.y, 0.5)
		return at
	var player := Player.find(get_tree())
	if player != null:
		return player.camera_look_position()
	return Vector3.ZERO


func _follow_camera() -> FollowCamera:
	for node: Node in get_tree().get_nodes_in_group(FollowCamera.GROUP):
		if node is FollowCamera and is_instance_valid(node):
			var cam := node as FollowCamera
			if cam.current:
				return cam
	for node: Node in get_tree().get_nodes_in_group(FollowCamera.GROUP):
		if node is FollowCamera and is_instance_valid(node):
			return node as FollowCamera
	return null


func _tick_lightning(delta: float) -> void:
	## June–August heavy rain: ambient flash (`aWeather_MakeKaminari`).
	if _lightning_left > 0.0:
		_lightning_left -= delta
		if _lightning_left <= 0.0:
			_apply_lightning(false)
		return
	if _kind != Weather.Kind.RAIN or _intensity != Weather.Intensity.HEAVY:
		return
	if Clock.month < 6 or Clock.month > 8:
		return
	_lightning_cooldown -= delta
	if _lightning_cooldown > 0.0:
		return
	_lightning_left = 0.12
	_lightning_cooldown = _rng.randf_range(4.0, 12.0)
	Audio.play_se(&"424")
	_apply_lightning(true)


func _apply_lightning(on: bool) -> void:
	var world := World.find(get_tree())
	if world == null:
		return
	world.set_lightning_flash(on)


# --- generated art --------------------------------------------------------------------


## Swaps in the converted rain / splash cards and the snow / petal sprites when they have
## been generated; without them the scene's plain cards stand in.
func _attach_art() -> void:
	## This node rewrites the splash points; keep its process material to itself.
	_splash.process_material = _splash.process_material.duplicate()
	_place_splashes(_center())
	var tex: Texture2D = _load_rain_texture()
	var rain_mesh: Mesh = _load_effect_mesh(RAIN_VISUAL)
	_dress(_rain, rain_mesh, tex)
	## The four splash cards as one mesh, a surface each, every surface drawn only for its
	## quarter of the splash's life (one draw pass, so it works on every renderer).
	var frames: Array[Mesh] = []
	for visual: StringName in SPLASH_VISUALS:
		var mesh: Mesh = _load_effect_mesh(visual)
		if mesh != null:
			frames.append(mesh)
	if frames.size() == SPLASH_VISUALS.size():
		_dress(_splash, _flipbook(frames), tex)
	else:
		_dress(_splash, rain_mesh, tex)
	_sprite(_snow, SNOW_SPRITE, Color(0.97, 0.98, 1.0, 0.9))
	_sprite(_petals, PETAL_SPRITE, Color(1.0, 0.72, 0.82, 0.85))


## `emitter`'s card: the converted `mesh` (its surfaces keeping any per-surface frame
## index), drawn with the scene's card material textured with `tex`.
func _dress(emitter: GPUParticles3D, mesh: Mesh, tex: Texture2D) -> void:
	var card := emitter.draw_pass_1 as PrimitiveMesh
	if card == null:
		return
	var base := card.material as ShaderMaterial
	if base == null:
		return
	base = base.duplicate() as ShaderMaterial
	base.set_shader_parameter("prim_color", RAIN_PRIM)
	base.set_shader_parameter("env_color", RAIN_ENV)
	base.set_shader_parameter("intensity_tex", tex if tex != null else _solid_texture())
	if mesh == null:
		card.material = base
		return
	var frames: Array = mesh.get_meta(&"frames", [])
	var dup: Mesh = mesh.duplicate() as Mesh
	for s: int in dup.get_surface_count():
		var mat := base
		if s < frames.size():
			mat = base.duplicate() as ShaderMaterial
			mat.set_shader_parameter("frame_index", int(frames[s]))
			mat.set_shader_parameter("frame_count", SPLASH_VISUALS.size())
		dup.surface_set_material(s, mat)
	emitter.draw_pass_1 = dup


## One mesh holding every surface of `frames`, tagged with the frame each came from.
static func _flipbook(frames: Array[Mesh]) -> ArrayMesh:
	var out := ArrayMesh.new()
	var tags: Array = []
	for i: int in frames.size():
		for s: int in frames[i].get_surface_count():
			out.add_surface_from_arrays(
				frames[i].surface_get_primitive_type(s), frames[i].surface_get_arrays(s))
			tags.append(i)
	out.set_meta(&"frames", tags)
	return out


func _sprite(emitter: GPUParticles3D, path: String, fallback: Color) -> void:
	var card := emitter.get_draw_pass_mesh(0) as PrimitiveMesh
	if card == null:
		return
	var mat := (card.material as StandardMaterial3D).duplicate() as StandardMaterial3D
	if ResourceLoader.exists(path):
		mat.albedo_texture = load(path) as Texture2D
	else:
		mat.albedo_color = fallback
	card.material = mat


static func _solid_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _load_rain_texture() -> Texture2D:
	## Prefer albedo baked into the streak GLB; fall back to a sibling I4 PNG.
	var from_mesh: Texture2D = _texture_from_visual(RAIN_VISUAL)
	if from_mesh != null:
		return from_mesh
	if ResourceLoader.exists(RAIN_TEX_FALLBACK):
		return load(RAIN_TEX_FALLBACK) as Texture2D
	return null


func _texture_from_visual(visual_id: StringName) -> Texture2D:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual_id)
	if paths.is_empty():
		return null
	var packed: PackedScene = load(paths[0]) as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	var tex: Texture2D = _find_albedo_texture(inst)
	inst.free()
	return tex


func _find_albedo_texture(node: Node) -> Texture2D:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var surface_count: int = mi.mesh.get_surface_count() if mi.mesh != null else 1
		for i: int in surface_count:
			var tex: Texture2D = _albedo_from_material(mi.get_active_material(i))
			if tex != null:
				return tex
	for child: Node in node.get_children():
		var found: Texture2D = _find_albedo_texture(child)
		if found != null:
			return found
	return null


func _albedo_from_material(mat: Material) -> Texture2D:
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).albedo_texture
	if mat is ShaderMaterial:
		var tex: Variant = (mat as ShaderMaterial).get_shader_parameter("albedo_texture")
		if tex is Texture2D:
			return tex as Texture2D
	return null


func _load_effect_mesh(visual_id: StringName) -> Mesh:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual_id)
	if paths.is_empty():
		return null
	var packed: PackedScene = load(paths[0]) as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	var mesh: Mesh = _find_mesh(inst)
	inst.free()
	return mesh


func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			return mi.mesh
	for child: Node in node.get_children():
		var found: Mesh = _find_mesh(child)
		if found != null:
			return found
	return null
