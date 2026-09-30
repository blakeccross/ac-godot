class_name TownTune
extends RefCounted

## The town tune (`m_melody.c`): 16 steps, each 0–15 — G low … E (0–12), random (13),
## rest (14, the sleeping frog) and tie (15, the dash, holding the previous note). Saved as
## `Save_Get(melody)`, a u64 of nibbles, first step in the top nibble. Played on the hour
## as the time signal (`mBGMTime_signal_melody`) and edited at the tune board
## (`m_mscore_ovl`).

const LENGTH := 16
const HIGHEST := 12
const RANDOM := 13
const REST := 14
const TIE := 15
## `mMld_SetDefaultMelody`.
const DEFAULT: Array[int] = [0x7, 0xC, 0xF, 0x7, 0x6, 0xB, 0xF, 0x9, 0xA, 0xE, 0xD, 0xE, 0x3, 0xF, 0xE, 0xE]
## `single_se` in `mMS_move_Play`: the note each value plays alone (none for rest / tie).
const NOTE_SE: Array[StringName] = [
	&"note_g_low", &"note_a_low", &"note_b_low", &"note_c_low", &"note_d_low", &"note_e_low", &"note_f_low",
	&"note_g", &"note_a", &"note_b", &"note_c", &"note_d", &"note_e", &"note_random",
]


static func default_notes() -> PackedByteArray:
	return PackedByteArray(DEFAULT)


static func sanitize(notes: Variant) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(LENGTH)
	if not (notes is Array or notes is PackedByteArray or notes is PackedInt32Array):
		return default_notes()
	var count: int = notes.size()
	if count != LENGTH:
		return default_notes()
	for i: int in LENGTH:
		out[i] = clampi(int(notes[i]), 0, 15)
	return out


## `mMld_TransformMelodyData_u8_2_u64`.
static func pack(notes: PackedByteArray) -> int:
	var v := 0
	for i: int in LENGTH:
		v |= (int(notes[i]) & 0xF) << (60 - i * 4)
	return v


## `mMld_TransformMelodyData_u64_2_u8`.
static func unpack(v: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(LENGTH)
	for i: int in LENGTH:
		out[i] = (v >> (60 - i * 4)) & 0xF
	return out


## C-stick down on a step (`mMS_move_Play`): rest is the bottom, then tie, G low … random.
## Returns the new value; `se` is the note to sound or &"".
static func step_down(note: int) -> int:
	if note == REST:
		return note
	return TIE if note == 0 else note - 1


static func step_up(note: int) -> int:
	if note == RANDOM:
		return note
	return 0 if note == TIE else note + 1


## The SE `mMS_move_Play` sounds for a step value (rests and ties are silent).
static func note_se(note: int) -> StringName:
	return NOTE_SE[note] if note >= 0 and note < NOTE_SE.size() else &""
