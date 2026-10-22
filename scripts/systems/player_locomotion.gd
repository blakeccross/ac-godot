class_name PlayerLocomotion
extends RefCounted

## Player ground movement — `m_player_main_{wait,walk,run,dash,turn_dash}` in meters, one
## cell = 40 GX = 2 m.
##
## Speeds are metres a second and steps run on `delta`. The decomp's `speed` (4.875 walk /
## 7.5 dash) is GX per 1/30 s and `Actor_position_move` adds half of it each 1/60 s tick;
## its per-tick steps (accelerate 0.609, brake 0.326, the `add_calc_short_angle2` turn) are
## converted here to m/s² and to turns scaled by the ticks a step covers.
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

## One decomp speed unit (GX per 1/30 s) in m/s, and one per-tick speed change in m/s².
const GX_SPEED := DecompTime.FRAME_HZ * UNIT_METERS
const GX_ACCEL := GX_SPEED * DecompTime.TICK_HZ

const WALK_SPEED := ORIG_WALK * GX_SPEED
const RUN_SPEED := ORIG_RUN * GX_SPEED
const ACCEL := ORIG_ACCEL * GX_ACCEL
const DECEL := ORIG_DECEL * GX_ACCEL
const WAIT_BRAKE := ORIG_WAIT_BRAKE * GX_ACCEL
const TURN_DASH_BRAKE := ORIG_TURN_DASH_BRAKE * GX_ACCEL
const TUMBLE_BRAKE := ORIG_TUMBLE_BRAKE * GX_ACCEL
## 1 in 600 a tick, as a rate a second.
static var TUMBLE_RATE: float = Motion.rate_from_chance(1.0 / TUMBLE_CHANCE)
## The slope probe looks one tick of travel ahead.
const LOOKAHEAD_SEC := DecompTime.TICK_SEC

## `mCon_calc`: `STICK_MIN / STICK_MAX` — below this the stick reads zero; above it
## `move_pR = t / STICK_MAX` (not shifted by the dead zone), so the first registered
## nudge is already ~16 % speed.
const STICK_MIN := 9.899495
const STICK_MAX := 61.0
const STICK_DEADZONE := 0.05
const IDLE_SPEED := 0.08
## s16 2500 / 50 per tick (`add_calc_short_angle2` limits).
const TURN_MAX_RAD := 2500.0 * MathUtil.S16
const TURN_MIN_RAD := 50.0 * MathUtil.S16
## `Player_actor_Get_DiffWorldAngleToControllerAngle(actor) >= 18204` (100°).
const TURN_DASH_ANGLE := 18204.0 * MathUtil.S16
## `Player_actor_CulcAnimation_Walk`: clip rate floor, and the clip rate at 30 fps.
const ANIM_RATE_MIN := 0.22
## `0.59999996f` — keeps a full-stick walk (4.875) just under the dash gauge.
const ANIM_RATE_COEF := 0.59999996
const ANIM_BASE_RATE := 0.5
## `Player_actor_set_lean_angle`: 20° cap, `add_calc_short_angle2(…, 1−√½, 10°, 0)`.
const LEAN_MAX := deg_to_rad(20.0)
const LEAN_STEP_MAX := deg_to_rad(10.0)

## Ground speed along `facing`, m/s.
var speed: float = 0.0
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
## `anim_speed_scale` turns it into an `AnimationPlayer` speed.
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
## Override for tests: returns true to trip this step.
var tumble_roll: Callable = Callable()
var position: Vector3 = Vector3.ZERO

var _facing: float = 0.0
var _turn_target: float = 0.0
var _rng := RandomNumberGenerator.new()

var planar_speed: float:
	get:
		return speed
	set(value):
		speed = value

## `speed` in the decomp's GX per 1/30 s, for the tool states still written in those units.
var speed_gx: float:
	get:
		return speed / GX_SPEED
	set(value):
		speed = value * GX_SPEED


func reset(yaw: float = 0.0) -> void:
	speed = 0.0
	facing = yaw
	body_yaw = yaw
	lean = 0.0
	anim_rate = ANIM_BASE_RATE
	wall_ratio = 1.0
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


## Steps `delta` seconds. `wish_dir` is the camera-relative stick direction, `stick` the
## `move_pR` percent (0..1). Returns the planar velocity (m/s) at the end of the step.
func tick(delta: float, wish_dir: Vector3, stick: float, dashing: bool, locked: bool) -> Vector3:
	if delta <= 0.0:
		return forward() * speed
	if locked:
		stick = 0.0
		wish_dir = Vector3.ZERO
	stick = clampf(stick, 0.0, 1.0)
	var has_dir: bool = stick > 0.0 and wish_dir.length_squared() > 0.0001
	var wish_yaw: float = atan2(wish_dir.x, wish_dir.z) if has_dir else facing
	stick = stick if has_dir else 0.0
	match mode:
		Gait.WAIT:
			_step_wait(stick, delta)
			## The decomp's start takes one standing tick; the rest of the step walks, so
			## a long step doesn't stand still for all of it.
			if mode == Gait.WALK and delta > DecompTime.TICK_SEC:
				_step_move(wish_yaw, stick, dashing, delta - DecompTime.TICK_SEC)
		Gait.WALK, Gait.RUN, Gait.DASH:
			_step_move(wish_yaw, stick, dashing, delta)
		Gait.TURN_DASH:
			_step_turn_dash(delta)
		Gait.TUMBLE:
			_step_tumble(delta)
		Gait.TUMBLE_GETUP:
			_step_tumble_getup(delta)
	return forward() * speed


func _step_wait(stick: float, delta: float) -> void:
	## `Player_actor_Movement_Wait`: brake 0.23925 a tick, no steering.
	_brake(WAIT_BRAKE, delta)
	anim_rate = ANIM_BASE_RATE
	_ease_lean(0.0, delta)
	## `request_proc_index_fromWait`: `move_pX || move_pY` → WALK (starts at frame 1).
	if stick > 0.0 and axes_active:
		_set_mode(Gait.WALK)


func _step_move(wish_yaw: float, stick: float, dashing: bool, delta: float) -> void:
	## `Player_actor_Movement_Walk` (shared by run / dash).
	var turn_mod: float = turn_mod(stick)
	var start_yaw: float = facing
	facing = MathUtil.short_angle2(
		facing, wish_yaw, 1.0 - sqrt(1.0 - turn_mod), TURN_MAX_RAD, TURN_MIN_RAD, _ticks(delta)
	)
	body_yaw = facing
	## Halfway through this step's turn: the heading it travels along and the one that
	## sets how much the turn slows it.
	var mid_yaw: float = start_yaw + angle_difference(start_yaw, facing) * 0.5
	var over_norm: float = _over_speed_normalize(position)
	var target: float = ((RUN_SPEED if dashing else WALK_SPEED) * stick) / over_norm
	var aligned: float = cos(absf(angle_difference(mid_yaw, wish_yaw)))
	target = 0.0 if aligned <= 0.0 else target * aligned
	var start_speed: float = speed
	speed = move_toward_speed(speed, target, delta)
	var distance: float = _ramp_distance(start_speed, target, delta)
	if over_norm == 1.0:
		var ahead: Vector3 = position + forward() * (speed * LOOKAHEAD_SEC)
		var ahead_norm: float = _over_speed_normalize(ahead)
		if ahead_norm != 1.0:
			over_norm = ahead_norm
			speed /= ahead_norm
			distance /= ahead_norm
	position += Vector3(sin(mid_yaw), 0.0, cos(mid_yaw)) * distance
	## `Player_actor_CulcAnimation_Walk`.
	var rate: float = ANIM_RATE_COEF * sqrt(maxf(speed * over_norm, 0.0) / RUN_SPEED)
	if wall_ratio < 1.0:
		rate *= sqrt(clampf(wall_ratio, 0.0, 1.0))
	anim_rate = maxf(rate, ANIM_RATE_MIN)
	## `Player_actor_set_lean_angle`.
	var e: float = (anim_rate * anim_rate) / 0.36
	_ease_lean(minf(pow(e * e, 3.0) * LEAN_MAX, LEAN_MAX), delta)
	_move_transitions(wish_yaw, stick, delta)


func _move_transitions(wish_yaw: float, stick: float, delta: float) -> void:
	## The gauge is in the decomp's speed units: `rate² / 0.048` reads back GX per 1/30 s.
	var gauge: float = (anim_rate * anim_rate) / 0.048
	match mode:
		Gait.WALK:
			if gauge >= ORIG_WALK_RUN:
				_set_mode(Gait.RUN)
			if speed == 0.0 and (stick == 0.0 or not axes_active):
				_set_mode(Gait.WAIT)
		Gait.RUN:
			if gauge < ORIG_WALK_RUN:
				_set_mode(Gait.WALK)
			if gauge >= ORIG_WALK:
				_set_mode(Gait.DASH)
		Gait.DASH:
			## Priority 6 trip > priority 3 skid > priority 1 run.
			if _should_tumble(delta):
				_set_mode(Gait.TUMBLE)
			elif stick > 0.0 and absf(angle_difference(facing, wish_yaw)) >= TURN_DASH_ANGLE:
				_turn_target = wish_yaw
				_set_mode(Gait.TURN_DASH)
			elif gauge < ORIG_WALK:
				_set_mode(Gait.RUN)


func _step_turn_dash(delta: float) -> void:
	## `Player_actor_main_Turn_dash`: brake 0.261 a tick along the old heading while the body
	## spins (always the positive way, `add_calc_short_angle3`) to the stick angle.
	_brake(TURN_DASH_BRAKE, delta)
	body_yaw = MathUtil.short_angle3(
		body_yaw, _turn_target, MathUtil.HALF_FRACTION, TURN_MAX_RAD, TURN_MIN_RAD, _ticks(delta)
	)
	anim_rate = ANIM_BASE_RATE
	_ease_lean(0.0, delta)
	if speed == 0.0 and is_equal_approx(wrapf(body_yaw - _turn_target, -PI, PI), 0.0):
		## Settle: `world.angle.y = shape_info.rotation.y`.
		facing = body_yaw
		_set_mode(Gait.WAIT)


func _should_tumble(delta: float) -> bool:
	if not bad_luck or speed / RUN_SPEED < TUMBLE_SPEED_FRAC:
		return false
	if not _flat_ahead():
		return false
	if tumble_roll.is_valid():
		return bool(tumble_roll.call())
	return Motion.happens(TUMBLE_RATE, delta, _rng)


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


func _step_tumble(delta: float) -> void:
	## `Player_actor_main_Tumble`: brake 0.175 a tick; lean eases out by keyframe 17; once
	## stopped and the fall clip has ended → get-up.
	_brake(TUMBLE_BRAKE, delta)
	anim_rate = ANIM_BASE_RATE
	var left: float = 17.0 - clip_frame
	if left > 0.0:
		lean = MathUtil.short_angle2(
			lean, 0.0, 1.0 - sqrt(1.0 - 1.0 / maxf(left, 1.0)), deg_to_rad(10.0), 0.0, _ticks(delta)
		)
	else:
		lean = 0.0
	if speed == 0.0 and clip_done:
		_set_mode(Gait.TUMBLE_GETUP)


func _step_tumble_getup(delta: float) -> void:
	_brake(TUMBLE_BRAKE, delta)
	anim_rate = ANIM_BASE_RATE
	if clip_done:
		_set_mode(Gait.WAIT)


## Slows by `rate` (m/s²) to a stop, moving along `facing` the exact distance covered.
func _brake(rate: float, delta: float) -> void:
	var start: float = speed
	var t: float = minf(delta, start / rate) if rate > 0.0 else delta
	speed = maxf(start - rate * delta, 0.0)
	position += forward() * (start * t - 0.5 * rate * t * t)


## Distance covered over `delta` while speed ramps from `start` toward `target` at ACCEL /
## DECEL and then holds there.
static func _ramp_distance(start: float, target: float, delta: float) -> float:
	var rate: float = ACCEL if target > start else DECEL
	var reach: float = absf(target - start) / rate
	if reach >= delta:
		var end: float = move_toward_speed(start, target, delta)
		return 0.5 * (start + end) * delta
	return 0.5 * (start + target) * reach + target * (delta - reach)


## `Player_actor_set_lean_angle`'s `add_calc_short_angle2(…, 1−√½, 10°, 0)` over `delta`.
func _ease_lean(target: float, delta: float) -> void:
	lean = MathUtil.short_angle2(lean, target, MathUtil.HALF_FRACTION, LEAN_STEP_MAX, 0.0, _ticks(delta))


## The 60ths of a second (decomp ticks) `delta` covers.
static func _ticks(delta: float) -> float:
	return maxf(delta, 0.0) * DecompTime.TICK_HZ


## `Player_actor_Culc_over_speed_normalize_NoneZero`: climbing a slope divides the target
## speed by `|move_vec|²` (1 + rise²); flat ground and descents return 1.
func over_speed_normalize(at: Vector3) -> float:
	return _over_speed_normalize(at)


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


## `add_calc_short_angle2(&angle, target, 1−√0.5, 2500, 50)`: the fixed turn of the talk
## (`Movement_Talk`) and show-off (`Movement_Notice_rod`, net) states, over `delta` seconds
## (one tick when left out).
static func ease_turn(current: float, target: float, delta: float = DecompTime.TICK_SEC) -> float:
	return MathUtil.short_angle2(
		current, target, MathUtil.HALF_FRACTION, TURN_MAX_RAD, TURN_MIN_RAD, _ticks(delta)
	)


static func move_toward_speed(current: float, target: float, delta: float) -> float:
	if current < target:
		return minf(target, current + ACCEL * delta)
	if current > target:
		return maxf(target, current - DECEL * delta)
	return target
