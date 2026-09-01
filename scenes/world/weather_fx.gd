extends MultiMeshInstance3D

## Outdoor weather particles (`ac_weather_*`). Camera-centered pool of 100 privs —
## rain streaks + splashes, snow, sakura. Center follows the *look-at* (player), not the
## camera eye — original uses `Camera2_getCenterPos_p()`.

const SHADER := preload("res://shaders/weather_particle.gdshader")
const POOL_SIZE := 100
const GAME_FPS := 60.0
const GX := FieldCatalog.GX_TO_METERS

## Rain spawn box around the look-at (GX → meters).
const RAIN_X := 130.0 * GX
const RAIN_Z_NEG := 200.0 * GX
const RAIN_Z_POS := 160.0 * GX
## `70 + 120` GX above ground (`aWeatherRain_make`).
const RAIN_HEIGHT := 190.0 * GX
## ~(-9.5..-12 - 2) GX/frame at 60 Hz.
const RAIN_SPEED_MIN := -14.0 * GX * GAME_FPS
const RAIN_SPEED_MAX := -11.5 * GX * GAME_FPS
## 10 mover frames then splash (`1000 - timer >= 10`).
const RAIN_FALL_LIFE := 10.0 / GAME_FPS
const SPLASH_LIFE := 8.0 / GAME_FPS
## Streak size: original mesh × `rain_scale` reads larger than a 0.5 m placeholder at 20° FOV.
const RAIN_STREAK := Vector3(0.12, 1.4, 0.12)

const SNOW_X := 100.0 * GX
const SNOW_Z_NEG := 200.0 * GX
const SNOW_Z_POS := 180.0 * GX
const SNOW_HEIGHT := 230.0 * GX
const SNOW_LIFE := 280.0 / GAME_FPS
const SNOW_SPEED_MIN := -2.5 * GX * GAME_FPS
const SNOW_SPEED_MAX := -0.5 * GX * GAME_FPS
const SNOW_DRIFT := 0.35
const SAKURA_FALL_EXTRA := -0.4

enum PartKind { RAIN, SPLASH, SNOW, SAKURA }

var _material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _frame: int = 0
var _active: Array[Dictionary] = []
var _free: Array[int] = []
var _center: Vector3 = Vector3.ZERO
var _cam_basis: Basis = Basis.IDENTITY
var _lightning_left: float = 0.0
var _lightning_cooldown: float = 2.0
var _intensity: Weather.Intensity = Weather.Intensity.NONE
var _kind: Weather.Kind = Weather.Kind.CLEAR


func _ready() -> void:
	add_to_group("weather_fx")
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 32.0
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = 4
	quad.material = _material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = POOL_SIZE
	mm.visible_instance_count = POOL_SIZE
	mm.mesh = quad
	multimesh = mm
	_free.clear()
	_active.clear()
	for i: int in POOL_SIZE:
		_free.append(i)
		_hide_slot(i)
	if not Game.weather_changed.is_connected(_on_weather_changed):
		Game.weather_changed.connect(_on_weather_changed)
	_sync_from_game()


func _exit_tree() -> void:
	if Game.weather_changed.is_connected(_on_weather_changed):
		Game.weather_changed.disconnect(_on_weather_changed)


func _on_weather_changed(_weather: StringName) -> void:
	_sync_from_game()


func _sync_from_game() -> void:
	_kind = Weather.kind_from_name(Game.weather)
	_intensity = Game.weather_intensity as Weather.Intensity
	if _kind == Weather.Kind.CLEAR or _intensity == Weather.Intensity.NONE:
		_clear_pool()


func _process(delta: float) -> void:
	_frame += 1
	_update_center()
	## Keep the MultiMesh AABB around the field so far-away hide slots do not cull us.
	custom_aabb = AABB(
		_center - Vector3(24.0, 4.0, 24.0),
		Vector3(48.0, 28.0, 48.0)
	)
	if _kind != Weather.Kind.CLEAR and _intensity != Weather.Intensity.NONE:
		_spawn(delta)
	_move(delta)
	_draw()
	_tick_lightning(delta)


func _update_center() -> void:
	## Look-at / player, matching `Camera2_getCenterPos_p` — not the camera eye.
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		_cam_basis = cam.global_transform.basis
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		if player.has_method("camera_look_position"):
			_center = player.call("camera_look_position") as Vector3
		else:
			_center = player.global_position + Vector3(0.0, 0.85, 0.0)
		return
	if cam is Camera3D and cam.has_method("_look_point"):
		## FollowCamera private — fall through to eye-projected ground.
		pass
	if cam != null:
		## Project a point ~look distance along -Z into the ground plane near Y=0.
		var forward: Vector3 = -cam.global_transform.basis.z
		var t: float = 0.0
		if absf(forward.y) > 0.001:
			t = -cam.global_position.y / forward.y
		_center = cam.global_position + forward * clampf(t, 8.0, 40.0)
		_center.y = maxf(_center.y, 0.5)


func _spawn(_delta: float) -> void:
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
	_active.append({
		"id": id,
		"kind": PartKind.RAIN,
		"pos": pos,
		"vel": Vector3(0.0, _rng.randf_range(RAIN_SPEED_MIN, RAIN_SPEED_MAX), 0.0),
		"life": RAIN_FALL_LIFE,
		"max_life": RAIN_FALL_LIFE,
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
	var fall: float = _rng.randf_range(SNOW_SPEED_MIN, SNOW_SPEED_MAX)
	if kind == PartKind.SAKURA:
		fall += SAKURA_FALL_EXTRA * GX * GAME_FPS
	_active.append({
		"id": id,
		"kind": kind,
		"pos": _center + offset,
		"vel": Vector3(SNOW_DRIFT, fall, SNOW_DRIFT * 0.35),
		"life": SNOW_LIFE,
		"max_life": SNOW_LIFE,
		"phase": _rng.randf() * TAU,
		"spin": _rng.randf_range(1.5, 4.0),
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
		"life": SPLASH_LIFE,
		"max_life": SPLASH_LIFE,
		"phase": 0.0,
	})


func _move(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for part: Dictionary in _active:
		var kind: int = int(part["kind"])
		var pos: Vector3 = part["pos"] as Vector3
		var vel: Vector3 = part["vel"] as Vector3
		var life: float = float(part["life"]) - delta
		if kind == PartKind.RAIN:
			pos += vel * delta
			part["pos"] = pos
			part["life"] = life
			if life <= 0.0:
				_free_slot(int(part["id"]))
				_spawn_splash(pos)
				continue
		elif kind == PartKind.SPLASH:
			part["life"] = life
			if life <= 0.0:
				_free_slot(int(part["id"]))
				continue
		else:
			pos += vel * delta
			part["phase"] = float(part.get("phase", 0.0)) + float(part.get("spin", 2.0)) * delta
			pos.x += sin(float(part["phase"])) * 0.3 * delta * 6.0
			pos.z += cos(float(part["phase"])) * 0.3 * delta * 6.0
			part["pos"] = pos
			_wrap_floater_inplace(part)
			pos = part["pos"] as Vector3
			if life <= 0.0 or pos.y < _center.y - 1.0:
				pos.y = _center.y + SNOW_HEIGHT
				part["pos"] = pos
				life = float(part["max_life"])
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
	for part: Dictionary in _active:
		var id: int = int(part["id"])
		var kind: int = int(part["kind"])
		var pos: Vector3 = part["pos"] as Vector3
		var life_t: float = clampf(float(part["life"]) / maxf(float(part["max_life"]), 0.001), 0.0, 1.0)
		var xform := Transform3D()
		match kind:
			PartKind.RAIN:
				## Billboard vertical streak toward the camera (`current_yAngle` + rain SRT).
				xform = _billboard(pos, RAIN_STREAK)
			PartKind.SPLASH:
				xform = Transform3D(
					Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)).scaled(Vector3(0.55, 0.55, 0.55)),
					pos
				)
			PartKind.SNOW:
				var scale: float = lerpf(0.2, 0.4, life_t)
				xform = _billboard(pos, Vector3(scale, scale, scale))
			PartKind.SAKURA:
				var scale_s: float = lerpf(0.22, 0.45, life_t)
				var ph: float = float(part.get("phase", 0.0))
				xform = Transform3D(Basis.from_euler(Vector3(ph * 0.4, ph, ph * 0.2)), pos)
				xform.basis = xform.basis.scaled(Vector3(scale_s, scale_s * 0.7, scale_s))
		multimesh.set_instance_transform(id, xform)
		multimesh.set_instance_custom_data(id, Color(float(kind), life_t, 0.0, 1.0))


func _billboard(pos: Vector3, scale: Vector3) -> Transform3D:
	## Face the camera; keep world-up so rain streaks stay vertical.
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


func _hide_slot(id: int) -> void:
	if multimesh == null:
		return
	var far := Transform3D(Basis.IDENTITY, Vector3(0.0, -1000.0, 0.0))
	multimesh.set_instance_transform(id, far)
	multimesh.set_instance_custom_data(id, Color(-1.0, 0.0, 0.0, 0.0))


func _clear_pool() -> void:
	for part: Dictionary in _active:
		_free_slot(int(part["id"]))
	_active.clear()
