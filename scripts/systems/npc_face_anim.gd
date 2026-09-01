class_name NpcFaceAnim
extends RefCounted

## `aNPC_tex_anm_ctrl` — the eye/mouth texture-pattern machine. An AC face is not skinned:
## the head carries one eye quad and one mouth quad, and the draw swaps which of the eight
## eye / six mouth textures each one samples. This reproduces the sequence tables and their
## fractional counters from `ac_npc_anime.c_inc`; `NpcFace` does the texture binding.

const FRAME_HZ := 30.0

## `nture[]` indices.
const EYE_OPEN := 0
const EYE_HALF := 1
const EYE_SHUT := 2
## `n_texture[]` indices.
const MOUTH_SHUT := 0
const MOUTH_SMALL := 1
const MOUTH_OPEN := 2

## `eye_normal_blink`. `aNPC_get_seq_cnt` gives 3, and the walk is downward from there, so
## the played order is open → shut(3) → half → open rather than a symmetric blink.
const EYE_NORMAL_BLINK: Array[Vector2i] = [
	Vector2i(EYE_OPEN, 1), Vector2i(EYE_HALF, 1), Vector2i(EYE_SHUT, 3), Vector2i(EYE_HALF, 1)
]
const EYE_SEQ_COUNT := 3
## `pattern_counter -= 0.5f` per drawn frame, so each table unit is two frames.
const EYE_RATE := 0.5
## `32 + RANDOM(16)` counter units between blink bursts.
const EYE_REST_MIN := 32
const EYE_REST_SPAN := 16

## `mouth_normal_move_type{A,B,C}` with `aNPC_get_seq_cnt` 4 / 2 / 6.
const MOUTH_TABLES: Array = [
	[
		Vector2i(MOUTH_SHUT, 1), Vector2i(MOUTH_SMALL, 1), Vector2i(MOUTH_OPEN, 1),
		Vector2i(MOUTH_SMALL, 1), Vector2i(MOUTH_SHUT, 1), Vector2i(MOUTH_SHUT, 0),
	],
	[
		Vector2i(MOUTH_SHUT, 1), Vector2i(MOUTH_SMALL, 1), Vector2i(MOUTH_SHUT, 1),
		Vector2i(MOUTH_SHUT, 0),
	],
	[
		Vector2i(MOUTH_SHUT, 1), Vector2i(MOUTH_SMALL, 1), Vector2i(MOUTH_OPEN, 1),
		Vector2i(MOUTH_SMALL, 1), Vector2i(MOUTH_OPEN, 1), Vector2i(MOUTH_SMALL, 1),
		Vector2i(MOUTH_SHUT, 1), Vector2i(MOUTH_SHUT, 0),
	],
]
const MOUTH_SEQ_COUNTS: Array[int] = [4, 2, 6]
## `pattern_counter -= 0.25f` per drawn frame, so each table unit is four frames.
const MOUTH_RATE := 0.25

var eye_pattern: int = EYE_OPEN
var mouth_pattern: int = MOUTH_SHUT

var _rng := RandomNumberGenerator.new()
var _accum: float = 0.0

var _eye_counter: float = 0.0
var _eye_seq: int = 0
var _eye_loops: int = 1

var _mouth_table: int = 0
var _mouth_counter: float = 0.0
var _mouth_seq: int = 0
var _mouth_loops: int = 1
var _mouth_active: bool = false


func _init() -> void:
	_rng.randomize()
	_start_eye_sequence(-1, 1 + _rng.randi_range(0, 2))


## Advance by wall time. `uttering` is `mMsg_Check_NowUtter` — see `aNPC_check_kutipaku`.
## Returns true when either pattern changed, so the caller can skip redundant rebinding.
func tick(delta: float, uttering: bool) -> bool:
	var before := Vector2i(eye_pattern, mouth_pattern)
	_accum += delta * FRAME_HZ
	var frames: int = int(_accum)
	_accum -= float(frames)
	## The original runs these off the draw, so cap a long hitch rather than replaying it.
	frames = mini(frames, 8)
	for _i in frames:
		_step_eye()
		_step_mouth(uttering)
	return before != Vector2i(eye_pattern, mouth_pattern)


func _step_eye() -> void:
	if _eye_counter > 0.0:
		_eye_counter -= EYE_RATE
		return
	if _eye_seq != 0:
		_eye_seq -= 1
		var entry: Vector2i = EYE_NORMAL_BLINK[_eye_seq]
		eye_pattern = entry.x
		_eye_counter = float(entry.y)
		return
	_eye_loops -= 1
	if _eye_loops <= 0:
		## Burst finished: hold the eyes open, then blink one to three more times.
		var rest: int = EYE_REST_MIN + _rng.randi_range(0, EYE_REST_SPAN - 1)
		_start_eye_sequence(rest, 1 + _rng.randi_range(0, 2))
	else:
		_start_eye_sequence(-1, _eye_loops)


func _start_eye_sequence(wait: int, loops: int) -> void:
	var entry: Vector2i = EYE_NORMAL_BLINK[0]
	eye_pattern = entry.x
	_eye_counter = float(entry.y) if wait < 0 else float(wait)
	_eye_seq = EYE_SEQ_COUNT
	_eye_loops = maxi(loops, 1)


func _step_mouth(uttering: bool) -> void:
	if not uttering:
		## `aNPC_tex_anm_ctrl` parks the mouth at the stop pattern when not speaking.
		_mouth_active = false
		mouth_pattern = MOUTH_SHUT
		return
	if not _mouth_active:
		_mouth_active = true
		_start_mouth_sequence(1 + _rng.randi_range(0, 2))
		return
	if _mouth_counter > 0.0:
		_mouth_counter -= MOUTH_RATE
		return
	if _mouth_seq != 0:
		_mouth_seq -= 1
		var entry: Vector2i = MOUTH_TABLES[_mouth_table][_mouth_seq]
		mouth_pattern = entry.x
		_mouth_counter = float(entry.y)
		return
	_mouth_loops -= 1
	_start_mouth_sequence(_mouth_loops if _mouth_loops > 0 else 1 + _rng.randi_range(0, 2))


func _start_mouth_sequence(loops: int) -> void:
	_mouth_table = _rng.randi_range(0, MOUTH_TABLES.size() - 1)
	mouth_pattern = MOUTH_TABLES[_mouth_table][0].x
	## `aNPC_tex_anm_ctrl_talk_seq` always passes `wait_time` 0, so the flap starts at once.
	_mouth_counter = 0.0
	_mouth_seq = MOUTH_SEQ_COUNTS[_mouth_table]
	_mouth_loops = maxi(loops, 1)
