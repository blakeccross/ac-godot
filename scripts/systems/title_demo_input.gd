class_name TitleDemoInput
extends RefCounted

## Recorded attract-mode input (`m_titledemo.c` `set_player_demo_keydata` + `mPlib_SetData1_
## controller_data_for_title_demo`). Samples were captured at 30 Hz and play back by time:
## the stick is interpolated between the two samples either side of the playback time (the
## original's odd-tick blend is the halfway point), the buttons read the sample in effect.
##
## Sample word (`pact0.c`): `XXXXXXXB YYYYYYYA` — 7-bit signed stick X in bits 15..9, B in
## bit 8, 7-bit signed stick Y in bits 7..1, A in bit 0. Sticks are N64 units (Y up); the
## deadzone / max come from `m_controller.h`.

const STICK_MIN := 9.899495
const STICK_MAX := 61.0
## Samples a second.
const SAMPLE_HZ := 30.0
## `f1 < 1800`: the blend only reads a second sample below this index.
const BLEND_LIMIT := 1800

## Raw `u16` samples (`assets/generated/titledemo/demos.json` → `demos[n].keys`).
var keys: PackedInt32Array = PackedInt32Array()
## Seconds played so far (`S_tdemo_frame`, in seconds).
var time: float = 0.0
## `Input.get_vector` convention: x right, y toward the camera (forward is negative).
var move: Vector2 = Vector2.ZERO
var a_held: bool = false
## Rising edge of A (`trigger_btn_a`). Latched until `consume_a_pressed()`, so a press is not
## lost if the playback steps twice before the player reads it.
var a_pressed: bool = false
var b_held: bool = false
var b_pressed: bool = false
## The last sample whose buttons were read.
var _sample: int = -1


static func stick_x(word: int) -> int:
	return MathUtil.s16_signed(word & 0xFE00) / 512


static func stick_y(word: int) -> int:
	return MathUtil.s16_signed((word & 0x00FE) << 8) / 512


static func a_bit(word: int) -> bool:
	return (word & 1) != 0


static func b_bit(word: int) -> bool:
	return ((word >> 8) & 1) != 0


## `mCon_calc`: inside the deadzone nothing moves; past `STICK_MAX` the vector is clamped.
## Returns magnitude 0..1 (`move_pR`, uncorrected) along the stick direction, flipped to
## Godot's Y so forward is negative.
static func stick_to_move(x: float, y: float) -> Vector2:
	var t: float = sqrt(x * x + y * y)
	if t <= STICK_MIN:
		return Vector2.ZERO
	return Vector2(x, -y) / t * minf(t, STICK_MAX) / STICK_MAX


func setup(samples: PackedInt32Array) -> void:
	keys = samples
	time = 0.0
	_sample = -1
	move = Vector2.ZERO
	a_held = false
	a_pressed = false
	b_held = false
	b_pressed = false


## Reads the input at the playback time, then plays on `delta` seconds (`title_demo_move`).
## Every sample passed since the last read counts toward the button edges.
func step(delta: float) -> void:
	var at: float = time * SAMPLE_HZ
	var f0: int = int(floorf(at + 0.000001))
	var blend: float = at - float(f0)
	var w0: int = _word(f0)
	var sx := float(stick_x(w0))
	var sy := float(stick_y(w0))
	if blend > 0.000001 and f0 + 1 < BLEND_LIMIT:
		var w1: int = _word(f0 + 1)
		sx = lerpf(sx, float(stick_x(w1)), blend)
		sy = lerpf(sy, float(stick_y(w1)), blend)
	move = stick_to_move(sx, sy)
	for i: int in range(_sample + 1, f0 + 1):
		var word: int = _word(i)
		a_pressed = a_pressed or (a_bit(word) and not a_held)
		b_pressed = b_pressed or (b_bit(word) and not b_held)
		a_held = a_bit(word)
		b_held = b_bit(word)
	_sample = maxi(_sample, f0)
	time += maxf(delta, 0.0)


## Take the latched A edge; a second reader cannot fire the action twice.
func consume_a_pressed() -> bool:
	var pressed: bool = a_pressed
	a_pressed = false
	return pressed


func _word(index: int) -> int:
	if index < 0 or index >= keys.size():
		return 0
	return keys[index]
