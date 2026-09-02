class_name MuseumFishActor
extends RefCounted

## One donated fish swimming in a museum tank (`MUSEUM_FISH_PRIVATE_DATA`).
## Movement follows `mfish_base_FishMove` / `Museum_Fish_BGCheck` / wall turn — not a
## mechanical C port, but the same bounds, lookahead, and turn responses.

const GAME_FPS := 30.0
## `Museum_Fish_BGCheck` base half-extent for tanks 0–3.
const TANK_HALF_BASE_GX := 54.0
## `mfish_WallCheck` look-ahead (`GETREG(TAKREG,70)+30`, reg usually 0).
const WALL_LOOKAHEAD_GX := 30.0
## Absolute Y clamp in GX before the water-line floor snap (`mfish_base_FishMove`).
const Y_MIN_GX := 60.0
const Y_MAX_GX := 110.0


var fish: FishData = null
var fish_index: int = -1
var tank: int = 0
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var active: bool = true

var _tank_center: Vector3 = Vector3.ZERO
var _swim_y: float = 2.0
var _speed: float = 0.4
var _target_speed: float = 0.4
var _speed_min: float = 0.4
var _speed_range: float = 0.45
var _drag: float = 0.99
var _body_pad: float = -6.0
var _ofs_z: float = -3.5
var _turn_limit: float = deg_to_rad(70.0)
var _activity: float = 0.0
var _target_yaw: float = 0.0
var _wall_yaw: float = 0.0
var _wall_flags: int = 0
var _rng: RandomNumberGenerator = null
var _init_scale: float = 0.01
var model_lift: float = 0.0
var _water_line_gx: float = 40.0


static func create(p_fish: FishData, index: int, grid: WorldGrid, rng: RandomNumberGenerator) -> MuseumFishActor:
	if p_fish == null or index < 0:
		return null
	var actor := MuseumFishActor.new()
	actor.fish = p_fish
	actor.fish_index = index
	actor.tank = MuseumDisplay.fish_tank(index)
	actor._rng = rng if rng != null else RandomNumberGenerator.new()
	var init: Dictionary = MuseumDisplay.fish_init(index)
	actor._init_scale = float(init.get("render_scale", 0.01))
	actor.model_lift = float(init.get("ofs_y", 0.0)) * FieldCatalog.GX_TO_METERS
	actor._body_pad = float(init.get("body_pad", -6.0))
	actor._ofs_z = float(init.get("ofs_z", -3.5))
	actor._speed_min = float(init.get("speed", 0.4))
	actor._speed_range = float(init.get("speed_range", 0.45))
	actor._drag = float(init.get("drag", 0.98995))
	actor._turn_limit = deg_to_rad(float(init.get("turn_deg", 70.0)))
	## `_0C` is absolute swim Y in GX. Shell floors snap authored Y=40 GX to world 0.
	actor._water_line_gx = MuseumDisplay.TANK_POS_GX[actor.tank].y
	var swim_gx: float = float(init.get("depth", 70.0))
	actor._swim_y = (swim_gx - actor._water_line_gx) * FieldCatalog.GX_TO_METERS
	actor._speed = actor._speed_min * FieldCatalog.GX_TO_METERS * GAME_FPS
	actor._target_speed = actor._speed
	var active_min: int = int(init.get("active_min", 120))
	var active_range: int = int(init.get("active_range", 120))
	actor._activity = float(active_min + actor._rng.randi_range(0, maxi(active_range, 0))) / GAME_FPS
	var center_gx: Vector3 = MuseumDisplay.TANK_POS_GX[actor.tank]
	actor._tank_center = MuseumDisplay.gx_to_world(grid, Vector3(center_gx.x, 0.0, center_gx.z))
	## Start inside the tightest BGCheck half (`54 + _28`).
	var half: Vector3 = actor._swim_half_gx(1.0, 1.0) * FieldCatalog.GX_TO_METERS
	var jitter: float = actor._rng.randf_range(-0.5, 0.5) * FieldCatalog.GX_TO_METERS * 10.0
	actor.position = Vector3(
		actor._tank_center.x + actor._rng.randf_range(-1.0, 1.0) * half.x * 0.35,
		actor._swim_y + jitter,
		actor._tank_center.z + actor._rng.randf_range(-1.0, 1.0) * half.z * 0.35
	)
	actor.yaw = actor._rng.randf() * TAU
	actor._target_yaw = actor.yaw
	actor.active = true
	return actor


func render_scale() -> float:
	## `mfish_init_data.renderScale` → same conversion as `FieldCatalog.actor_uniform_scale`.
	return _init_scale / FieldCatalog.PIPELINE_SCALE * FieldCatalog.GX_TO_METERS


func tick(delta: float) -> void:
	if fish == null:
		return
	_activity -= delta
	while _activity <= 0.0:
		_on_activity_expired()
		var init: Dictionary = MuseumDisplay.fish_init(fish_index)
		var active_min: int = int(init.get("active_min", 120))
		var active_range: int = int(init.get("active_range", 120))
		_activity += float(active_min + _rng.randi_range(0, maxi(active_range, 0))) / GAME_FPS
	## Ease yaw toward target (`add_calc_short_angle2`, ~6.25°/frame max).
	var max_turn: float = deg_to_rad(6.25) * delta * GAME_FPS
	var diff: float = wrapf(_target_yaw - yaw, -PI, PI)
	yaw = wrapf(yaw + clampf(diff, -max_turn, max_turn), -PI, PI)
	## Speed eases toward the burst target, then decays (`_18` drag).
	var speed_step: float = FieldCatalog.GX_TO_METERS * GAME_FPS
	_speed = move_toward(_speed, _target_speed, 0.75 * speed_step * delta)
	_target_speed = maxf(_target_speed * pow(_drag, delta * GAME_FPS), 0.0)
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var move: float = _speed * delta
	if fish.id == &"jellyfish":
		position.y += sin(Time.get_ticks_msec() * 0.002 + float(fish_index)) * 0.15 * delta
		move *= 0.35
	elif fish.id == &"eel":
		position.y = lerpf(position.y, _swim_y * 0.35, 0.05)
	position += forward * move
	## Ease Y toward cruise depth (`add_calc2` toward `_5F4 + _0C`).
	position.y = lerpf(position.y, _swim_y, clampf(0.1 * delta * GAME_FPS, 0.0, 1.0))
	_bg_check()
	## Mid-cruise: if heading into a wall, kick a turn like `mfish_normal_process`.
	if _wall_flags != 0 and absf(wrapf(_wall_yaw - yaw, -PI, PI)) < deg_to_rad(30.0):
		_start_wall_turn()
	pitch = clampf((position.y - _swim_y) * 0.15, -0.35, 0.35)


## `Museum_Fish_BGCheck` half extents in GX (before meter scale).
func _swim_half_gx(scale_x: float, scale_z: float) -> Vector3:
	if tank >= 4:
		return Vector3(
			_body_pad * scale_x + 189.0,
			0.0,
			_body_pad * scale_z + 25.0
		)
	return Vector3(
		TANK_HALF_BASE_GX + _body_pad * scale_x,
		0.0,
		TANK_HALF_BASE_GX + _body_pad * scale_z
	)


func _body_axis_scales() -> Vector2:
	## Orientation shrink of `_28` for length along each axis (`Museum_Fish_BGCheck`).
	var yaw_s: float = absf(sin(yaw))
	var yaw_c: float = absf(cos(yaw))
	var roll_f: float = 0.5 * absf(cos(pitch)) + 0.5
	if _body_pad >= 0.0:
		return Vector2.ONE
	return Vector2(0.3 + 0.7 * yaw_s * roll_f, 0.3 + 0.7 * yaw_c * roll_f)


func _objchk_gx() -> Vector3:
	## Nose point used by BGCheck (`Museum_Fish_objchk_pos_set`).
	var s: float = FieldCatalog.GX_TO_METERS
	var local := Vector3(
		(position.x - _tank_center.x) / s,
		position.y / s + _water_line_gx,
		(position.z - _tank_center.z) / s
	)
	local.x += _ofs_z * sin(yaw)
	local.z += _ofs_z * cos(yaw)
	return local


func _bg_check() -> void:
	## Clamp nose to tank glass, then pull body with it (`Museum_Fish_BGCheck`).
	var scales: Vector2 = _body_axis_scales()
	var half: Vector3 = _swim_half_gx(scales.x, scales.y)
	if tank >= 4:
		## Sea tank +Z is tighter (`_28*f25+14`); -Z uses +25 (+cos lobe simplified).
		half.z = _body_pad * scales.y + 14.0
	var chk: Vector3 = _objchk_gx()
	var s: float = FieldCatalog.GX_TO_METERS
	_wall_flags = 0
	if chk.x > half.x:
		position.x += (half.x - chk.x) * s
		_wall_flags |= 4
	elif chk.x < -half.x:
		position.x += (-half.x - chk.x) * s
		_wall_flags |= 2
	var z_hi: float = half.z if tank < 4 else (_body_pad * scales.y + 14.0)
	var z_lo: float = half.z if tank < 4 else (_body_pad * scales.y + 25.0)
	if tank >= 4:
		## Rebuild with asymmetric sea extents.
		if chk.z > z_hi:
			position.z += (z_hi - chk.z) * s
			_wall_flags |= 16
		elif chk.z < -z_lo:
			position.z += (-z_lo - chk.z) * s
			_wall_flags |= 8
	else:
		if chk.z > half.z:
			position.z += (half.z - chk.z) * s
			_wall_flags |= 16
		elif chk.z < -half.z:
			position.z += (-half.z - chk.z) * s
			_wall_flags |= 8
	## Absolute Y 60–110 GX → relative after water-line snap.
	var y_lo: float = (Y_MIN_GX - _water_line_gx) * s
	var y_hi: float = (Y_MAX_GX - _water_line_gx) * s
	position.y = clampf(position.y, y_lo, y_hi)
	_wall_yaw = _wall_escape_yaw()


func _wall_escape_yaw() -> float:
	## `_62C` from wall flags — angle of the hit face.
	if _wall_flags & 2:
		return deg_to_rad(-90.0)
	if _wall_flags & 4:
		return deg_to_rad(90.0)
	if _wall_flags & 8:
		return deg_to_rad(180.0)
	if _wall_flags & 16:
		return 0.0
	return yaw


func _lookahead_hits_wall() -> bool:
	## `mfish_WallCheck`: probe `_60C.y` by 30 GX, then `mfish_PosWallCheck`.
	var s: float = FieldCatalog.GX_TO_METERS
	var tip := Vector3(
		(position.x - _tank_center.x) / s + sin(yaw) * WALL_LOOKAHEAD_GX,
		0.0,
		(position.z - _tank_center.z) / s + cos(yaw) * WALL_LOOKAHEAD_GX
	)
	var pad: float = _body_pad + 45.0
	var hx: float = pad
	var hz: float = pad
	if tank >= 4:
		hx = _body_pad + 180.0
		## +Z / −Z asymmetric in PosWallCheck.
		if tip.x > hx or tip.x < -hx:
			return true
		if tip.z > _body_pad + 5.0 or tip.z < -(_body_pad + 45.0):
			return true
		return false
	return absf(tip.x) > hx or absf(tip.z) > hz


func _on_activity_expired() -> void:
	if _lookahead_hits_wall() or _wall_flags != 0:
		_start_wall_turn()
	else:
		_start_normal_burst()


func _start_normal_burst() -> void:
	## `mfish_normal_process_init`: new cruise speed + small heading change.
	var burst: float = _speed_min + _rng.randf() * _speed_range
	_target_speed = burst * FieldCatalog.GX_TO_METERS * GAME_FPS
	var turn: float = _rng.randf_range(-_turn_limit, _turn_limit)
	if absf(turn) < deg_to_rad(20.0):
		turn = deg_to_rad(20.0) if turn >= 0.0 else deg_to_rad(-20.0)
	_target_yaw = wrapf(yaw + turn, -PI, PI)


func _start_wall_turn() -> void:
	## `mfish_turn_process_init`: 45°–120° away from the wall face.
	var v: float = deg_to_rad(45.0 + _rng.randf() * 75.0)
	var face: float = _wall_escape_yaw() if _wall_flags != 0 else yaw
	if wrapf(yaw - face, -PI, PI) < 0.0:
		v = -v
	_target_yaw = wrapf(yaw + v, -PI, PI)
	## Prefer leaving along the wall normal ± 112.5° when already pressed to glass.
	if _wall_flags != 0:
		var side: float = 1.0 if wrapf(yaw - face, -PI, PI) > 0.0 else -1.0
		_target_yaw = wrapf(face + side * deg_to_rad(112.5), -PI, PI)
	_target_speed = maxf(_target_speed, (_speed_min + _speed_range * 0.5) * FieldCatalog.GX_TO_METERS * GAME_FPS)
