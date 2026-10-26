class_name NpcPointMove
extends RefCounted

## A special NPC's scripted point actions (`aNPC_ACT_WALK` / `RUN` with
## `aNPC_ACT_TYPE_TO_POINT`, and the in-place `aNPC_ACT_TURN` / `TURN2`), advanced by `delta`.
## Pure: positions are GX, speeds GX a second; the caller places the node.
##
## `aNPC_position_move`: the body turns toward the point at the action's turn rate, speed eases
## to the action's max, and the actor moves along its facing. `aNPC_check_arrive_destination`
## ends the action once the squared distance to the point is under the arrival radius (72 by
## default — compared unsquared, as the decomp does).

## The decomp's speeds are GX per 1/30 s and `chase_f` adds `acceleration × 0.5` a 1/60 s tick.
const PER_FRAME := DecompTime.FRAME_HZ
const PER_TICK_RATE := 0.5 * DecompTime.TICK_HZ * DecompTime.FRAME_HZ
## `aNPC_spd_data` rows: max speed (1 and 3), acceleration (0.1 and 0.3).
const WALK_MAX := 1.0 * PER_FRAME
const WALK_ACCEL := 0.1 * PER_TICK_RATE
const RUN_MAX := 3.0 * PER_FRAME
const RUN_ACCEL := 0.3 * PER_TICK_RATE
## `aNPC_setupAction` `mv_angl_add` for the walk / run / turn action types (s16 per 30 fps frame).
const WALK_TURN := 0x200
const RUN_TURN := 0x400
const SPIN_TURN := 0x800
const ARRIVE_SQ_GX := 72.0

enum Gait { WAIT, WALK, RUN, TURN }

var facing: float = 0.0
var speed: float = 0.0
var gait: Gait = Gait.WAIT


func reset(yaw: float) -> void:
	facing = yaw
	speed = 0.0
	gait = Gait.WAIT


## `aNPC_ACT_WAIT` / `TURN*` have speed type 0: the actor stops dead when one starts.
func stop() -> void:
	speed = 0.0
	gait = Gait.WAIT


## `delta` seconds of a WALK / RUN to `goal_gx`. Returns the new position; `arrived(…)` tells
## when the action has ended.
func step_to(delta: float, pos_gx: Vector3, goal_gx: Vector3, run: bool) -> Vector3:
	gait = Gait.RUN if run else Gait.WALK
	var to := Vector2(goal_gx.x - pos_gx.x, goal_gx.z - pos_gx.z)
	if to.length_squared() > 0.0:
		facing = chase_yaw(facing, atan2(to.x, to.y), turn_rate(RUN_TURN if run else WALK_TURN) * delta)
	var max_speed: float = RUN_MAX if run else WALK_MAX
	var accel: float = RUN_ACCEL if run else WALK_ACCEL
	var was: float = speed
	speed = move_toward(speed, max_speed, accel * delta)
	var step: float = (was + speed) * 0.5 * delta
	return pos_gx + Vector3(sin(facing) * step, 0.0, cos(facing) * step)


## `delta` seconds of an in-place turn toward `target_yaw` (`TURN` spins 0x800 and plays WALK1;
## `TURN2` the same rate on WAIT1). Returns true once facing it (`aNPC_act_turn`).
func step_turn(delta: float, target_yaw: float) -> bool:
	speed = 0.0
	gait = Gait.TURN
	facing = chase_yaw(facing, target_yaw, turn_rate(SPIN_TURN) * delta)
	return is_equal_approx(facing, target_yaw)


## `speed` in the decomp's GX per 1/30 s.
func frame_speed() -> float:
	return speed / PER_FRAME


static func arrived(pos_gx: Vector3, goal_gx: Vector3) -> bool:
	var dx: float = goal_gx.x - pos_gx.x
	var dz: float = goal_gx.z - pos_gx.z
	return dx * dx + dz * dz < ARRIVE_SQ_GX


static func yaw_to(from_gx: Vector3, to_gx: Vector3) -> float:
	return atan2(to_gx.x - from_gx.x, to_gx.z - from_gx.z)


## `chase_angle` by `add_s16` a 1/30 s frame, in radians a second.
static func turn_rate(add_s16: int) -> float:
	return float(add_s16) * MathUtil.S16 * PER_FRAME


static func chase_yaw(from: float, target: float, step: float) -> float:
	var diff: float = angle_difference(from, target)
	if absf(diff) <= step:
		return target
	return wrapf(from + signf(diff) * step, -PI, PI)
