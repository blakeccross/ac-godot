extends Node3D

## Outdoor weather particles (`ac_weather_*`). Camera-centered pool of 100 privs —
## rain streaks + splashes from `ef_ame02_*`, snow/sakura placeholders. Center follows
## the look-at (player), not the camera eye — original uses `Camera2_getCenterPos_p()`.
##
## Simulation is fixed at 60 Hz (`GAME_FRAME`), matching decomp priv timers / GX-per-frame
## speeds. Draw still runs every rendered frame so billboards track the camera.

const RAIN_SHADER := preload("res://shaders/weather_rain.gdshader")
const FLOAT_SHADER := preload("res://shaders/weather_particle.gdshader")
const POOL_SIZE := 100
## Actor / effect frame rate (GC display). Not player locomotion's 30 Hz feel scale.
const TICK_HZ := 60.0
const TICK_DT := 1.0 / TICK_HZ
const GX := FieldCatalog.GX_TO_METERS
const PIPELINE := FieldCatalog.PIPELINE_SCALE

## Rain spawn box around the look-at (GX → meters).
const RAIN_X := 130.0 * GX
const RAIN_Z_NEG := 200.0 * GX
const RAIN_Z_POS := 160.0 * GX
## `70 + 120` GX above ground (`aWeatherRain_make`).
const RAIN_HEIGHT := 190.0 * GX
## `speed.y = -9.5 + RANDOM_F(-2.5) - 2` → [-14, -11.5) GX per game frame.
const RAIN_SPEED_GX_MIN := -14.0
const RAIN_SPEED_GX_MAX := -11.5
## Fall 10 frames then splash (`1000 - timer >= 10`).
const RAIN_FALL_FRAMES := 10
## Splash timer 8 (`aWeatherRain_MakePicha`); frames advance `(8 - timer) >> 1`.
const SPLASH_FRAMES := 8
## `aWeatherRain_draw` rain_scale / picha_scale on authored ±1000 verts.
## Godot node scale = matrix_scale × GX / PIPELINE (same as `NpcFeelGlyphs`).
const RAIN_SCALE := Vector3(
	0.000299999985145 * GX / PIPELINE,
	0.035 * GX / PIPELINE,
	0.01 * GX / PIPELINE
)
const SPLASH_SCALE := 0.0033 * GX / PIPELINE
## `ef_ame02_setmode` PRIM / ENV.
const RAIN_PRIM := Color(255 / 255.0, 50 / 255.0, 50 / 255.0, 80 / 255.0)
const RAIN_ENV := Color(100 / 255.0, 225 / 255.0, 225 / 255.0, 1.0)
const RAIN_SHADE := 0.28
const RAIN_TEX_FALLBACK := "res://assets/generated/effects/ef_ame02_0.png"

const SNOW_X := 100.0 * GX
const SNOW_Z_NEG := 200.0 * GX
const SNOW_Z_POS := 180.0 * GX
const SNOW_HEIGHT := 230.0 * GX
const SNOW_LIFE_FRAMES := 280
const SNOW_SPEED_GX_MIN := -2.5
const SNOW_SPEED_GX_MAX := -0.5
const SNOW_DRIFT_MPS := 0.35
const SAKURA_FALL_EXTRA_GX := -0.4

const SPLASH_VISUALS: Array[StringName] = [
	&"ef_ame02_00",
	&"ef_ame02_01",
	&"ef_ame02_02",
	&"ef_ame02_03",
]
const RAIN_VISUAL := &"ef_ame02_04"

enum PartKind { RAIN, SPLASH, SNOW, SAKURA }

var _rng := RandomNumberGenerator.new()
var _frame: int = 0
var _tick_accum: float = 0.0
var _active: Array[Dictionary] = []
var _free: Array[int] = []
var _center: Vector3 = Vector3.ZERO
var _cam_basis: Basis = Basis.IDENTITY
var _cam_pos: Vector3 = Vector3.ZERO
var _lightning_left: float = 0.0
var _lightning_cooldown: float = 2.0
var _intensity: Weather.Intensity = Weather.Intensity.NONE
var _kind: Weather.Kind = Weather.Kind.CLEAR

var _rain_mmi: MultiMeshInstance3D
var _splash_mmi: Array[MultiMeshInstance3D] = []
var _float_mmi: MultiMeshInstance3D
var _rain_ready: bool = false


func _ready() -> void:
	add_to_group("weather_fx")
	_free.clear()
	_active.clear()
	for i: int in POOL_SIZE:
		_free.append(i)
	_setup_meshes()
	if not Game.weather_changed.is_connected(_on_weather_changed):
		Game.weather_changed.connect(_on_weather_changed)
	_sync_from_game()
	_sync_rain_se()


func _exit_tree() -> void:
	if Game.weather_changed.is_connected(_on_weather_changed):
		Game.weather_changed.disconnect(_on_weather_changed)
	Audio.stop_syslev()


func _on_weather_changed(_weather: StringName) -> void:
	_sync_from_game()
	_sync_rain_se()


func _sync_from_game() -> void:
	_kind = Weather.kind_from_name(Game.weather)
	_intensity = Game.weather_intensity as Weather.Intensity
	if _kind == Weather.Kind.CLEAR or _intensity == Weather.Intensity.NONE:
		_clear_pool()


func _sync_rain_se() -> void:
	## `aWeather_ChangeEnvSE` SysLev 7/8/9. Outdoor only.
	Audio.sync_rain_syslev(_kind, _intensity, Game.is_indoors())


func _setup_meshes() -> void:
	var tex: Texture2D = _load_rain_texture()
	var rain_mesh: Mesh = _load_effect_mesh(RAIN_VISUAL)
	_rain_ready = rain_mesh != null and tex != null
	if _rain_ready:
		_rain_mmi = _make_textured_mmi("Rain", rain_mesh, tex)
		add_child(_rain_mmi)
		for i: int in SPLASH_VISUALS.size():
			var splash_mesh: Mesh = _load_effect_mesh(SPLASH_VISUALS[i])
			if splash_mesh == null:
				splash_mesh = rain_mesh
			var mmi: MultiMeshInstance3D = _make_textured_mmi("Splash%d" % i, splash_mesh, tex)
			_splash_mmi.append(mmi)
			add_child(mmi)
	else:
		## No generated rain cards — keep a procedural streak fallback so weather still reads.
		_rain_mmi = _make_procedural_rain_mmi()
		add_child(_rain_mmi)
	_float_mmi = _make_float_mmi()
	add_child(_float_mmi)
	_hide_all_slots()


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
			var mat: Material = mi.get_active_material(i)
			var tex: Texture2D = _albedo_from_material(mat)
			if tex != null:
				return tex
	for child: Node in node.get_children():
		var found: Texture2D = _find_albedo_texture(child)
		if found != null:
			return found
	return null


func _albedo_from_material(mat: Material) -> Texture2D:
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).albedo_texture
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).albedo_texture
	if mat is ShaderMaterial:
		var sh := mat as ShaderMaterial
		var tex: Variant = sh.get_shader_parameter("albedo_texture")
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


func _make_textured_mmi(node_name: String, mesh: Mesh, tex: Texture2D) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 32.0
	var mat := ShaderMaterial.new()
	mat.shader = RAIN_SHADER
	mat.set_shader_parameter("intensity_tex", tex)
	mat.set_shader_parameter("prim_color", RAIN_PRIM)
	mat.set_shader_parameter("env_color", RAIN_ENV)
	mat.set_shader_parameter("shade_amt", RAIN_SHADE)
	mat.render_priority = 4
	var dup: Mesh = mesh.duplicate() as Mesh
	for s: int in dup.get_surface_count():
		dup.surface_set_material(s, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = false
	mm.instance_count = POOL_SIZE
	mm.visible_instance_count = POOL_SIZE
	mm.mesh = dup
	mmi.multimesh = mm
	return mmi


func _make_procedural_rain_mmi() -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "RainFallback"
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 32.0
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = FLOAT_SHADER
	mat.render_priority = 4
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = POOL_SIZE
	mm.visible_instance_count = POOL_SIZE
	mm.mesh = quad
	mmi.multimesh = mm
	_rain_ready = false
	return mmi


func _make_float_mmi() -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Floaters"
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 32.0
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = FLOAT_SHADER
	mat.render_priority = 4
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = POOL_SIZE
	mm.visible_instance_count = POOL_SIZE
	mm.mesh = quad
	mmi.multimesh = mm
	return mmi


func _process(delta: float) -> void:
	_update_center()
	var aabb := AABB(_center - Vector3(24.0, 4.0, 24.0), Vector3(48.0, 28.0, 48.0))
	if _rain_mmi != null:
		_rain_mmi.custom_aabb = aabb
	for mmi: MultiMeshInstance3D in _splash_mmi:
		mmi.custom_aabb = aabb
	if _float_mmi != null:
		_float_mmi.custom_aabb = aabb
	## Fixed 60 Hz sim so spawn density and GX/frame speeds match decomp at any render FPS.
	_tick_accum += delta
	while _tick_accum >= TICK_DT:
		_tick_accum -= TICK_DT
		_game_tick()
	_draw()
	_tick_lightning(delta)


func _game_tick() -> void:
	_frame += 1
	if _kind != Weather.Kind.CLEAR and _intensity != Weather.Intensity.NONE:
		_spawn_tick()
	_move_tick()


func _update_center() -> void:
	## Look-at / player, matching `Camera2_getCenterPos_p` — not the camera eye.
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		_cam_basis = cam.global_transform.basis
		_cam_pos = cam.global_position
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		if player.has_method("camera_look_position"):
			_center = player.call("camera_look_position") as Vector3
		else:
			_center = player.global_position + Vector3(0.0, 0.85, 0.0)
		return
	if cam != null:
		var forward: Vector3 = -cam.global_transform.basis.z
		var t: float = 0.0
		if absf(forward.y) > 0.001:
			t = -cam.global_position.y / forward.y
		_center = cam.global_position + forward * clampf(t, 8.0, 40.0)
		_center.y = maxf(_center.y, 0.5)


func _spawn_tick() -> void:
	match _kind:
		Weather.Kind.RAIN:
			var count: int = Weather.spawn_count_per_frame(_kind, _intensity)
			for _i: int in count:
				_spawn_rain()
		Weather.Kind.SNOW:
			if (_frame & Weather.snow_spawn_mask(_intensity)) == 0:
				_spawn_floater(PartKind.SNOW)
		Weather.Kind.SAKURA:
			if (_frame & Weather.snow_spawn_mask(_intensity)) == 0:
				_spawn_floater(PartKind.SAKURA)
		_:
			pass


func _spawn_rain() -> void:
	var id: int = _take_slot()
	if id < 0:
		return
	var xz := Vector3(
		_rng.randf_range(-RAIN_X, RAIN_X),
		0.0,
		_rng.randf_range(-RAIN_Z_NEG, RAIN_Z_POS)
	)
	var at: Vector3 = _center + xz
	var ground: float = _ground_y(at)
	var pos := Vector3(at.x, ground + RAIN_HEIGHT, at.z)
	## Meters per tick (= GX/frame × GX_TO_METERS).
	var speed_y: float = _rng.randf_range(RAIN_SPEED_GX_MIN, RAIN_SPEED_GX_MAX) * GX
	_active.append({
		"id": id,
		"kind": PartKind.RAIN,
		"pos": pos,
		"vel": Vector3(0.0, speed_y, 0.0),
		"life": RAIN_FALL_FRAMES,
		"max_life": RAIN_FALL_FRAMES,
		"phase": 0.0,
	})


func _spawn_floater(kind: PartKind) -> void:
	var id: int = _take_slot()
	if id < 0:
		return
	var offset := Vector3(
		_rng.randf_range(-SNOW_X, SNOW_X),
		SNOW_HEIGHT,
		_rng.randf_range(-SNOW_Z_NEG, SNOW_Z_POS)
	)
	var fall_gx: float = _rng.randf_range(SNOW_SPEED_GX_MIN, SNOW_SPEED_GX_MAX)
	if kind == PartKind.SAKURA:
		fall_gx += SAKURA_FALL_EXTRA_GX
	_active.append({
		"id": id,
		"kind": kind,
		"pos": _center + offset,
		"vel": Vector3(
			SNOW_DRIFT_MPS * TICK_DT,
			fall_gx * GX,
			SNOW_DRIFT_MPS * 0.35 * TICK_DT
		),
		"life": SNOW_LIFE_FRAMES,
		"max_life": SNOW_LIFE_FRAMES,
		"phase": _rng.randf() * TAU,
		"spin": _rng.randf_range(1.5, 4.0) * TICK_DT,
	})


func _spawn_splash(at: Vector3) -> void:
	var id: int = _take_slot()
	if id < 0:
		return
	var pos: Vector3 = at
	pos.y = _ground_y(at) + 0.04
	_active.append({
		"id": id,
		"kind": PartKind.SPLASH,
		"pos": pos,
		"vel": Vector3.ZERO,
		"life": SPLASH_FRAMES,
		"max_life": SPLASH_FRAMES,
		"phase": 0.0,
	})


func _move_tick() -> void:
	var keep: Array[Dictionary] = []
	for part: Dictionary in _active:
		var kind: int = int(part["kind"])
		var pos: Vector3 = part["pos"] as Vector3
		var vel: Vector3 = part["vel"] as Vector3
		var life: int = int(part["life"]) - 1
		if kind == PartKind.RAIN:
			pos += vel
			part["pos"] = pos
			part["life"] = life
			if life <= 0:
				_free_slot(int(part["id"]))
				_spawn_splash(pos)
				continue
		elif kind == PartKind.SPLASH:
			part["life"] = life
			if life <= 0:
				_free_slot(int(part["id"]))
				continue
		else:
			pos += vel
			part["phase"] = float(part.get("phase", 0.0)) + float(part.get("spin", 0.05))
			pos.x += sin(float(part["phase"])) * 0.3 * TICK_DT * 6.0
			pos.z += cos(float(part["phase"])) * 0.3 * TICK_DT * 6.0
			part["pos"] = pos
			_wrap_floater_inplace(part)
			pos = part["pos"] as Vector3
			if life <= 0 or pos.y < _center.y - 1.0:
				pos.y = _center.y + SNOW_HEIGHT
				part["pos"] = pos
				life = int(part["max_life"])
			part["life"] = life
		keep.append(part)
	_active = keep


func _wrap_floater_inplace(part: Dictionary) -> void:
	var pos: Vector3 = part["pos"] as Vector3
	var cx: float = _center.x
	var cz: float = _center.z
	if pos.x < cx - SNOW_X:
		pos.x += SNOW_X * 2.0
	elif pos.x > cx + SNOW_X:
		pos.x -= SNOW_X * 2.0
	if pos.z < cz - SNOW_Z_NEG:
		pos.z += SNOW_Z_NEG + SNOW_Z_POS
	elif pos.z > cz + SNOW_Z_POS:
		pos.z -= SNOW_Z_NEG + SNOW_Z_POS
	part["pos"] = pos


func _draw() -> void:
	_hide_all_slots()
	for part: Dictionary in _active:
		var id: int = int(part["id"])
		var kind: int = int(part["kind"])
		var pos: Vector3 = part["pos"] as Vector3
		var max_life: float = maxf(float(part["max_life"]), 1.0)
		var life_t: float = clampf(float(part["life"]) / max_life, 0.0, 1.0)
		match kind:
			PartKind.RAIN:
				_draw_rain(id, pos)
			PartKind.SPLASH:
				_draw_splash(id, pos, life_t)
			PartKind.SNOW:
				var scale: float = lerpf(0.2, 0.4, life_t)
				_set_float(id, _billboard(pos, Vector3(scale, scale, scale)), kind, life_t)
			PartKind.SAKURA:
				var scale_s: float = lerpf(0.22, 0.45, life_t)
				var ph: float = float(part.get("phase", 0.0))
				var xform := Transform3D(Basis.from_euler(Vector3(ph * 0.4, ph, ph * 0.2)), pos)
				xform.basis = xform.basis.scaled(Vector3(scale_s, scale_s * 0.7, scale_s))
				_set_float(id, xform, kind, life_t)


func _draw_rain(id: int, pos: Vector3) -> void:
	if _rain_mmi == null or _rain_mmi.multimesh == null:
		return
	if _rain_ready:
		_rain_mmi.multimesh.set_instance_transform(id, _yaw_billboard(pos, RAIN_SCALE))
	else:
		## Procedural fallback: decomp world size ~0.03 × 3.5 m.
		_rain_mmi.multimesh.set_instance_transform(id, _billboard(pos, Vector3(0.03, 3.5, 0.03)))
		_rain_mmi.multimesh.set_instance_custom_data(id, Color(0.0, 1.0, 0.0, 1.0))


func _draw_splash(id: int, pos: Vector3, life_t: float) -> void:
	## `disp = (8 - timer) >> 1` while timer counts 8→1.
	var elapsed: float = (1.0 - life_t) * float(SPLASH_FRAMES)
	var frame: int = clampi(int(elapsed) >> 1, 0, maxi(_splash_mmi.size() - 1, 0))
	if _splash_mmi.is_empty():
		return
	var s: float = SPLASH_SCALE
	## Full billboard like `Matrix_mult(&play->billboard_matrix)`.
	var xform := _full_billboard(pos, Vector3(s, s, s))
	for i: int in _splash_mmi.size():
		var mm: MultiMesh = _splash_mmi[i].multimesh
		if mm == null:
			continue
		if i == frame:
			mm.set_instance_transform(id, xform)
		else:
			mm.set_instance_transform(id, _hidden_xform())


func _set_float(id: int, xform: Transform3D, kind: int, life_t: float) -> void:
	if _float_mmi == null or _float_mmi.multimesh == null:
		return
	_float_mmi.multimesh.set_instance_transform(id, xform)
	_float_mmi.multimesh.set_instance_custom_data(id, Color(float(kind), life_t, 0.0, 1.0))


func _yaw_billboard(pos: Vector3, scale: Vector3) -> Transform3D:
	## `suMtxMakeSRT` with rotY = `search_position_angleY(center, eye)` — local scale then yaw.
	var to_eye: Vector3 = _cam_pos - pos
	to_eye.y = 0.0
	var yaw: float = 0.0
	if to_eye.length_squared() > 0.0001:
		yaw = atan2(to_eye.x, to_eye.z)
	var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * Basis.from_scale(scale)
	return Transform3D(basis, pos)


func _full_billboard(pos: Vector3, scale: Vector3) -> Transform3D:
	var right: Vector3 = _cam_basis.x
	var up: Vector3 = _cam_basis.y
	var forward: Vector3 = _cam_basis.z
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	right = right.normalized()
	up = up.normalized()
	forward = forward.normalized()
	var basis := Basis(right, up, forward) * Basis.from_scale(scale)
	return Transform3D(basis, pos)


func _billboard(pos: Vector3, scale: Vector3) -> Transform3D:
	## Face the camera; keep world-up (snow / procedural rain fallback).
	var right: Vector3 = _cam_basis.x
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := Vector3.UP
	var forward: Vector3 = right.cross(up).normalized()
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	right = up.cross(forward).normalized()
	var basis := Basis(right, up, forward).scaled(scale)
	return Transform3D(basis, pos)


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
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("set_lightning_flash"):
		return
	world.call("set_lightning_flash", on)


func _ground_y(at: Vector3) -> float:
	var world: Node = get_tree().get_first_node_in_group("world")
	if world != null and "layout" in world and "grid" in world:
		var data: WorldData = world.get("layout") as WorldData
		var grid: WorldGrid = world.get("grid") as WorldGrid
		var y: float = FieldCollision.ground_y_at(data, grid, at)
		if FieldCollision.has_floor(y):
			return y
	return maxf(_center.y - 0.85, 0.05)


func _take_slot() -> int:
	if _free.is_empty():
		return -1
	return _free.pop_back()


func _free_slot(id: int) -> void:
	_hide_slot(id)
	if not _free.has(id):
		_free.append(id)


func _hidden_xform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.0, -1000.0, 0.0))


func _hide_slot(id: int) -> void:
	var far: Transform3D = _hidden_xform()
	if _rain_mmi != null and _rain_mmi.multimesh != null:
		_rain_mmi.multimesh.set_instance_transform(id, far)
		if _rain_mmi.multimesh.use_custom_data:
			_rain_mmi.multimesh.set_instance_custom_data(id, Color(-1.0, 0.0, 0.0, 0.0))
	for mmi: MultiMeshInstance3D in _splash_mmi:
		if mmi.multimesh != null:
			mmi.multimesh.set_instance_transform(id, far)
	if _float_mmi != null and _float_mmi.multimesh != null:
		_float_mmi.multimesh.set_instance_transform(id, far)
		_float_mmi.multimesh.set_instance_custom_data(id, Color(-1.0, 0.0, 0.0, 0.0))


func _hide_all_slots() -> void:
	for i: int in POOL_SIZE:
		_hide_slot(i)


func _clear_pool() -> void:
	for part: Dictionary in _active:
		_free_slot(int(part["id"]))
	_active.clear()
