class_name TrainCars
extends RefCounted

## Per-actor train state that lives while the cars are spawned (`ac_train0` / `ac_train1`):
## the two sprung couplings and the passenger-car door. Pure; `FieldTrain` applies it.
##
## `aTR0_ctrl_back_car`: the mid car (drawn by `TRAIN0` at `arg0_f`) trails the locomotive by
## 125 GX on a stiff spring that lets it run up to 2 GX slack. `aTR1_position_move`: the
## passenger car trails the mid car the same way. Starting or stopping the loco makes the
## cars bump into each other.

const COUPLING_GX := 125.0
const SLACK_GX := 2.0
const CATCH_UP := 0.8
const BOUNCE_BACK := -0.23
const SETTLE_RATE := 0.0025

## `aTR1_setupAction`: per `TrainControl.Action`, which clip (0 = `obj_train1_3_open`,
## 1 = `obj_train1_3_close`) and its speed (cKF frames per tick). Frame 1 of `open` is closed;
## frame 1 of `close` is open.
const DOOR_CLIP := [0, 0, 0, 0, 0, 1, 1, 0, 0]
const DOOR_SPEED := [0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.5, 0.0, 0.0]
const DOOR_OPEN_CLIP := 0
const DOOR_CLOSE_CLIP := 1
## `aTR1_OngenTrgStart(…, 43)`: the door opening / closing.
const DOOR_SE := &"2b"

var mid_x: float = 0.0
var mid_speed: float = 0.0
var caboose_x: float = 0.0
var caboose_speed: float = 0.0
var door_action: int = TrainControl.Action.WAIT_STOPPED
## `train1->arg0_f = 1.0` in `aTR1_actor_ct`, cleared after the first move.
var _fresh: bool = true


## `mTRC_trainSet` spawning both actors: mid car state zeroed (it snaps to its coupling on
## the first step), passenger car at `x − 250`, door set up for action 5.
func spawn(loco_x: float) -> void:
	mid_x = 0.0
	mid_speed = 0.0
	caboose_x = loco_x - 2.0 * COUPLING_GX
	caboose_speed = 0.0
	door_action = TrainControl.Action.WAIT_STOPPED
	_fresh = true


## One actor tick. `parked_demo` (title demo 1) pins the mid car and freezes the passenger
## car, as `mEv_CheckTitleDemo() == START1` / `mEv_IsNotTitleDemo()` do. Returns the door
## change as `{clip, speed, at_end, sound}`, or `{}` when the door keeps its state.
func step(loco_x: float, loco_speed: float, action: int, parked_demo: bool) -> Dictionary:
	if parked_demo:
		mid_x = loco_x - COUPLING_GX
	else:
		_step_mid(loco_x, loco_speed)
		_step_caboose()
	var door: Dictionary = {}
	if action != door_action:
		door = door_setup(action, parked_demo or _fresh)
		door_action = action
	_fresh = false
	return door


## `aTR1_setupAction`. `quiet`: title demo, or a car that has just spawned — the open/close
## (actions 4 and 6) then jumps to its end pose without the SE.
static func door_setup(action: int, quiet: bool) -> Dictionary:
	var clip: int = int(DOOR_CLIP[action])
	var moving: bool = action == TrainControl.Action.SIGNAL_STOPPED \
		or action == TrainControl.Action.SIGNAL_STARTING
	return {
		"clip": clip,
		"speed": float(DOOR_SPEED[action]),
		"at_end": moving and quiet,
		"sound": moving and not quiet,
	}


## `aTR0_ctrl_back_car`.
func _step_mid(loco_x: float, loco_speed: float) -> void:
	var base: float = loco_x - COUPLING_GX
	var next: float = mid_x + 0.5 * mid_speed
	if next - base > SLACK_GX:
		mid_speed = loco_speed if not is_zero_approx(loco_speed) else BOUNCE_BACK
		mid_x = base + SLACK_GX
	elif next - base <= 0.0:
		mid_speed = _catch_up(mid_speed, loco_speed)
		mid_x = base
	else:
		mid_speed = TrainControl.chase(mid_speed, 0.0, SETTLE_RATE)
		mid_x = next


## `aTR1_position_move`: the same spring, behind the mid car.
func _step_caboose() -> void:
	var base: float = mid_x - COUPLING_GX
	var next: float = caboose_x + 0.5 * caboose_speed
	if next - base <= 0.0:
		caboose_speed = _catch_up(caboose_speed, mid_speed)
		caboose_x = base
	elif next - base > SLACK_GX:
		caboose_speed = mid_speed if not is_zero_approx(mid_speed) else BOUNCE_BACK
		caboose_x = base + SLACK_GX
	else:
		caboose_speed = TrainControl.chase(caboose_speed, 0.0, SETTLE_RATE)
		caboose_x = next


## `calc_speed1` (both actors): a car that fell behind its coupling is pulled forward.
static func _catch_up(own: float, leader: float) -> float:
	if is_zero_approx(own):
		return CATCH_UP + leader
	if own < leader:
		return leader + 0.5 * (leader - own)
	return leader

