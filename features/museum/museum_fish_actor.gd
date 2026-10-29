class_name MuseumFishActor
extends RefCounted

## One museum tank fish (`MUSEUM_FISH_PRIVATE_DATA`, `ac_museum_fish_base`). The swim runs in the
## decomp's own units — GX for position and speed, radians for its s16 angles — and every
## per-frame ease takes `ticks` (frames elapsed at `DecompTime.TICK_HZ`), so it plays the same at
## any frame rate. `MuseumFishSchool` drives the tank-wide checks and calls `move` once a frame.
##
## The behaviour is the shared base (`mfish_ani_base_mv`): bursts of swimming (`normal`), turns
## off the glass (`turn`), coasting to a stop (`dummy`), pecking at the glass by the player
## (`peck`) and at the gravel (`ground_peck`), pushed by the tank's current and by the other fish.

enum Process { NORMAL, TURN, DUMMY, PECK, GROUND_PECK }

## `suisou_pos`: tank centres (GX, floor at y 40).
const TANK_POS_GX: Array[Vector3] = [
	Vector3(220.0, 40.0, 220.0), Vector3(420.0, 40.0, 220.0), Vector3(220.0, 40.0, 460.0),
	Vector3(420.0, 40.0, 460.0), Vector3(320.0, 40.0, 20.0),
]
const SEA_TANK := 4
## `mfish_get_flow_vec`: each tank's current strength.
const FLOW_STRENGTH: Array[float] = [0.05, 0.06, 0.2, 0.05, 0.08]
## `mfish_base_FishMove`: the swim height band (GX).
const Y_MIN := 60.0
const Y_MAX := 110.0
## The floor the room snaps to world 0 (`MuseumDisplay.TANK_POS` y).
const FLOOR_GX := 40.0

var fish: FishData = null
var fish_index: int = -1
var tank: int = 0
var school: MuseumFishSchool = null

## `init_data` (`mfish_init_data`).
var render_scale_gx: float = 0.01
var ofs_y: float = 0.0
var body_len: float = 0.0  ## `_08`
var depth: float = 70.0  ## `_0C`
var speed_min: float = 0.0  ## `_10`
var speed_range: float = 0.0  ## `_14`
var drag: float = 0.99  ## `_18`
var straight_chance: float = 0.2  ## `_1C`: the odds a new burst keeps its heading
var mass: float = 0.4  ## `_20`: how hard it shoves and is shoved
var ofs_z: float = 0.0
var pad: float = 0.0  ## `_28`
var active_min: int = 120
var active_range: int = 120
var turn_limit: float = deg_to_rad(70.0)  ## `_30`

## State (`MUSEUM_FISH_PRIVATE_DATA`).
var process: Process = Process.NORMAL
var pos: Vector3 = Vector3.ZERO  ## GX
var bob_y: float = 0.0  ## `_5AC.y`
var objchk: Vector3 = Vector3.ZERO
var vel: Vector3 = Vector3.ZERO  ## `_5D0`
var flow: Vector3 = Vector3.ZERO  ## `_5DC`
var speed: float = 0.0  ## `_5E8`
var target_speed: float = 0.0  ## `_5F0`
var height_ofs: float = 0.0  ## `_5F4`
var pushed: float = 0.0  ## `_5F8`
var room_x_lo: float = 99.0  ## `_5FC` / `_600` / `_604` / `_608`: room to the glass
var room_x_hi: float = 99.0
var room_z_lo: float = 99.0
var room_z_hi: float = 99.0
var pitch: float = 0.0  ## `_60C.x`
var yaw: float = 0.0  ## `_60C.y`
var target_pitch: float = 0.0  ## `_612.x`
var target_yaw: float = 0.0  ## `_612.y`
var turn_rate: float = 0.0  ## `_618.y`
var roll: float = 0.0  ## `_618.z`
var turn_left: float = 0.0  ## `_622`
var activity: float = 0.0  ## `activityFrameCount`, ticks
var activity_saved: float = 0.0
var escape_angle: float = 0.0
var wall_angle: float = 0.0  ## `_62C`
var flags: int = 0  ## `_62E_flags`: 0x2/0x4/0x8/0x10 glass, 0x20 crowded, 0x40/0x80 turn side
var wiggle: float = 0.0  ## `_632`
var hide_angle: float = 0.0
var wiggle_phase: float = 0.0  ## `_636`
var bob_phase: float = 0.0  ## `_638`
var turns_left: float = 0.0  ## `_63E`
var crowd: MuseumFishActor = null  ## `_594`
var nearest: MuseumFishActor = null  ## `_598`
var anim_speed: float = 1.0

var _rng: RandomNumberGenerator


static func create(p_fish: FishData, index: int, rng: RandomNumberGenerator) -> MuseumFishActor:
	if p_fish == null or index < 0:
		return null
	var a := MuseumFishActor.new()
	a.fish = p_fish
	a.fish_index = index
	a.tank = MuseumDisplay.fish_tank(index)
	a._rng = rng if rng != null else RandomNumberGenerator.new()
	var init: Dictionary = MuseumDisplay.fish_init(index)
	a.render_scale_gx = float(init.get("render_scale", 0.01))
	a.ofs_y = float(init.get("ofs_y", 0.0))
	a.body_len = float(init.get("body_len", 0.0))
	a.depth = float(init.get("depth", 70.0))
	a.speed_min = float(init.get("speed", 0.0))
	a.speed_range = float(init.get("speed_range", 0.0))
	a.drag = float(init.get("drag", 0.99))
	a.straight_chance = float(init.get("straight", 0.2))
	a.mass = float(init.get("mass", 0.4))
	a.ofs_z = float(init.get("ofs_z", 0.0))
	a.pad = float(init.get("body_pad", 0.0))
	a.active_min = int(init.get("active_min", 120))
	a.active_range = int(init.get("active_range", 120))
	a.turn_limit = deg_to_rad(float(init.get("turn_deg", 70.0)))
	a._construct()
	return a


## `Museum_Fish_Prv_data_init` + `mfish_onefish_ct` + `mfish_base_ct`.
func _construct() -> void:
	pos = TANK_POS_GX[tank]
	pos.y = depth + _rnd2(10.0)
	pos.x += _rnd2(90.0) if tank != SEA_TANK else _rnd2(150.0)
	pos.z += _rnd2(90.0) if tank != SEA_TANK else _rnd2(10.0)
	_new_activity()
	speed = _rng.randf() * 2.0
	yaw = _rng.randf() * TAU - PI
	target_yaw = yaw
	if fish.id == &"catfish" or fish.id == &"giant_catfish":
		height_ofs = 0.0
	elif fish.id == &"freshwater_goby":
		height_ofs = _rng.randf() * 5.0
	else:
		height_ofs = _rnd2(10.0)
	bob_phase = _rng.randf() * TAU
	turn_left = 0.0
	process = Process.NORMAL
	objchk = pos


## `renderScale` in the same conversion as `FieldCatalog.actor_uniform_scale`.
func render_scale() -> float:
	return render_scale_gx / FieldCatalog.PIPELINE_SCALE * FieldCatalog.GX_TO_METERS


## World position of the fish's origin (metres; the room grid origin is the acre NW).
func world_position() -> Vector3:
	return Vector3(pos.x, pos.y - FLOOR_GX + bob_y, pos.z) * FieldCatalog.GX_TO_METERS


## `mfish_ani_base_mv`, `ticks` frames' worth.
func move(ticks: float) -> void:
	_base_mv(ticks)
	_bg_check()
	_anim_speed(ticks)


# ---- `mfish_base_mv` ------------------------------------------------------------------------

func _base_mv(t: float) -> void:
	if pushed > body_len * 20.0:
		pushed = 0.0
		activity = 0.0
	activity -= t
	if activity <= 0.0:
		_new_activity()
		if school != null and school.peck_check(self):
			activity /= 4.0
			activity_saved = activity
			_peck_init()
		elif _wall_check():
			_turn_init()
		elif _ground_peck_before_check():
			_ground_peck_init()
		else:
			_normal_init()
	elif process == Process.NORMAL:
		var off_glass: bool = (flags & 0x1e) != 0 and absf(_diff(wall_angle, yaw)) < deg_to_rad(30.0)
		var off_crowd: bool = (flags & 0x20) != 0 and absf(_diff(escape_angle + PI, yaw)) < deg_to_rad(30.0)
		if off_glass or off_crowd:
			_new_activity()
			_turn_init()
	bob_y = sin(bob_phase) * 0.2 if tank == 2 else 0.0
	bob_phase += deg_to_rad(10.0) * t
	match process:
		Process.NORMAL:
			_normal(t)
		Process.TURN:
			_turn(t)
		Process.DUMMY:
			_dummy(t)
		Process.PECK:
			_peck(t)
		Process.GROUND_PECK:
			_ground_peck(t)
	if absf(roll) > absf(turn_left):
		speed = _calc2(speed, minf(0.2, speed), 0.2, 0.5, t)
	pitch = _angle(pitch, target_pitch, _ease(0.1), deg_to_rad(5.0), deg_to_rad(0.5), t)
	target_pitch = _angle(target_pitch, 0.0, _ease(0.1), deg_to_rad(2.5), deg_to_rad(0.5), t)
	_fish_move(t)


func _new_activity() -> void:
	activity = float(active_min) + _rng.randf() * float(active_range)
	activity_saved = activity


## `mfish_base_FishMove`.
func _fish_move(t: float) -> void:
	if fish.id == &"piranha" and process != Process.PECK:
		speed *= pow(drag, t)
	else:
		speed = _calc0(speed, 1.0 - drag, 0.025, t)
	vel.x = speed * sin(yaw)
	vel.z = speed * cos(yaw)
	vel.y = _calc(vel.y, maxf(absf(speed * sin(pitch)), 0.1), 0.1, 0.1, 0.005, t)
	pos.y = _calc2(pos.y, height_ofs + depth, 0.1, vel.y, t)
	_move_smooth(t)
	_flow_vec(t)
	pos.x += (vel.x + flow.x) * t
	pos.z += (vel.z + flow.z) * t
	pos.y = clampf(pos.y + flow.y * t, Y_MIN, Y_MAX)


# ---- processes ------------------------------------------------------------------------------

## `mfish_normal_process_init`.
func _normal_init() -> void:
	var ra: float = _rng.randf() * speed_range + speed_min
	var frac: float = ra / maxf(speed_range + speed_min, 1.0)
	if ra > speed:
		target_speed = ra
	height_ofs = _rnd_ex_fx(10.0) * frac
	target_pitch = atan2(height_ofs + depth - pos.y, speed) / 16.0
	vel.y = 0.0
	if _rng.randf() > straight_chance:
		target_yaw += _rnd_ex_fx(turn_limit * 2.0)
		var d: float = _diff(target_yaw, yaw)
		if absf(d) < deg_to_rad(20.0):
			target_yaw += deg_to_rad(20.0) if d > 0.0 else deg_to_rad(-20.0)
		wiggle = deg_to_rad(frac * 30.0 + 20.0)
	else:
		target_yaw += deg_to_rad(15.0) if _diff(target_yaw, yaw) > 0.0 else deg_to_rad(-15.0)
		wiggle = deg_to_rad(40.0 * frac + 30.0)
	wiggle_phase = 0.0 if _diff(yaw, target_yaw) > 0.0 else -PI
	flags &= ~0xc0
	process = Process.NORMAL


## `mfish_normal_process`.
func _normal(t: float) -> void:
	if wiggle > deg_to_rad(20.0):
		var step: float = ((wiggle - deg_to_rad(20.0)) / deg_to_rad(2.0) * 0.04 + 0.1) * 0.5
		speed = _calc(speed, target_speed, _ease(0.2), step, 0.05, t)
	elif activity > activity_saved - 10.0:
		speed = _calc(speed, target_speed, _ease(0.5), 0.75, 0.05, t)
	wiggle = _angle(wiggle, 0.0, _ease2(0.5), deg_to_rad(1.25), deg_to_rad(0.25), t)
	wiggle_phase += deg_to_rad(10.0) * t
	_steer(target_yaw + wiggle * sin(wiggle_phase), _ease2(0.5), deg_to_rad(6.25), deg_to_rad(3.75), t)
	if speed < 0.01 or (tank == 2 and speed < 0.05):
		_dummy_init()
	elif speed > 1.0 and (flags & 0x1e) != 0:
		target_yaw = wall_angle + (deg_to_rad(112.5) if _diff(yaw, wall_angle) > 0.0 else deg_to_rad(-112.5))
		wiggle = 0.0


## `mfish_turn_process_init`.
func _turn_init() -> void:
	var v: float = deg_to_rad(_rng.randf() * 75.0 + 45.0)
	turn_rate = deg_to_rad((speed + 0.5) / (speed_min + speed_range + 0.5) * 7.5 + 7.5)
	if flags & 0xc0:
		v = absf(v) if flags & 0x40 else -absf(v)
	elif flags & 0x1e:
		if _diff(yaw, wall_angle) < 0.0:
			v = -v
	elif flags & 0x20:
		if _diff(escape_angle, yaw) < 0.0:
			v = -v
	flags |= 0x40 if v > 0.0 else 0x80
	target_yaw = wrapf(target_yaw + v, -PI, PI)
	if tank == 2:
		var tmp: float = wrapf(target_yaw + PI / 2.0, -PI, PI)
		if tmp > deg_to_rad(135.0):
			target_yaw = deg_to_rad(-45.0)
		elif tmp > deg_to_rad(-135.0):
			target_yaw = deg_to_rad(-135.0)
	target_speed = speed_min + speed_range * 0.7
	turns_left = _rng.randf() * 3.0 + 1.0 if _rng.randf() < 0.2 else 0.0
	process = Process.TURN


## `mfish_turn_process`.
func _turn(t: float) -> void:
	if absf(turn_left) > deg_to_rad(20.0):
		speed = _calc(speed, target_speed, _ease(0.1), 0.25, 0.05, t)
	target_speed = _calc2(target_speed, maxf(speed_min, 0.0), 0.5, 0.2, t)
	wiggle = _angle(wiggle, 0.0, _ease2(0.5), deg_to_rad(2.5), deg_to_rad(0.25), t)
	_steer(target_yaw + wiggle * sin(wiggle_phase), _ease(0.2), turn_rate / 2.0, deg_to_rad(3.75), t, _ease2(0.4))
	if absf(_diff(yaw, target_yaw)) < deg_to_rad(2.0) and speed < 0.1:
		if turns_left > 0.0:
			if _wall_check():
				_turn_init()
			else:
				_normal_init()
			turns_left -= 1.0
		else:
			_dummy_init()


## `mfish_dummy_process_init` (`mfish_get_hide_camera_angle`): drift side-on to the camera.
func _dummy_init() -> void:
	var v: float = yaw
	if v > 0.0 or (tank == 2 and _rng.randf() < 0.8):
		v = PI / 2.0 + (1.0 if v > PI / 2.0 else -1.0) * deg_to_rad(_rng.randf() * 45.0)
	else:
		v = -PI / 2.0 + (1.0 if v > -PI / 2.0 else -1.0) * deg_to_rad(_rng.randf() * 45.0)
	hide_angle = v
	if tank == 2 and yaw < 0.0 and hide_angle > 0.0:
		target_speed = maxf(speed_min, 1.2)
	process = Process.DUMMY


## `mfish_dummy_process`.
func _dummy(t: float) -> void:
	target_yaw = _angle(target_yaw, hide_angle, _ease2(0.2), deg_to_rad(3.75), deg_to_rad(0.25), t)
	_steer(target_yaw, _ease2(0.5), deg_to_rad(5.0), deg_to_rad(5.0), t)
	if tank == 2:
		if target_yaw < 0.0:
			activity -= t
		else:
			speed = _calc2(speed, target_speed, 0.1, 0.05, t)
			target_speed = _calc0(target_speed, 0.05, 0.1, t)


## `mfish_peck_process_init`: swim at the player by the glass.
func _peck_init() -> void:
	vel.y = 0.0
	var to: Vector3 = school.player_gx() + Vector3(0.0, 40.0, 0.0) - pos if school != null else Vector3.ZERO
	var dist: float = Vector2(to.x, to.z).length()
	var toward: float = atan2(to.x, to.z)
	var top: float = speed_range + speed_min
	if dist < 20.0:
		top *= 0.75
		target_speed = maxf(top, 0.5)
	if top > speed:
		target_speed = top
	var d: float = _diff(toward, yaw)
	if absf(d) < turn_limit:
		target_yaw = toward
	else:
		target_yaw = yaw + (turn_limit if d > 0.0 else -turn_limit)
	if atan2(-to.y, dist) < 0.0:
		height_ofs = clampf(height_ofs + _rng.randf() * 2.5, -10.0, 10.0)
	else:
		height_ofs = clampf(height_ofs - _rng.randf() * 2.5, -10.0, 10.0)
	wiggle = deg_to_rad(top / 8.0 * 30.0 + 20.0)
	wiggle_phase = PI / 2.0 if _rng.randf() < 0.5 else -PI / 2.0
	flags &= ~0xc0
	process = Process.PECK


## `mfish_peck_process`: nose the glass, back off, come again.
func _peck(t: float) -> void:
	var dist: float = 999.0
	if school != null:
		var to: Vector3 = school.player_gx() - pos
		dist = Vector2(to.x, to.z).length()
	if wiggle > deg_to_rad(15.0):
		var step: float = ((wiggle - deg_to_rad(20.0)) / deg_to_rad(2.0) * 0.04 + 0.1) * 0.5
		speed = _calc(speed, target_speed, _ease(0.25), step, 0.05, t)
	elif activity > activity_saved - 16.0:
		speed = _calc(speed, target_speed, _ease(0.1), 0.5, 0.05, t)
	elif dist > 20.0:
		speed = _calc2(speed, maxf(speed, 0.4), 0.25, 0.05, t)
	wiggle = _angle(wiggle, 0.0, _ease2(0.25), deg_to_rad(0.75), deg_to_rad(0.25), t)
	wiggle_phase += deg_to_rad(10.0) * t
	_steer(target_yaw + wiggle * sin(wiggle_phase), _ease2(0.5), deg_to_rad(6.25), deg_to_rad(3.75), t)
	## `mfish_peck_wall_check`: at the glass, facing it, within 60 GX of the player.
	if (flags & 0x1e) != 0 and absf(_diff(yaw, wall_angle)) < deg_to_rad(45.0) and dist < 60.0:
		if _rng.randf() < 0.9:
			speed = -0.3 - _rng.randf() * 0.3
			activity = 10.0
		else:
			speed = -0.5
			activity = (float(active_min) + _rng.randf() * float(active_range)) / 8.0
		activity_saved = activity
		target_speed = 0.0


## `mfish_ground_peck_before_check`: the gravel corner of tank 2 (goldfish).
func _ground_peck_before_check() -> bool:
	if process == Process.GROUND_PECK:
		return turns_left > 0.0
	var p: Vector3 = TANK_POS_GX[tank]
	var v: float = maxf(absf(p.x - pos.x), absf(p.z - pos.z))
	return (
		tank == 2 and pos.x < p.x + 20.0 and pos.z > p.z - 10.0
		and pos.y < body_len * 0.5 + 75.0 - v * 0.15 and _rng.randf() > 0.2
	)


func _ground_height() -> float:
	var p: Vector3 = TANK_POS_GX[tank]
	return body_len * 0.3 + 65.0 - maxf(absf(p.x - pos.x), absf(p.z - pos.z)) * 0.15 - depth


## `mfish_ground_peck_process_init`.
func _ground_peck_init() -> void:
	height_ofs = _ground_height()
	target_pitch = deg_to_rad(60.0)
	activity = (_rnd_ex_f(30.0) + 15.0) * 2.0
	if process != Process.GROUND_PECK:
		turns_left = _rng.randf() * 2.0 + 3.0
	else:
		turns_left -= 1.0
	target_speed = 0.5
	process = Process.GROUND_PECK


## `mfish_ground_peck_process`.
func _ground_peck(t: float) -> void:
	height_ofs = _ground_height()
	flow *= pow(0.1, t)
	if pos.y > height_ofs + depth + 4.0:
		target_pitch = maxf(target_pitch, deg_to_rad(40.0))
		activity += t
		target_speed = _calc2(target_speed, 0.5, 0.6, 0.5, t)
	elif _diff(target_pitch, pitch) > 0.0:
		target_speed = _calc2(target_speed, 0.2, 0.5, 0.4, t)
	elif speed > 0.0:
		speed = -0.2
	else:
		target_speed = _calc0(target_speed, 0.2, 0.1, t)
	target_pitch = maxf(target_pitch, deg_to_rad(15.0))
	speed = _calc(speed, target_speed * cos(pitch), _ease(0.5), 0.25, 0.05, t)
	_dummy(t)


## Turn toward `goal` and let the body roll with what is left of the turn (`_622` → `_618.z`).
func _steer(goal: float, fraction: float, max_step: float, roll_max: float, t: float, roll_fraction: float = -1.0) -> void:
	yaw = _angle(yaw, goal, fraction, max_step, deg_to_rad(0.25), t)
	turn_left = _diff(goal, yaw)
	roll = _angle(roll, turn_left, roll_fraction if roll_fraction >= 0.0 else _ease2(0.5), roll_max, deg_to_rad(0.25), t)


# ---- the tank -------------------------------------------------------------------------------

## `mfish_WallCheck` / `mfish_PosWallCheck`: will 30 GX ahead be past the glass?
func _wall_check() -> bool:
	var p: Vector3 = pos + Vector3(sin(yaw), 0.0, cos(yaw)) * 30.0
	var c: Vector3 = TANK_POS_GX[tank]
	var x_hi: float = pad + (180.0 if tank == SEA_TANK else 45.0)
	var z_hi: float = pad + (5.0 if tank == SEA_TANK else 45.0)
	var z_lo: float = pad + 45.0
	return p.x > c.x + x_hi or p.x < c.x - x_hi or p.z > c.z + z_hi or p.z < c.z - z_lo


## `Museum_Fish_BGCheck`: keep the check point (`objchk_pos`) inside the glass; a long body
## gets less room the more side-on it lies.
func _bg_check() -> void:
	var c: Vector3 = TANK_POS_GX[tank]
	var fx: float = 1.0
	var fz: float = 1.0
	if (process == Process.NORMAL or process == Process.TURN or process == Process.DUMMY) and pad < 0.0:
		var roll_f: float = absf(cos(roll)) * 0.5 + 0.5
		fx = 0.3 + 0.7 * absf(sin(yaw)) * roll_f
		fz = 0.3 + 0.7 * absf(cos(yaw)) * roll_f
	var x_hi: float
	var x_lo: float
	var z_hi: float
	var z_lo: float
	var lean: float = 0.0
	objchk = pos + Vector3(sin(yaw), 0.0, cos(yaw)) * ofs_z
	if tank < SEA_TANK:
		x_hi = 54.0 + pad * fx
		x_lo = x_hi
		z_hi = 54.0 + pad * fz
		z_lo = z_hi
	else:
		var off: float = objchk.x - c.x
		x_hi = pad * fx + 189.0
		x_lo = x_hi
		z_hi = pad * fz + 14.0
		z_lo = pad * fz + 25.0 + cos(deg_to_rad(off)) * 9.0 + 21.0
		lean = deg_to_rad(sin(deg_to_rad(off)) * -10.0)
	flags &= ~0x1e
	wall_angle = 0.0
	if objchk.x > c.x + x_hi:
		pos.x += c.x + x_hi - objchk.x
		flags |= 0x4
	elif objchk.x < c.x - x_lo:
		pos.x += c.x - x_lo - objchk.x
		flags |= 0x2
	if objchk.z > c.z + z_hi:
		pos.z += c.z + z_hi - objchk.z
		flags |= 0x10
	elif objchk.z < c.z - z_lo:
		pos.z += c.z - z_lo - objchk.z
		flags |= 0x8
	objchk = pos + Vector3(sin(yaw), 0.0, cos(yaw)) * ofs_z
	room_x_lo = objchk.x - (c.x - x_lo)
	room_x_hi = c.x + x_hi - objchk.x
	room_z_lo = objchk.z - (c.z - z_lo)
	room_z_hi = c.z + z_hi - objchk.z
	if tank < SEA_TANK and fish.id != &"eel":
		_obj_bg_check(fx, fz)
	if flags & 0x2:
		wall_angle = -PI / 2.0
	elif flags & 0x4:
		wall_angle = PI / 2.0
	if flags & 0x8:
		wall_angle = PI - wall_angle / 2.0 + lean / 2.0 if flags & 0x6 else lean + PI
	elif flags & 0x10:
		wall_angle = wall_angle / 2.0 if flags & 0x6 else 0.0
	wall_angle = wrapf(wall_angle, -PI, PI)


## `Museum_Fish_ObjBGCheck`: the rock and driftwood standing in one corner of each small tank.
func _obj_bg_check(fx: float, fz: float) -> void:
	var c: Vector3 = TANK_POS_GX[tank]
	var top: float
	var x_lo: float
	var x_hi: float
	var z_lo: float
	var z_hi: float
	match tank:
		0:
			top = 85.0
			x_lo = c.x - 20.0
			x_hi = c.x + 1000.0
			z_lo = c.z - 1000.0
			z_hi = c.z - 25.0
		1:
			x_lo = c.x - 5.0
			x_hi = c.x + 1000.0
			z_lo = c.z - 1000.0
			z_hi = c.z - 10.0
			top = 75.0 - cos(deg_to_rad(180.0 * (objchk.x - x_lo) / 70.0)) * 5.0
		2:
			top = 80.0
			x_lo = c.x - 1000.0
			x_hi = c.x - 5.0
			z_lo = c.z - 1000.0
			z_hi = c.z - 20.0
		_:
			top = 75.0
			x_lo = c.x - 20.0
			x_hi = c.x + 1000.0
			z_lo = c.z - 1000.0
			z_hi = c.z - 5.0
	var e: float = top - pos.y
	if e <= 0.0:
		return
	var b: float = x_hi - (pos.x + pad * fx)
	var a: float = x_lo - (pos.x - pad * fx)
	var cz: float = z_hi - (pos.z + pad * fz)
	var d: float = z_lo - (pos.z - pad * fz)
	if not (b > 0.0 and cz > 0.0 and a < 0.0 and d < 0.0):
		return
	var v1: float
	var v2: float
	if b > -a:
		if (flags & 2) == 0:
			flags |= 4
		v1 = a
	else:
		if (flags & 4) == 0:
			flags |= 2
		v1 = b
	if cz > -d:
		if (flags & 8) == 0:
			flags |= 0x10
		v2 = d
	else:
		if (flags & 0x10) == 0:
			flags |= 8
		v2 = cz
	if e < minf(absf(v2), absf(v1)):
		pos.y += e
	elif absf(v2) < absf(v1):
		pos.z += v2
	else:
		pos.x += v1


## `mfish_move_smooth`: slow down and curve along the glass rather than nose into it.
func _move_smooth(t: float) -> void:
	if not (room_z_hi < 20.0 or room_x_hi < 20.0 or room_z_lo < 20.0 or room_x_lo < 20.0):
		return
	var v: float = 0.0
	if room_x_hi < 20.0:
		v = PI / 2.0
	elif room_x_lo < 20.0:
		v = -PI / 2.0
	if room_z_hi < 20.0:
		v = 0.0 if v == 0.0 else v / 2.0
	elif room_z_lo < 20.0:
		v = PI if v == 0.0 else PI - v / 2.0
	var close: bool = room_z_hi < 5.0 or room_z_lo < 5.0 or room_x_hi < 5.0 or room_x_lo < 5.0
	if not ((speed > 0.0 or close) and process != Process.PECK):
		return
	var vv: float = _diff(yaw, v)
	if absf(vv) < PI / 4.0:
		speed = _calc0(speed, 0.1 * cos(vv * 2.0), 0.02, t)
	if (tank == 0 or fish.id == &"arowana") and absf(vv) < PI / 2.0 and absf(turn_left) < deg_to_rad(10.0):
		var side: float = PI / 2.0 if vv > 0.0 else -PI / 2.0
		var lean: float = 12.0 if vv > 0.0 else 5.0
		var max_step: float = deg_to_rad(speed * lean * cos(vv) + 1.5) / 2.0
		if process == Process.DUMMY:
			hide_angle = _angle(hide_angle, v + side, _ease(0.25), max_step, deg_to_rad(0.5), t)
		else:
			target_yaw = _angle(target_yaw, v + side, _ease(0.25), max_step, deg_to_rad(0.5), t)


## `mfish_get_flow_vec`: the tank's circulating current, damped side-on, plus a push away from
## the nearest fish (`_598`) when it is heavier.
func _flow_vec(t: float) -> void:
	var c: Vector3 = TANK_POS_GX[tank]
	var rel: Vector3 = pos - c
	var s: float = sin(deg_to_rad(360.0 * Vector2(rel.x, rel.z).length() / 720.0)) * 0.1 + 0.2
	var p := Vector3(
		s * cos(deg_to_rad(360.0 * rel.x / 60.0)),
		s * 0.5 * cos(deg_to_rad(180.0 * rel.y / 70.0)),
		s * cos(deg_to_rad(360.0 * rel.z / 60.0))
	)
	var swirl: float = atan2(rel.x, rel.z) + (school.flow_angle(tank) if school != null else 0.0)
	var strength: float = 2.0 if tank == 2 else 1.5
	p.x += strength * cos(swirl)
	p.z += strength * sin(swirl)
	p.x *= absf(cos(yaw) * cos(pitch))
	p.z *= absf(sin(yaw) * cos(pitch))
	p.x *= cos(roll)
	p.z *= cos(roll)
	if tank == SEA_TANK:
		p.z += 0.5 * cos(yaw + PI / 2.0)
	elif tank == 2:
		p.x -= absf(cos(yaw)) * 0.02
		if absf(_diff(yaw, deg_to_rad(270.0))) < deg_to_rad(100.0):
			p.x = minf(-1.0, p.x)
	if nearest != null:
		var reach: float = nearest.body_len * (10.0 if tank == SEA_TANK else 5.0) + body_len * 2.0
		var off: Vector3 = pos - nearest.pos
		var dist: float = off.length()
		if dist < reach and dist > 0.0001:
			var k: float = (dist - reach) * (dist - reach) / (reach * reach) * nearest.mass
			p += off * (k / dist)
	if tank == 2 and p.x < 0.0:
		p.x *= 1.1
	p *= FLOW_STRENGTH[tank]
	flow.x = _calc2(flow.x, p.x, 0.5, 0.1, t)
	flow.y = _calc2(flow.y, p.y, 0.5, 0.1, t)
	flow.z = _calc2(flow.z, p.z, 0.5, 0.1, t)


## `mfish_ani_base_mv`: the swim clip speeds with the stroke.
func _anim_speed(t: float) -> void:
	var span: float = maxf(speed_min + speed_range, 0.01)
	if tank == 2:
		anim_speed = speed * 3.0 / span + 1.0
	elif fish.id in [&"bitterling", &"brook_trout", &"crucian_carp"]:
		if target_speed - 0.1 > speed and process == Process.NORMAL and activity > activity_saved - 10.0:
			anim_speed = (target_speed - speed) * 3.0 / span + 1.5
		else:
			anim_speed = _calc2(anim_speed, 2.0 * speed + 0.5, 0.2, 0.1, t)
	elif activity > activity_saved - 10.0 and target_speed > 0.0:
		anim_speed = speed * 4.0 / span + 1.25
	else:
		anim_speed = _calc2(anim_speed, 2.0 * speed + 0.5, 0.2, 0.1, t)


# ---- the decomp's eases, over `t` frames ----------------------------------------------------

## `CALC_EASE` / `CALC_EASE2`.
static func _ease(x: float) -> float:
	return 1.0 - sqrt(1.0 - x)


static func _ease2(x: float) -> float:
	return _ease(_ease(x))


static func _diff(a: float, b: float) -> float:
	return wrapf(a - b, -PI, PI)


static func _angle(value: float, target: float, fraction: float, max_step: float, min_step: float, t: float) -> float:
	return wrapf(MathUtil.short_angle2(value, target, fraction, max_step, min_step, t), -PI, PI)


## `add_calc`.
static func _calc(value: float, target: float, fraction: float, max_step: float, min_step: float, t: float) -> float:
	return BugBehavior.add_calc(value, target, fraction, max_step, min_step, t)


## `add_calc2`: no minimum step, and it may overshoot nothing (step capped by the gap).
static func _calc2(value: float, target: float, fraction: float, max_step: float, t: float) -> float:
	var f: float = 1.0 - pow(1.0 - clampf(fraction, 0.0, 1.0), t)
	return value + clampf(f * (target - value), -max_step * t, max_step * t)


## `add_calc0`.
static func _calc0(value: float, fraction: float, max_step: float, t: float) -> float:
	var f: float = 1.0 - pow(1.0 - clampf(fraction, 0.0, 1.0), t)
	return value - clampf(value * f, -max_step * t, max_step * t)


## `RANDOM2_F`: ±`v`/2.
func _rnd2(v: float) -> float:
	return (_rng.randf() - 0.5) * v


## `Rnd_EX_f` / `Rnd_EX_fx`: a centre-weighted random.
func _rnd_ex_core() -> float:
	var r1: float = (_rng.randf() - 0.5) * 2.0
	var r2: float = _rng.randf()
	if r2 > r1 * r1:
		r1 = sqrt(r2) if r1 > 0.0 else -sqrt(r2)
	return r1


func _rnd_ex_f(v: float) -> float:
	return v * (1.0 + _rnd_ex_core()) * 0.5


func _rnd_ex_fx(v: float) -> float:
	return v * _rnd_ex_core() / 2.0
