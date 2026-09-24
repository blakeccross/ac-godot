class_name TrainControl
extends RefCounted

## The town train's schedule and motion (`m_train_control.c`). Pure state, stepped once per decomp
## play frame (`mTRC_move`, 60 Hz — `x += 0.5 · speed` is the "30fps -> 60fps" step); positions
## are absolute decomp GX on the rail row. The presentation (`FieldTrain`) and the sound (`TrainService`) read it.
##
## Every hour the train enters from the west edge at full speed, slows from block 2, stops at
## the station, waits, then pulls out and leaves east. It is due to leave the far edge at
## hh:19; `mTRC_get_depart_time` schedules its entry 4:10 earlier.
##
## Only `train_coming_flag` 0 (the timetable) is modelled. The intro arrival (flag 3) is
## `IntroStationStage`; the call-a-friend / departure flags (2, 4) have no feature yet.

enum Action {
	NONE,
	SPAWN_MOVING,
	BEGIN_SLOWDOWN,
	BEGIN_STOP,
	SIGNAL_STOPPED,
	WAIT_STOPPED,
	SIGNAL_STARTING,
	BEGIN_PULL_OUT,
	SPEED_UP,
}

## `mTRC_KishaStatusTrg` states (−1 = no change this tick).
const STATE_NONE := -1
const STATE_DEMO := 0
const STATE_APPROACH := 1
const STATE_STOPPED := 2
const STATE_PULL_OUT := 3
const STATE_GONE := 4

## GAFE01_00 values (`m_train_control.h`, the `#else` branch).
const SLOW_SPEED := 2.0
const FAST_SPEED := 6.0
const SLOW_RATE := 0.01
const STOP_RATE := 0.005
const START_RATE := 0.00345
const SPEEDUP_RATE := 0.00345

const TICK_HZ := PlayerLocomotion.LOGIC_HZ
const RAIL_Z_GX := 740.0
const BLOCK_GX := 640.0
const SPAWN_X_GX := 320.0
const PARKED_X_GX := 2367.0
const STOP_FROM_X_GX := 2165.0
const EXIT_X_GX := 4400.0
## `TRAIN1` stands 250 behind the locomotive (`mTRC_trainSet`).
const CABOOSE_BACK_GX := 250.0
const STOPPED_SIGNAL_TICKS := 48
const STARTING_SIGNAL_TICKS := 84
const PULL_OUT_TICKS := 180
## `mTRC_ACTION_SIGNAL_STOPPED` → `start_timer += 310`: how long the train stands.
const DWELL_SEC := 310
## `mTRC_get_depart_time`: due at the far edge at hh:19, entry 4:10 earlier.
const DEPART_MINUTE := 19
const LEAD_SEC := 4 * 60 + 10
const DAY_SEC := 86400

var action: Action = Action.NONE
var speed: float = 0.0
var x_gx: float = 0.0
var timer: int = 0
var start_timer: int = 0
var signal_on: bool = false
var control_state: int = 0
var last_control_state: int = 0
var day: int = 0


## `mTRC_init`, once per play session.
func init(now_sec: int, today: int) -> void:
	action = Action.NONE
	speed = 0.0
	x_gx = 0.0
	timer = 0
	signal_on = false
	control_state = 0
	last_control_state = 0
	start_timer = depart_time(now_sec)
	day = today


## `mTRC_get_depart_time`: the next entry time (seconds of day, may pass 86400).
static func depart_time(now_sec: int) -> int:
	for hour: int in range(0, 25):
		var due: int = hour * 3600 + DEPART_MINUTE * 60
		if due >= now_sec:
			return due - LEAD_SEC
	return 24 * 3600 + DEPART_MINUTE * 60 - LEAD_SEC


## `mTRC_mati_init` (title demo 1): parked at the station and never leaving.
func mati_init() -> void:
	action = Action.WAIT_STOPPED
	signal_on = true
	control_state = 1
	last_control_state = 1
	speed = 0.0
	x_gx = PARKED_X_GX


## `mTRC_norm_init`: enter from the west edge.
func _norm_init() -> void:
	action = Action.SPAWN_MOVING
	speed = 0.0
	control_state = 0
	last_control_state = 0
	x_gx = SPAWN_X_GX


func is_running() -> bool:
	return action != Action.NONE


func caboose_x_gx() -> float:
	return x_gx - CABOOSE_BACK_GX


## One `mTRC_move` tick. `arbeit`: the first job is running (`mEv_CheckArbeit`), which holds
## the timetable. `parked_demo`: title demo 1 (`mEv_TITLEDEMO_START1`). Returns the
## `KishaStatusTrg` state raised this tick, or `STATE_NONE`.
func step(now_sec: int, today: int, arbeit: bool = false, parked_demo: bool = false) -> int:
	var state: int = STATE_NONE
	if parked_demo:
		if action == Action.NONE:
			mati_init()
	elif action == Action.NONE and not arbeit and now_sec >= start_timer:
		_norm_init()
		state = STATE_APPROACH
	return _control(now_sec, today, state)


## `mTRC_trainControl`.
func _control(now_sec: int, today: int, state: int) -> int:
	if day != today:
		if start_timer >= DAY_SEC:
			start_timer -= DAY_SEC
		day = today
	match action:
		Action.SPAWN_MOVING:
			speed = FAST_SPEED
			if int(x_gx / BLOCK_GX) >= 2:
				action = Action.BEGIN_SLOWDOWN
		Action.BEGIN_SLOWDOWN:
			speed = chase(speed, SLOW_SPEED, SLOW_RATE)
			if x_gx > STOP_FROM_X_GX:
				action = Action.BEGIN_STOP
				speed = SLOW_SPEED
		Action.BEGIN_STOP:
			speed = chase(speed, 0.0, STOP_RATE)
			if absf(speed) < 0.008:
				signal_on = true
				timer = STOPPED_SIGNAL_TICKS
				action = Action.SIGNAL_STOPPED
				state = STATE_STOPPED
				speed = 0.0
		Action.SIGNAL_STOPPED:
			if timer == 0:
				action = Action.WAIT_STOPPED
				start_timer += DWELL_SEC
			else:
				timer -= 1
		Action.WAIT_STOPPED:
			if control_state != last_control_state:
				control_state = last_control_state
				signal_on = false
			elif control_state == 0 and now_sec >= start_timer:
				signal_on = false
			if not signal_on:
				timer = STARTING_SIGNAL_TICKS
				action = Action.SIGNAL_STARTING
		Action.SIGNAL_STARTING:
			if timer == 0:
				timer = PULL_OUT_TICKS
				action = Action.BEGIN_PULL_OUT
				state = STATE_PULL_OUT
			else:
				timer -= 1
		Action.BEGIN_PULL_OUT:
			speed = chase(speed, SLOW_SPEED, START_RATE)
			if timer == 0:
				action = Action.SPEED_UP
			else:
				timer -= 1
		Action.SPEED_UP:
			speed = chase(speed, FAST_SPEED, SPEEDUP_RATE)
			if x_gx > EXIT_X_GX:
				start_timer = depart_time(now_sec)
				action = Action.NONE
				state = STATE_GONE
	if action != Action.NONE:
		x_gx += 0.5 * speed
	return state


## `mTRC_trainSet` / `aTRC_area_check`: the train actors exist only while the locomotive is
## within one block east/west of the player's block, on the player's block row.
func in_area(player_block: Vector2i) -> bool:
	if action == Action.NONE:
		return false
	var block := Vector2i(int(x_gx / BLOCK_GX), int(RAIL_Z_GX / BLOCK_GX))
	return absi(block.x - player_block.x) < 2 and block.y == player_block.y


## `chase_f`: step `value` toward `target` by `step`.
static func chase(value: float, target: float, step: float) -> float:
	return move_toward(value, target, absf(step))
