class_name PlayerLocomotion
extends RefCounted

## GameCube walk feel in meters. Speeds follow `m_player_main_walk` (4.875 / 7.5 per
## frame at 30 Hz) scaled so one 40-unit tile is one 2 m cell. Not a C port.

enum Gait { WAIT, WALK, RUN, DASH }

const FRAME_HZ := 30.0
const TILE_UNITS := 40.0
const TILE_METERS := 2.0
const UNIT_METERS := TILE_METERS / TILE_UNITS

const ORIG_WALK := 4.875
const ORIG_RUN := 7.5
const ORIG_WALK_RUN := 3.525
const ORIG_ACCEL := 0.60899997
const ORIG_DECEL := 0.32625002

const WALK_SPEED := ORIG_WALK * FRAME_HZ * UNIT_METERS
const RUN_SPEED := ORIG_RUN * FRAME_HZ * UNIT_METERS
const WALK_RUN_SPEED := ORIG_WALK_RUN * FRAME_HZ * UNIT_METERS
const ACCEL := ORIG_ACCEL * FRAME_HZ * UNIT_METERS * FRAME_HZ
const DECEL := ORIG_DECEL * FRAME_HZ * UNIT_METERS * FRAME_HZ

const STICK_DEADZONE := 0.05
const IDLE_SPEED := 0.08
## s16 2500 / 65536 of a turn, per 30 Hz frame.
const TURN_MAX_RAD := 2500.0 * TAU / 65536.0
const TURN_MIN_RAD := 50.0 * TAU / 65536.0

var planar_speed: float = 0.0
var facing: float = 0.0


func reset(yaw: float = 0.0) -> void:
	planar_speed = 0.0
	facing = yaw


func gait() -> Gait:
	if planar_speed < IDLE_SPEED:
		return Gait.WAIT
	if planar_speed < WALK_RUN_SPEED:
		return Gait.WALK
	if planar_speed <= WALK_SPEED:
		return Gait.RUN
	return Gait.DASH


func forward() -> Vector3:
	return Vector3(sin(facing), 0.0, cos(facing))


func facing_point(origin: Vector3, distance: float) -> Vector3:
	return origin + forward() * distance


func tick(delta: float, wish_dir: Vector3, stick: float, dashing: bool, locked: bool) -> Vector3:
	if delta <= 0.0:
		return Vector3(sin(facing), 0.0, cos(facing)) * planar_speed
	if locked:
		stick = 0.0
		wish_dir = Vector3.ZERO
	stick = clampf(stick, 0.0, 1.0)
	var cap: float = RUN_SPEED if dashing else WALK_SPEED
	var target: float = cap * stick
	if stick > STICK_DEADZONE and wish_dir.length_squared() > 0.0001:
		var wish_yaw: float = atan2(wish_dir.x, wish_dir.z)
		facing = step_facing(facing, wish_yaw, stick, delta)
		var aligned: float = cos(angle_difference(facing, wish_yaw))
		if aligned <= 0.0:
			target = 0.0
		else:
			target *= aligned
	else:
		target = 0.0
	planar_speed = move_toward_speed(planar_speed, target, delta)
	return forward() * planar_speed


static func turn_mod(stick: float) -> float:
	if stick >= 1.0:
		return 0.5
	if stick <= STICK_DEADZONE:
		return 0.01
	return 0.01 + 0.5157895 * (stick - STICK_DEADZONE)


static func step_facing(current: float, target: float, stick: float, delta: float) -> float:
	var fraction: float = 1.0 - sqrt(1.0 - turn_mod(stick))
	var dt_scale: float = delta * FRAME_HZ
	var max_step: float = TURN_MAX_RAD * dt_scale
	var min_step: float = TURN_MIN_RAD * dt_scale
	var signed: float = angle_difference(current, target)
	if is_zero_approx(signed):
		return target
	var step: float = signed * fraction
	if absf(step) > min_step:
		step = clampf(step, -max_step, max_step)
	else:
		step = min_step * signf(signed)
	var next: float = current + step
	if signf(angle_difference(next, target)) != signf(signed):
		return target
	return next


static func move_toward_speed(current: float, target: float, delta: float) -> float:
	if current < target:
		return minf(target, current + ACCEL * delta)
	if current > target:
		return maxf(target, current - DECEL * delta)
	return target
