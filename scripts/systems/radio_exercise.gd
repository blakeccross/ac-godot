class_name RadioExercise
extends RefCounted

## Radio exercise (`m_player_main_radio_exercise`, `Player_actor_Check_radio_exercise_command`).
## While the aerobics radio plays (indoors) or the aerobics event runs on the shrine acre,
## C-stick flicks are logged in an 8-slot ring buffer; a logged sequence that ends with one
## of the eighteen key patterns starts that exercise. Directions follow
## `Player_actor_CheckController_forRadio_exercise`: 0 neutral, 6 down, 3 up, 1 right,
## 2 left, 7 / 8 down-right / down-left, 4 / 5 up-right / up-left; -1 means no input allowed.

const RING_SIZE := 8
## `ring_buf_timer`: holding one direction re-logs it after 50 ticks.
const HOLD_TICKS := 50
## `JW_JUTGamepad_getSubStickValue() > 0.6`.
const STICK_MIN := 0.6

const KEYS: Array = [
	[6, 0, 3],
	[1, 4, 3, 5, 2],
	[2, 5, 3, 4, 1],
	[3, 0, 3],
	[5, 0, 5],
	[7, 0, 5],
	[4, 0, 4],
	[8, 0, 4],
	[2, 0, 2],
	[1, 0, 2],
	[1, 0, 1],
	[2, 0, 1],
	[8, 0, 8],
	[4, 0, 8],
	[7, 0, 7],
	[5, 0, 7],
	[6, 8, 2, 5, 3, 4, 1, 7],
	[6, 7, 1, 4, 3, 5, 2, 8],
]
## `continue_command_data`: the arm circles flow straight into their mirror.
const CONTINUE: Array[int] = [-1, 17, 16, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]
## `anime_index_data` (clip leaf per command).
const CLIPS: Array[String] = [
	"ply_1_taisou1", "ply_1_taisou2_1", "ply_1_taisou2_2", "ply_1_taisou3",
	"ply_1_taisou4_1", "ply_1_taisou4_1", "ply_1_taisou4_2", "ply_1_taisou4_2",
	"ply_1_taisou5_1", "ply_1_taisou5_1", "ply_1_taisou5_2", "ply_1_taisou5_2",
	"ply_1_taisou6_1", "ply_1_taisou6_1", "ply_1_taisou6_2", "ply_1_taisou6_2",
	"ply_1_taisou7_1", "ply_1_taisou7_2",
]
## `CulcAnimation_Radio_exercise` speed factor per command (cKF frames per tick).
const SPEED: Array[float] = [
	0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.25, 0.25, 0.25, 0.25, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5,
]

var _ring: Array[int] = []
var _index: int = 0
var _hold: int = 0
## `radio_exercise_continue_cmd_idx` / `radio_exercise_cmd_timer`.
var pending: int = -1
var pending_timer: float = 0.0


func _init() -> void:
	_ring.resize(RING_SIZE)
	_ring.fill(-1)


## `Player_actor_CheckController_forRadio_exercise` from a stick with y up.
static func direction(stick: Vector2) -> int:
	if stick.length() <= STICK_MIN:
		return 0
	## `JUTGamePad` sub-stick angle: 0 is down, +90° right, ±180° up.
	var deg: float = rad_to_deg(atan2(stick.x, -stick.y))
	if deg >= 0.0:
		if deg < 22.5:
			return 6
		if deg < 67.5:
			return 7
		if deg < 112.5:
			return 1
		if deg < 157.5:
			return 4
		return 3
	if deg > -22.5:
		return 6
	if deg > -67.5:
		return 8
	if deg > -112.5:
		return 2
	if deg > -157.5:
		return 5
	return 3


func _at(ofs: int) -> int:
	return _ring[(_index + ofs) % RING_SIZE]


## `Player_actor_Set_RadioExerciseCommandRingBuffer`.
func log_command(command: int) -> void:
	if command >= 0 and _at(0) == command and _hold < HOLD_TICKS:
		_hold += 1
		return
	_index = (_index + RING_SIZE - 1) % RING_SIZE
	_ring[_index] = command
	_hold = 0


## `Player_actor_Check_radio_exercise_command`: the newest entries against each key, newest
## last. While an exercise that chains is pending, only its follow-up counts.
func match_command(continue_idx: int = -1) -> Dictionary:
	var only: int = CONTINUE[continue_idx] if continue_idx >= 0 and continue_idx < CONTINUE.size() else -1
	for i: int in KEYS.size():
		if only >= 0 and i != only:
			continue
		var key: Array = KEYS[i]
		var ok := true
		for j: int in key.size():
			var cmd: int = _at(j)
			if cmd < 0 or cmd != int(key[key.size() - 1 - j]):
				ok = false
				break
		if ok:
			return {"cmd": i, "timer": 6.0 if CONTINUE[i] >= 0 else 0.0}
	return {"cmd": -1, "timer": 0.0}


## `Player_actor_CheckAndRequest_main_radio_exercise_all` for one tick: returns the exercise
## to start now, or -1. `request` false only updates the pending choice.
func step(request: bool = true) -> int:
	pending_timer = maxf(pending_timer - 1.0, 0.0)
	var hit: Dictionary = match_command(pending)
	var cmd: int = int(hit["cmd"])
	if cmd >= 0:
		if pending < 0 or pending_timer > 0.0:
			pending = cmd
			pending_timer = float(hit["timer"])
	if request and pending >= 0 and pending_timer <= 0.0:
		var start: int = pending
		pending = -1
		pending_timer = 0.0
		return start
	return -1


## `setup_main_Radio_exercise` clears the pending command, and its first tick logs no input
## (`_04`), so the pattern just matched cannot fire again by itself.
func begin() -> void:
	pending = -1
	pending_timer = 0.0
	log_command(-1)
