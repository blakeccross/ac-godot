class_name TitleDemoInput
extends RefCounted

## Recorded attract-mode input (`m_titledemo.c` `set_player_demo_keydata` + `mPlib_SetData1_
## controller_data_for_title_demo`). Samples were captured at 30 Hz; the game consumes one
## frame per 60 Hz tick, so each sample covers two ticks and the stick is blended across the
## odd tick.
##
## Sample word (`pact0.c`): `XXXXXXXB YYYYYYYA` — 7-bit signed stick X in bits 15..9, B in
## bit 8, 7-bit signed stick Y in bits 7..1, A in bit 0. Sticks are N64 units (Y up); the
## deadzone / max come from `m_controller.h`.

const STICK_MIN := 9.899495
const STICK_MAX := 61.0
## `f1 < 1800`: the blend only reads a second sample below this index.
const BLEND_LIMIT := 1800

## Raw `u16` samples (`assets/generated/titledemo/demos.json` → `demos[n].keys`).
var keys: PackedInt32Array = PackedInt32Array()
## Ticks consumed so far (`S_tdemo_frame`).
var frame: int = 0
## `Input.get_vector` convention: x right, y toward the camera (forward is negative).
var move: Vector2 = Vector2.ZERO
var a_held: bool = false
## Rising edge of A (`trigger_btn_a`). Latched until `consume_a_pressed()`: the title steps this
## from an accumulator, so a jittery frame can run two steps before the player's physics tick
## reads it, and a one-step pulse would be overwritten and the press lost.
var a_pressed: bool = false
var b_held: bool = false
var b_pressed: bool = false


static func stick_x(word: int) -> int:
	return _signed16(word & 0xFE00) / 512


static func stick_y(word: int) -> int:
	return _signed16((word & 0x00FE) << 8) / 512


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
	frame = 0
	move = Vector2.ZERO
	a_held = false
	a_pressed = false
	b_held = false
	b_pressed = false


## One 60 Hz game tick (`title_demo_move`).
func step() -> void:
	var f0: int = frame / 2
	var f1: int = f0 + (frame % 2)
	var w0: int = _word(f0)
	var sx: float
	var sy: float
	if f0 != f1 and f1 < BLEND_LIMIT:
		var w1: int = _word(f1)
		sx = (float(stick_x(w0)) + float(stick_x(w1))) / 2.0
		sy = (float(stick_y(w0)) + float(stick_y(w1))) / 2.0
	else:
		sx = float(stick_x(w0))
		sy = float(stick_y(w0))
	move = stick_to_move(sx, sy)
	var a_now: bool = a_bit(w0)
	var b_now: bool = b_bit(w0)
	a_pressed = a_pressed or (a_now and not a_held)
	b_pressed = b_pressed or (b_now and not b_held)
	a_held = a_now
	b_held = b_now
	frame += 1


## Take the latched A edge; a second reader cannot fire the action twice.
func consume_a_pressed() -> bool:
	var pressed: bool = a_pressed
	a_pressed = false
	return pressed


func _word(index: int) -> int:
	if index < 0 or index >= keys.size():
		return 0
	return keys[index]


static func _signed16(value: int) -> int:
	var v: int = value & 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v
