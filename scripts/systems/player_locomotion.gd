class_name PlayerLocomotion
extends RefCounted

## Player ground movement — `m_player_main_{wait,walk,run,dash,turn_dash}` in meters, one
## cell = 40 GX = 2 m.
##
## The decomp's play frame is 1/60 s: `Actor_position_move` adds `0.5 · speed` per frame
## ("30fps -> 60fps"), so `speed` (4.875 walk / 7.5 dash) is GX per 1/30 s (`DecompTime.FRAME_HZ`)
## while every per-frame step (accelerate 0.609, brake 0.326, `add_calc_short_angle2`
## turn) runs once per tick (`DecompTime.TICK_HZ`). `tick` therefore steps whole ticks.
##
## Gait is a mode machine, not a speed band: the clip rate `0.6·√(speed·norm / 7.5)`
## (floored at 0.22, cut by wall contact) decides walk ↔ run (3.525) ↔ dash (4.875) via
## `rate² / 0.048`, WAIT is entered only once speed *and* stick are both zero, and a dash
## turned ≥ 100° off the stick skids (`TURN_DASH`).

enum Gait { WAIT, WALK, RUN, DASH, TURN_DASH, TUMBLE, TUMBLE_GETUP }

const TILE_UNITS := 40.0
const TILE_METERS := 2.0
const UNIT_METERS := TILE_METERS / TILE_UNITS

const ORIG_WALK := 4.875
const ORIG_RUN := 7.5
const ORIG_WALK_RUN := 3.525
const ORIG_ACCEL := 0.60899997
const ORIG_DECEL := 0.32625002
## `Player_actor_Movement_Wait` / `_Turn_dash` brakes.
const ORIG_WAIT_BRAKE := 0.23925
const ORIG_TURN_DASH_BRAKE := 0.261
## `Player_actor_Movement_Tumble` (tumble and get-up).
const ORIG_TUMBLE_BRAKE := 0.175
## `request_proc_index_fromDash_common`: bad-luck trip, 1 in 600 frames at ≥ 75 % dash.
const TUMBLE_CHANCE := 600
const TUMBLE_SPEED_FRAC := 0.75
## `Player_actor_Check_FlatPlace` probes (lateral, forward) in GX around the actor.
const FLAT_PROBES: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(20.0, 0.0), Vector2(-20.0, 0.0),
	Vector2(0.0, 28.284271), Vector2(20.0, 28.284271), Vector2(-20.0, 28.284271),
	Vector2(0.0, 56.568542), Vector2(20.0, 56.568542), Vector2(-20.0, 56.568542),
	Vector2(0.0, 84.85281), Vector2(20.0, 84.85281), Vector2(-20.0, 84.85281),
]

const WALK_SPEED := ORIG_WALK * DecompTime.FRAME_HZ * UNIT_METERS
const RUN_SPEED := ORIG_RUN * DecompTime.FRAME_HZ * UNIT_METERS
const WALK_RUN_SPEED := ORIG_WALK_RUN * DecompTime.FRAME_HZ * UNIT_METERS
const ACCEL := ORIG_ACCEL * DecompTime.FRAME_HZ * UNIT_METERS * DecompTime.TICK_HZ
const DECEL := ORIG_DECEL * DecompTime.FRAME_HZ * UNIT_METERS * DecompTime.TICK_HZ

## `mCon_calc`: `STICK_MIN / STICK_MAX` — below this the stick reads zero; above it
## `move_pR = t / STICK_MAX` (not shifted by the dead zone), so the first registered
## nudge is already ~16 % speed.
const STICK_MIN := 9.899495
const STICK_MAX := 61.0
const STICK_DEADZONE := 0.05
const IDLE_SPEED := 0.08
## s16 2500 / 65536 of a turn, per tick.
const TURN_MAX_RAD := 2500.0 * TAU / 65536.0
const TURN_MIN_RAD := 50.0 * TAU / 65536.0
## `Player_actor_Get_DiffWorldAngleToControllerAngle(actor) >= 18204` (100°).
const TURN_DASH_ANGLE := 18204.0 * TAU / 65536.0
## `Player_actor_CulcAnimation_Walk`: clip rate floor, and the clip rate at 30 fps.
const ANIM_RATE_MIN := 0.22
## `0.59999996f` — keeps a full-stick walk (4.875) just under the dash gauge.
const ANIM_RATE_COEF := 0.59999996
const ANIM_BASE_RATE := 0.5
## `Player_actor_set_lean_angle`: 20° cap, `add_calc_short_angle2(…, 1−√½, 10°, 0)`.
const LEAN_MAX := deg_to_rad(20.0)
const LEAN_STEP_MAX := deg_to_rad(10.0)
const HALF_FRACTION := 0.29289321881

## Decomp `actor->speed` (GX / 1/30 s).
var speed_gx: float = 0.0
## Drawn body yaw (`shape_info.rotation.y`) — differs from `facing` only while skidding.
var body_yaw: float = 0.0
## Movement direction (`world.angle.y`). Setting it also turns the body (every mode
## but the skid writes both, as the original does).
var facing: float:
	get:
		return _facing
	set(value):
		_facing = value
		body_yaw = value
## Forward pitch (`shape_info.rotation.x`), radians; positive leans forward.
var lean: float = 0.0
## Keyframe rate (`frame_control.speed`, keyframes per 1/60 s; 0.5 = the clip's 30 fps).
var anim_rate: float = ANIM_BASE_RATE
var mode: Gait = Gait.WAIT
## Set on the frame a mode starts; the scene reads + clears it to (re)start clips.
var mode_changed: bool = false
## Previous mode, for clip phase carry-over (walk ↔ run ↔ dash keep the frame).
var previous_mode: Gait = Gait.WAIT
## `hit_wall` result from the last frame: 1 = free, else achieved/intended motion.
var wall_ratio: float = 1.0
## Optional `func(pos: Vector3) -> float` ground height (meters) for slope normalize.
var ground_sampler: Callable = Callable()
## Optional `func(pos: Vector3) -> bool`: is the unit under `pos` flat (vertical normal).
var flat_sampler: Callable = Callable()
## `now_private->destiny.type == mPr_DESTINY_BAD_LUCK` (and not the title demo).
var bad_luck: bool = false
## Current keyframe of the playing clip (30 fps frames) and whether it has ended; the
## scene feeds these so tumble → get-up → wait follow the clip like `CulcAnimation`.
var clip_frame: float = 0.0
var clip_done: bool = false
## `move_pX != 0 || move_pY != 0` — the per-axis test wait ↔ walk uses (not the radius).
var axes_active: bool = true
## Override for tests: returns true to trip this frame.
var tumble_roll: Callable = Callable()
var position: Vector3 = Vector3.ZERO

var _facing: float = 0.0
var _steps := FrameStepper.new(DecompTime.TICK_HZ, 8.0)
var _turn_target: float = 0.0

var planar_speed: float:
	get:
		return speed_gx * DecompTime.FRAME_HZ * UNIT_METERS
	set(value):
		speed_gx = value / (DecompTime.FRAME_HZ * UNIT_METERS)


func reset(yaw: float = 0.0) -> void:
	speed_gx = 0.0
	facing = yaw
	body_yaw = yaw
	lean = 0.0
	anim_rate = ANIM_BASE_RATE
	wall_ratio = 1.0
	_steps.reset()
	_set_mode(Gait.WAIT)
	mode_changed = false


func gait() -> Gait:
	return mode


func forward() -> Vector3:
	return Vector3(sin(facing), 0.0, cos(facing))


func facing_point(origin: Vector3, distance: float) -> Vector3:
	return origin + Vector3(sin(body_yaw), 0.0, cos(body_yaw)) * distance


## `mCon_calc` per-axis percent (`move_pX` / `move_pY`): each axis is zeroed inside its own
## dead zone, so a small diagonal can register radially yet read 0 on both axes.
static func axis_percent(raw_axis: float) -> float:
	var t: float = clampf(absf(raw_axis), 0.0, 1.0) * STICK_MAX
	if t <= STICK_MIN:
		return 0.0
	return signf(raw_axis) * t / STICK_MAX


## `mCon_calc` on a normalised stick vector (full deflection = `STICK_MAX`): returns the
## original's `move_pR` for that radius.
static func stick_percent(raw_len: float) -> float:
	var t: float = clampf(raw_len, 0.0, 1.0) * STICK_MAX
	if t <= STICK_MIN:
		return 0.0
	return t / STICK_MAX


## Clip speed multiplier for an `AnimationPlayer` authored at the clip's native 30 fps.
func anim_speed_scale() -> float:
	return anim_rate / ANIM_BASE_RATE


## Step whole 60 Hz frames. `wish_dir` is the camera-relative stick direction, `stick`
## the `move_pR` percent (0..1). Returns this frame's planar velocity (m/s).
func tick(delta: float, wish_dir: Vector3, stick: float, dashing: bool, locked: bool) -> Vector3:
	if locked:
		stick = 0.0
		wish_dir = Vector3.ZERO
	stick = clampf(stick, 0.0, 1.0)
	var has_dir: bool = stick > 0.0 and wish_dir.length_squared() > 0.0001
	var wish_yaw: float = atan2(wish_dir.x, wish_dir.z) if has_dir else facing
	_steps.add(delta)
	while _steps.next():
		_frame(wish_yaw, stick if has_dir else 0.0, dashing)
	return forward() * planar_speed


func _frame(wish_yaw: float, stick: float, dashing: bool) -> void:
	match mode:
		Gait.WAIT:
			_frame_wait(stick)
		Gait.WALK, Gait.RUN, Gait.DASH:
			_frame_move(wish_yaw, stick, dashing)
		Gait.TURN_DASH:
			_frame_turn_dash()
		Gait.TUMBLE:
			_frame_tumble()
		Gait.TUMBLE_GETUP:
			_frame_tumble_getup()


func _frame_wait(stick: float) -> void:
	## `Player_actor_Movement_Wait`: brake 0.23925, no steering.
	speed_gx = maxf(speed_gx - ORIG_WAIT_BRAKE, 0.0)
	_advance(speed_gx)
	anim_rate = ANIM_BASE_RATE
	lean = MLib.short_angle2(lean, 0.0, HALF_FRACTION, LEAN_STEP_MAX)
	## `request_proc_index_fromWait`: `move_pX || move_pY` → WALK (starts at frame 1).
	if stick > 0.0 and axes_active:
		_set_mode(Gait.WALK)


func _frame_move(wish_yaw: float, stick: float, dashing: bool) -> void:
	## `Player_actor_Movement_Walk` (shared by run / dash).
	var turn_mod: float = turn_mod(stick)
	facing = MLib.short_angle2(
		facing, wish_yaw, 1.0 - sqrt(1.0 - turn_mod), TURN_MAX_RAD, TURN_MIN_RAD
	)
	body_yaw = facing
	var over_norm: float = _over_speed_normalize(position)
	var target: float = ((ORIG_RUN if dashing else ORIG_WALK) * stick) / over_norm
	var aligned: float = cos(absf(angle_difference(facing, wish_yaw)))
	target = 0.0 if aligned <= 0.0 else target * aligned
	if speed_gx < target:
		speed_gx = minf(speed_gx + ORIG_ACCEL, target)
	elif speed_gx > target:
		speed_gx = maxf(speed_gx - ORIG_DECEL, target)
	if over_norm == 1.0:
		var ahead: Vector3 = position + forward() * (0.5 * speed_gx * UNIT_METERS)
		var ahead_norm: float = _over_speed_normalize(ahead)
		if ahead_norm != 1.0:
			over_norm = ahead_norm
			speed_gx /= ahead_norm
	_advance(speed_gx)
	## `Player_actor_CulcAnimation_Walk`.
	var rate: float = ANIM_RATE_COEF * sqrt(maxf(speed_gx * over_norm, 0.0) / ORIG_RUN)
	if wall_ratio < 1.0:
		rate *= sqrt(clampf(wall_ratio, 0.0, 1.0))
	anim_rate = maxf(rate, ANIM_RATE_MIN)
	## `Player_actor_set_lean_angle`.
	var e: float = (anim_rate * anim_rate) / 0.36
	var lean_target: float = minf(pow(e * e, 3.0) * LEAN_MAX, LEAN_MAX)
	lean = MLib.short_angle2(lean, lean_target, HALF_FRACTION, LEAN_STEP_MAX)
	_move_transitions(wish_yaw, stick)


func _move_transitions(wish_yaw: float, stick: float) -> void:
	var gauge: float = (anim_rate * anim_rate) / 0.048
	match mode:
		Gait.WALK:
			if gauge >= ORIG_WALK_RUN:
				_set_mode(Gait.RUN)
			if speed_gx == 0.0 and (stick == 0.0 or not axes_active):
				_set_mode(Gait.WAIT)
		Gait.RUN:
			if gauge < ORIG_WALK_RUN:
				_set_mode(Gait.WALK)
			if gauge >= ORIG_WALK:
				_set_mode(Gait.DASH)
		Gait.DASH:
			## Priority 6 trip > priority 3 skid > priority 1 run.
			if _should_tumble():
				_set_mode(Gait.TUMBLE)
			elif stick > 0.0 and absf(angle_difference(facing, wish_yaw)) >= TURN_DASH_ANGLE:
				_turn_target = wish_yaw
				_set_mode(Gait.TURN_DASH)
			elif gauge < ORIG_WALK:
				_set_mode(Gait.RUN)


func _frame_turn_dash() -> void:
	## `Player_actor_main_Turn_dash`: brake 0.261 along the old heading while the body
	## spins (always the positive way, `add_calc_short_angle3`) to the stick angle.
	speed_gx = maxf(speed_gx - ORIG_TURN_DASH_BRAKE, 0.0)
	_advance(speed_gx)
	body_yaw = MLib.short_angle3(body_yaw, _turn_target, HALF_FRACTION, TURN_MAX_RAD, TURN_MIN_RAD)
	anim_rate = ANIM_BASE_RATE
	lean = MLib.short_angle2(lean, 0.0, HALF_FRACTION, LEAN_STEP_MAX)
	if speed_gx == 0.0 and is_equal_approx(wrapf(body_yaw - _turn_target, -PI, PI), 0.0):
		## Settle: `world.angle.y = shape_info.rotation.y`.
		facing = body_yaw
		_set_mode(Gait.WAIT)


func _should_tumble() -> bool:
	if not bad_luck or speed_gx / ORIG_RUN < TUMBLE_SPEED_FRAC:
		return false
	if not _flat_ahead():
		return false
	if tumble_roll.is_valid():
		return bool(tumble_roll.call())
	return randi() % TUMBLE_CHANCE == 0


func _flat_ahead() -> bool:
	if not flat_sampler.is_valid():
		return true
	var fwd := Vector3(sin(body_yaw), 0.0, cos(body_yaw))
	var side := Vector3(cos(body_yaw), 0.0, -sin(body_yaw))
	for probe: Vector2 in FLAT_PROBES:
		var at: Vector3 = position + (side * probe.x + fwd * probe.y) * UNIT_METERS
		if not bool(flat_sampler.call(at)):
			return false
	return true


func _frame_tumble() -> void:
	## `Player_actor_main_Tumble`: brake 0.175; lean eases out by frame 17; once stopped
	## and the fall clip has ended → get-up.
	speed_gx = maxf(speed_gx - ORIG_TUMBLE_BRAKE, 0.0)
	_advance(speed_gx)
	anim_rate = ANIM_BASE_RATE
	var left: float = 17.0 - clip_frame
	if left > 0.0:
		lean = MLib.short_angle2(lean, 0.0, 1.0 - sqrt(1.0 - 1.0 / maxf(left, 1.0)), deg_to_rad(10.0))
	else:
		lean = 0.0
	if speed_gx == 0.0 and clip_done:
		_set_mode(Gait.TUMBLE_GETUP)


func _frame_tumble_getup() -> void:
	speed_gx = maxf(speed_gx - ORIG_TUMBLE_BRAKE, 0.0)
	_advance(speed_gx)
	anim_rate = ANIM_BASE_RATE
	if clip_done:
		_set_mode(Gait.WAIT)


func _advance(spd_gx: float) -> void:
	position += forward() * (0.5 * spd_gx * UNIT_METERS)


## `Player_actor_Culc_over_speed_normalize_NoneZero`: climbing a slope divides the target
## speed by `|move_vec|²` (1 + rise²); flat ground and descents return 1.
func _over_speed_normalize(at: Vector3) -> float:
	if not ground_sampler.is_valid():
		return 1.0
	var d := 0.25
	var dir := forward()
	var y0: float = ground_sampler.call(at - dir * d)
	var y1: float = ground_sampler.call(at + dir * d)
	if not is_finite(y0) or not is_finite(y1):
		return 1.0
	if y0 <= FieldCollision.NO_FLOOR + 1.0 or y1 <= FieldCollision.NO_FLOOR + 1.0:
		return 1.0
	var rise: float = (y1 - y0) / (2.0 * d)
	if rise <= 0.0001:
		return 1.0
	return 1.0 + rise * rise


func _set_mode(next: Gait) -> void:
	if next == mode:
		return
	previous_mode = mode
	mode = next
	mode_changed = true
	clip_done = false
	clip_frame = 0.0


static func turn_mod(stick: float) -> float:
	if stick >= 1.0:
		return 0.5
	if stick <= STICK_DEADZONE:
		return 0.01
	return 0.01 + 0.5157895 * (stick - STICK_DEADZONE)


static func step_facing(current: float, target: float, stick: float, delta: float) -> float:
	## One `add_calc_short_angle2` per elapsed decomp frame (kept for callers that steer
	## outside `tick`, e.g. the intro station follow).
	var frames: int = maxi(int(round(DecompTime.sec_to_ticks(delta))), 1)
	var fraction: float = 1.0 - sqrt(1.0 - turn_mod(stick))
	for _i: int in frames:
		current = MLib.short_angle2(current, target, fraction, TURN_MAX_RAD, TURN_MIN_RAD)
	return current


static func move_toward_speed(current: float, target: float, delta: float) -> float:
	if current < target:
		return minf(target, current + ACCEL * delta)
	if current > target:
		return maxf(target, current - DECEL * delta)
	return target
