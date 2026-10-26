class_name TrainControl
extends RefCounted

## The town train's schedule and motion (`m_train_control.c`). Pure state, advanced by `delta`
## (`mTRC_move`); `x` is a `TownSpace` field position (metres) on the rail row and `speed` is
## metres a second. The decomp's speeds are GX per 1/30 s and its rates per 1/60 s tick; each
## constant converts where it is written. The presentation (`FieldTrain`) and the sound (`TrainService`) read it.
##
## Every hour the train enters from the west edge at full speed, slows from block 2, stops at
## the station, waits, then pulls out and leaves east. It is due to leave the far edge at
## hh:19; `mTRC_get_depart_time` schedules its entry 4:10 earlier.
##
## `train_coming_flag` 0 (the timetable) and 3 (the new-resident arrival, `demo_init`) are
## modelled; the call-a-friend / departure flags (2, 4) have no feature yet.

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

## `mTRC_KishaStatusTrg` states (−1 = no change this step).
const STATE_NONE := -1
const STATE_DEMO := 0
const STATE_APPROACH := 1
const STATE_STOPPED := 2
const STATE_PULL_OUT := 3
const STATE_GONE := 4

const GX := FieldCatalog.GX_TO_METERS
## One GX per 1/30 s, in metres a second; and a per-tick change of that, in metres a second².
const PER_FRAME := GX * DecompTime.FRAME_HZ
const PER_TICK_RATE := GX * DecompTime.FRAME_HZ * DecompTime.TICK_HZ
## GAFE01_00 values (`m_train_control.h`, the `#else` branch): speeds 2 and 6, eased at
## 0.01 / 0.005 / 0.00345 a tick.
const SLOW_SPEED := 2.0 * PER_FRAME
const FAST_SPEED := 6.0 * PER_FRAME
const SLOW_RATE := 0.01 * PER_TICK_RATE
const STOP_RATE := 0.005 * PER_TICK_RATE
const START_RATE := 0.00345 * PER_TICK_RATE
const SPEEDUP_RATE := 0.00345 * PER_TICK_RATE
## `fabsf(speed) < 0.008`: stopped.
const STOPPED_BELOW := 0.008 * PER_FRAME

## Rail row and stops: decomp field GX.
const RAIL_Z := 740.0 * GX
const BLOCK := TownSpace.BLOCK
const SPAWN_X := 320.0 * GX
const PARKED_X := 2367.0 * GX
## `mTRC_demo_init`: the intro train is already slowing at x 2037 GX when the town loads.
const DEMO_X := 2037.0 * GX
## `mTRC_demo_init`: `train_start_timer = now − 4:50`, so after the 310 s dwell is added at
## the stop the train is due out 20 s after the arrival began.
const DEMO_LEAD_SEC := 4 * 60 + 50
const STOP_FROM_X := 2165.0 * GX
const EXIT_X := 4400.0 * GX
## `TRAIN1` stands 250 GX behind the locomotive (`mTRC_trainSet`).
const CABOOSE_BACK := 250.0 * GX
## The signal and pull-out timers: 48, 84 and 180 ticks.
const STOPPED_SIGNAL_TIME := 48.0 / DecompTime.TICK_HZ
const STARTING_SIGNAL_TIME := 84.0 / DecompTime.TICK_HZ
const PULL_OUT_TIME := 180.0 / DecompTime.TICK_HZ
## `mTRC_ACTION_SIGNAL_STOPPED` → `start_timer += 310`: how long the train stands.
const DWELL_SEC := 310
## `mTRC_get_depart_time`: due at the far edge at hh:19, entry 4:10 earlier.
const DEPART_MINUTE := 19
const LEAD_SEC := 4 * 60 + 10
const DAY_SEC := 86400

var action: Action = Action.NONE
var speed: float = 0.0
var x: float = 0.0
## Seconds left on the current signal or pull-out.
var timer: float = 0.0
var start_timer: int = 0
var signal_on: bool = false
var control_state: int = 0
var last_control_state: int = 0
var day: int = 0


## `mTRC_init`, once per play session.
func init(now_sec: int, today: int) -> void:
	action = Action.NONE
	speed = 0.0
	x = 0.0
	timer = 0.0
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
	x = PARKED_X


## `mTRC_demo_init` (`train_coming_flag` 3, set by `aID_first_set`): the new resident's train
## appears west of the station already at slow speed, stops, and leaves on its own shortly
## after. The caller raises `STATE_DEMO` (`mTRC_schedule` returns 0).
func demo_init(now_sec: int, today: int) -> void:
	action = Action.BEGIN_SLOWDOWN
	speed = SLOW_SPEED
	start_timer = now_sec - DEMO_LEAD_SEC
	day = today
	control_state = 0
	last_control_state = 0
	x = DEMO_X


## `mTRC_norm_init`: enter from the west edge.
func _norm_init() -> void:
	action = Action.SPAWN_MOVING
	speed = 0.0
	control_state = 0
	last_control_state = 0
	x = SPAWN_X


func is_running() -> bool:
	return action != Action.NONE


func caboose_x() -> float:
	return x - CABOOSE_BACK


## `delta` seconds of `mTRC_move`. `arbeit`: the first job is running (`mEv_CheckArbeit`),
## which holds the timetable. `parked_demo`: title demo 1 (`mEv_TITLEDEMO_START1`).
## `coming_demo`: `train_coming_flag == 3` now (consumed by the caller). Returns the
## `KishaStatusTrg` state raised, or `STATE_NONE`.
func advance(
	delta: float, now_sec: int, today: int, arbeit: bool = false, parked_demo: bool = false, coming_demo: bool = false
) -> int:
	var state: int = STATE_NONE
	if coming_demo:
		demo_init(now_sec, today)
		state = STATE_DEMO
	elif parked_demo:
		if action == Action.NONE:
			mati_init()
	elif action == Action.NONE and not arbeit and now_sec >= start_timer:
		_norm_init()
		state = STATE_APPROACH
	return _control(delta, now_sec, today, state)


## `mTRC_trainControl`.
func _control(delta: float, now_sec: int, today: int, state: int) -> int:
	if day != today:
		if start_timer >= DAY_SEC:
			start_timer -= DAY_SEC
		day = today
	## Speed at the start of the step; a speed that jumps (rather than eases) resets it, so
	## the move below uses the new speed for the whole step.
	var was: float = speed
	match action:
		Action.SPAWN_MOVING:
			speed = FAST_SPEED
			was = speed
			if int(x / BLOCK) >= 2:
				action = Action.BEGIN_SLOWDOWN
		Action.BEGIN_SLOWDOWN:
			speed = move_toward(speed, SLOW_SPEED, SLOW_RATE * delta)
			var average: float = (was + speed) * 0.5
			if x > STOP_FROM_X:
				action = Action.BEGIN_STOP
				speed = SLOW_SPEED
				was = speed
			elif average > 0.0 and x + average * delta > STOP_FROM_X:
				## Passes the stop trigger this step: brake from the moment it does, so the
				## train stands at the same place whatever the frame rate.
				var to_trigger: float = (STOP_FROM_X - x) / average
				x = STOP_FROM_X
				action = Action.BEGIN_STOP
				speed = SLOW_SPEED
				return _control(delta - to_trigger, now_sec, today, state)
		Action.BEGIN_STOP:
			speed = move_toward(speed, 0.0, STOP_RATE * delta)
			if absf(speed) < STOPPED_BELOW:
				signal_on = true
				timer = STOPPED_SIGNAL_TIME
				action = Action.SIGNAL_STOPPED
				state = STATE_STOPPED
				speed = 0.0
				was = 0.0
		Action.SIGNAL_STOPPED:
			if timer <= 0.0:
				action = Action.WAIT_STOPPED
				start_timer += DWELL_SEC
			else:
				timer -= delta
		Action.WAIT_STOPPED:
			if control_state != last_control_state:
				control_state = last_control_state
				signal_on = false
			elif control_state == 0 and now_sec >= start_timer:
				signal_on = false
			if not signal_on:
				timer = STARTING_SIGNAL_TIME
				action = Action.SIGNAL_STARTING
		Action.SIGNAL_STARTING:
			if timer <= 0.0:
				timer = PULL_OUT_TIME
				action = Action.BEGIN_PULL_OUT
				state = STATE_PULL_OUT
			else:
				timer -= delta
		Action.BEGIN_PULL_OUT:
			speed = move_toward(speed, SLOW_SPEED, START_RATE * delta)
			if timer <= 0.0:
				action = Action.SPEED_UP
			else:
				timer -= delta
		Action.SPEED_UP:
			speed = move_toward(speed, FAST_SPEED, SPEEDUP_RATE * delta)
			if x > EXIT_X:
				start_timer = depart_time(now_sec)
				action = Action.NONE
				state = STATE_GONE
	if action != Action.NONE:
		x += (was + speed) * 0.5 * delta
	return state


## `speed` in the decomp's GX per 1/30 s, for the formulas written in it (wheel rate, smoke and
## chuff spacing).
func frame_speed() -> float:
	return speed / PER_FRAME


## `mTRC_trainSet` / `aTRC_area_check`: the train actors exist only while the locomotive is
## within one block east/west of the player's block, on the player's block row.
func in_area(player_block: Vector2i) -> bool:
	if action == Action.NONE:
		return false
	var block := Vector2i(int(x / BLOCK), int(RAIL_Z / BLOCK))
	return absi(block.x - player_block.x) < 2 and block.y == player_block.y

