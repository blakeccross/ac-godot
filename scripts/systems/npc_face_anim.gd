class_name NpcFaceAnim
extends RefCounted

## `aNPC_tex_anm_ctrl` — the eye/mouth texture-pattern machine. An AC face is not skinned:
## the head carries one eye quad and one mouth quad, and the draw swaps which of the eight
## eye / six mouth textures each one samples. This reproduces the sequence tables and their
## fractional counters from `ac_npc_anime.c_inc`; `NpcFace` does the texture binding.
##
## Eye emotes past `normal` (`angry` / `sad` / `laugh` / `surprise` / `cry`) match the
## `eye_*_blink` tables. Mood wait poses (`wait_do1`, `wait_ai1`, `wait_ki1`, …) hold a
## single eye frame instead of blinking — `set_emote` follows those holds.

const FRAME_HZ := 30.0

## `nture[]` indices.
const EYE_OPEN := 0
const EYE_HALF := 1
const EYE_SHUT := 2
const EYE_ANGRY := 3
const EYE_SAD := 4
const EYE_LAUGH := 5
const EYE_SURPRISE := 6
const EYE_CRY := 7
## `n_texture[]` indices.
const MOUTH_SHUT := 0
const MOUTH_SMALL := 1
const MOUTH_OPEN := 2
const MOUTH_ANGRY_SHUT := 3
const MOUTH_ANGRY_SMALL := 4
const MOUTH_ANGRY_OPEN := 5

## Matches `eye_anm_table_type` / mood wait holds. `SLEEPY` is mood-only (hold shut).
enum Emote { NORMAL, ANGRY, SAD, LAUGH, SURPRISE, CRY, SLEEPY }

## `eye_*_blink`. `aNPC_get_seq_cnt` gives 3, and the walk is downward from there, so
## the played order is base → shut → half → base rather than a symmetric blink.
const EYE_BLINKS: Array = [
	[ # unused (seq_type 0 = hold)
		Vector2i(EYE_OPEN, 1), Vector2i(EYE_HALF, 1), Vector2i(EYE_SHUT, 3), Vector2i(EYE_HALF, 1),
	],
	[ # normal
		Vector2i(EYE_OPEN, 1), Vector2i(EYE_HALF, 1), Vector2i(EYE_SHUT, 3), Vector2i(EYE_HALF, 1),
	],
	[ # angry
		Vector2i(EYE_ANGRY, 1), Vector2i(EYE_HALF, 1), Vector2i(EYE_SHUT, 3), Vector2i(EYE_HALF, 1),
	],
	[ # sadly
		Vector2i(EYE_SAD, 1), Vector2i(EYE_HALF, 1), Vector2i(EYE_SHUT, 3), Vector2i(EYE_HALF, 1),
	],
	[ # laugh
		Vector2i(EYE_LAUGH, 1), Vector2i(EYE_HALF, 1), Vector2i(EYE_SHUT, 3), Vector2i(EYE_HALF, 1),
	],
	[ # surprise
		Vector2i(EYE_SURPRISE, 1), Vector2i(EYE_HALF, 1), Vector2i(EYE_SHUT, 3), Vector2i(EYE_HALF, 1),
	],
	[ # cry
		Vector2i(EYE_CRY, 1), Vector2i(EYE_HALF, 1), Vector2i(EYE_SHUT, 3), Vector2i(EYE_HALF, 1),
	],
]
const EYE_SEQ_COUNT := 3
## `pattern_counter -= 0.5f` per drawn frame, so each table unit is two frames.
const EYE_RATE := 0.5
## `32 + RANDOM(16)` counter units between blink bursts.
const EYE_REST_MIN := 32
const EYE_REST_SPAN := 16

## `mouth_*_move_type{A,B,C}` with `aNPC_get_seq_cnt` 4 / 2 / 6. Index 0 unused;
## 1 = normal (`mouth0..2`), 2 = angry (`mouth3..5`).
const MOUTH_TABLES: Array = [
	[], # unused
	[ # normal
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
	],
	[ # angry
		[
			Vector2i(MOUTH_ANGRY_SHUT, 1), Vector2i(MOUTH_ANGRY_SMALL, 1), Vector2i(MOUTH_ANGRY_OPEN, 1),
			Vector2i(MOUTH_ANGRY_SMALL, 1), Vector2i(MOUTH_ANGRY_SHUT, 1), Vector2i(MOUTH_SHUT, 0),
		],
		[
			Vector2i(MOUTH_ANGRY_SHUT, 1), Vector2i(MOUTH_ANGRY_SMALL, 1), Vector2i(MOUTH_ANGRY_SHUT, 1),
			Vector2i(MOUTH_SHUT, 0),
		],
		[
			Vector2i(MOUTH_ANGRY_SHUT, 1), Vector2i(MOUTH_ANGRY_SMALL, 1), Vector2i(MOUTH_ANGRY_OPEN, 1),
			Vector2i(MOUTH_ANGRY_SMALL, 1), Vector2i(MOUTH_ANGRY_OPEN, 1), Vector2i(MOUTH_ANGRY_SMALL, 1),
			Vector2i(MOUTH_ANGRY_SHUT, 1), Vector2i(MOUTH_SHUT, 0),
		],
	],
]
const MOUTH_SEQ_COUNTS: Array = [
	[],
	[4, 2, 6],
	[4, 2, 6],
]
## `pattern_counter -= 0.25f` per drawn frame, so each table unit is four frames.
const MOUTH_RATE := 0.25

var eye_pattern: int = EYE_OPEN
var mouth_pattern: int = MOUTH_SHUT
var emote: Emote = Emote.NORMAL

var _rng := RandomNumberGenerator.new()
var _accum: float = 0.0

## 0 = hold `_eye_hold` (mood wait poses); 1..6 = blink table index.
var _eye_seq_type: int = 1
var _eye_hold: int = EYE_OPEN
var _eye_counter: float = 0.0
var _eye_seq: int = 0
var _eye_loops: int = 1

## 0 = hold only; 1 = normal flap; 2 = angry flap.
var _mouth_seq_type: int = 1
var _mouth_hold: int = MOUTH_SHUT
var _mouth_table: int = 0
var _mouth_counter: float = 0.0
var _mouth_seq: int = 0
var _mouth_loops: int = 1
var _mouth_active: bool = false


func _init() -> void:
	_rng.randomize()
	set_emote(Emote.NORMAL)


## Map `mNpc_FEEL_*` onto the wait-pose emote (happy → laugh eyes, etc.).
static func emote_from_mood(mood: int) -> Emote:
	match mood:
		VillagerState.Mood.HAPPY:
			return Emote.LAUGH
		VillagerState.Mood.ANGRY:
			return Emote.ANGRY
		VillagerState.Mood.SAD:
			return Emote.SAD
		VillagerState.Mood.SLEEPY:
			return Emote.SLEEPY
		VillagerState.Mood.PITFALL:
			return Emote.SURPRISE
		_:
			return Emote.NORMAL


## Apply a face emote. Mood waits hold a frame; `NORMAL` blinks. Mouth flap family
## follows the decomp wait tables (`normal` vs `angry` mouth banks).
## Pass `mouth_hold_override` (>= 0) to park the mouth on a specific pattern —
## manpu smile/shock clips end open-mouthed while mood laughs stay shut.
func set_emote(next: Emote, mouth_hold_override: int = -1) -> void:
	emote = next
	match next:
		Emote.ANGRY:
			_eye_seq_type = 0
			_eye_hold = EYE_ANGRY
			_mouth_seq_type = 2
			_mouth_hold = MOUTH_ANGRY_SHUT
		Emote.SAD:
			_eye_seq_type = 0
			_eye_hold = EYE_SAD
			_mouth_seq_type = 2
			_mouth_hold = MOUTH_ANGRY_SHUT
		Emote.LAUGH:
			_eye_seq_type = 0
			_eye_hold = EYE_LAUGH
			_mouth_seq_type = 1
			_mouth_hold = MOUTH_SHUT
		Emote.SURPRISE:
			_eye_seq_type = 0
			_eye_hold = EYE_SURPRISE
			_mouth_seq_type = 1
			_mouth_hold = MOUTH_SHUT
		Emote.CRY:
			_eye_seq_type = 0
			_eye_hold = EYE_CRY
			_mouth_seq_type = 2
			_mouth_hold = MOUTH_ANGRY_SHUT
		Emote.SLEEPY:
			_eye_seq_type = 0
			_eye_hold = EYE_SHUT
			_mouth_seq_type = 0
			_mouth_hold = MOUTH_ANGRY_SMALL
		_:
			_eye_seq_type = 1
			_eye_hold = EYE_OPEN
			_mouth_seq_type = 1
			_mouth_hold = MOUTH_SHUT
	if mouth_hold_override >= 0:
		_mouth_hold = mouth_hold_override
	_mouth_active = false
	mouth_pattern = _mouth_hold
	if _eye_seq_type == 0:
		eye_pattern = _eye_hold
		_eye_seq = 0
		_eye_counter = 0.0
		_eye_loops = 1
	else:
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
	if _eye_seq_type == 0:
		eye_pattern = _eye_hold
		return
	if _eye_counter > 0.0:
		_eye_counter -= EYE_RATE
		return
	if _eye_seq != 0:
		_eye_seq -= 1
		var entry: Vector2i = _eye_blink_table()[_eye_seq]
		eye_pattern = entry.x
		_eye_counter = float(entry.y)
		return
	_eye_loops -= 1
	if _eye_loops <= 0:
		## Burst finished: hold the base eye, then blink one to three more times.
		var rest: int = EYE_REST_MIN + _rng.randi_range(0, EYE_REST_SPAN - 1)
		_start_eye_sequence(rest, 1 + _rng.randi_range(0, 2))
	else:
		_start_eye_sequence(-1, _eye_loops)


func _start_eye_sequence(wait: int, loops: int) -> void:
	var entry: Vector2i = _eye_blink_table()[0]
	eye_pattern = entry.x
	_eye_counter = float(entry.y) if wait < 0 else float(wait)
	_eye_seq = EYE_SEQ_COUNT
	_eye_loops = maxi(loops, 1)


func _eye_blink_table() -> Array:
	var idx: int = clampi(_eye_seq_type, 0, EYE_BLINKS.size() - 1)
	return EYE_BLINKS[idx]


func _step_mouth(uttering: bool) -> void:
	if not uttering or _mouth_seq_type == 0:
		## `aNPC_tex_anm_ctrl` parks the mouth at the stop pattern when not speaking.
		_mouth_active = false
		mouth_pattern = _mouth_hold
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
		var entry: Vector2i = _mouth_variant()[_mouth_seq]
		mouth_pattern = entry.x
		_mouth_counter = float(entry.y)
		return
	_mouth_loops -= 1
	_start_mouth_sequence(_mouth_loops if _mouth_loops > 0 else 1 + _rng.randi_range(0, 2))


func _start_mouth_sequence(loops: int) -> void:
	var variants: Array = MOUTH_TABLES[_mouth_seq_type]
	_mouth_table = _rng.randi_range(0, variants.size() - 1)
	mouth_pattern = _mouth_variant()[0].x
	## `aNPC_tex_anm_ctrl_talk_seq` always passes `wait_time` 0, so the flap starts at once.
	_mouth_counter = 0.0
	_mouth_seq = int(MOUTH_SEQ_COUNTS[_mouth_seq_type][_mouth_table])
	_mouth_loops = maxi(loops, 1)


func _mouth_variant() -> Array:
	return MOUTH_TABLES[_mouth_seq_type][_mouth_table]
