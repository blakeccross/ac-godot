class_name NpcPointMove
extends RefCounted

## A special NPC's scripted point actions (`aNPC_ACT_WALK` / `RUN` with
## `aNPC_ACT_TYPE_TO_POINT`, and the in-place `aNPC_ACT_TURN` / `TURN2`), one 60 Hz frame at a
## time. Pure: positions are GX, the caller places the node.
##
## `aNPC_position_move`: the body chases `mv_angl` (the bearing to the point) by `mv_add_angl`
## through the frame-scaled `chase_angle` (half the step per 60 Hz frame), speed chases the
## action's max by `acceleration × 0.5` per frame, and the actor moves `0.5 · speed` GX along
## its facing. `aNPC_check_arrive_destination` ends the action once the squared distance to
## the point is under the arrival radius (72 by default — compared unsquared, as the decomp does).

## `aNPC_spd_data` rows: max speed, acceleration.
const WALK_MAX := 1.0
const WALK_ACCEL := 0.1
const RUN_MAX := 3.0
const RUN_ACCEL := 0.3
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


## One frame of a WALK / RUN to `goal_gx`. Returns the new position; `arrived(…)` tells when
## the action has ended.
func step_to(pos_gx: Vector3, goal_gx: Vector3, run: bool) -> Vector3:
	gait = Gait.RUN if run else Gait.WALK
	var to := Vector2(goal_gx.x - pos_gx.x, goal_gx.z - pos_gx.z)
	if to.length_squared() > 0.0:
		facing = chase_yaw(facing, atan2(to.x, to.y), turn_step(RUN_TURN if run else WALK_TURN))
	var max_speed: float = RUN_MAX if run else WALK_MAX
	var accel: float = RUN_ACCEL if run else WALK_ACCEL
	speed = move_toward(speed, max_speed, accel * 0.5)
	var step: float = 0.5 * speed
	return pos_gx + Vector3(sin(facing) * step, 0.0, cos(facing) * step)


## One frame of an in-place turn toward `target_yaw` (`TURN` spins 0x800 and plays WALK1;
## `TURN2` the same rate on WAIT1). Returns true once facing it (`aNPC_act_turn`).
func step_turn(target_yaw: float) -> bool:
	speed = 0.0
	gait = Gait.TURN
	facing = chase_yaw(facing, target_yaw, turn_step(SPIN_TURN))
	return is_equal_approx(facing, target_yaw)


static func arrived(pos_gx: Vector3, goal_gx: Vector3) -> bool:
	var dx: float = goal_gx.x - pos_gx.x
	var dz: float = goal_gx.z - pos_gx.z
	return dx * dx + dz * dz < ARRIVE_SQ_GX


static func yaw_to(from_gx: Vector3, to_gx: Vector3) -> float:
	return atan2(to_gx.x - from_gx.x, to_gx.z - from_gx.z)


## `chase_angle` step for one 60 Hz frame (`game_GameFrame_2F` halves it).
static func turn_step(add_s16: int) -> float:
	return float(add_s16) * MLib.S16 / DecompTime.TICKS_PER_FRAME


static func chase_yaw(from: float, target: float, step: float) -> float:
	var diff: float = angle_difference(from, target)
	if absf(diff) <= step:
		return target
	return wrapf(from + signf(diff) * step, -PI, PI)
