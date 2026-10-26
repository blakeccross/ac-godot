class_name NpcClipFace
extends RefCounted

## Per-clip face rules for Rover's train clips (`aNPC_Animation_c` eye / mouth fields in
## `npc_1_*.c`, applied by `aNPC_tex_anm_ctrl`). A clip with a fixed pattern sequence shows
## `seq[frame − 1]` and ignores blinking and message flapping; a clip whose eye type is 0
## holds the eyes open; the rest blink at random as usual.
##
## Sequences are run-length encoded as `Vector2i(pattern, frames)` over the clip's frames.

enum Eye { BLINK, HOLD, FIXED }

## `npc_1_open_d10_tex_index` / `npc_1_open_d11_tex_index` (131 frames). The mouth rests on
## mouth0, closes onto mouth3 for the step down (frames 76–118), then eases open.
const OPEN_D1_EYE: Array[Vector2i] = [
	Vector2i(0, 36), Vector2i(1, 1), Vector2i(2, 2), Vector2i(0, 34), Vector2i(1, 1), Vector2i(2, 2),
	Vector2i(0, 5), Vector2i(1, 1), Vector2i(2, 2), Vector2i(0, 16), Vector2i(1, 1), Vector2i(2, 2),
	Vector2i(0, 14), Vector2i(1, 1), Vector2i(2, 2), Vector2i(1, 1), Vector2i(0, 10),
]
const OPEN_D1_MOUTH: Array[Vector2i] = [
	Vector2i(0, 75), Vector2i(3, 43), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 11),
]
## `npc_1_to_deck_d10_tex_index` (79 frames; the mouth type is 0).
const TO_DECK_EYE: Array[Vector2i] = [
	Vector2i(0, 36), Vector2i(1, 1), Vector2i(2, 2), Vector2i(0, 34), Vector2i(1, 1), Vector2i(2, 2),
	Vector2i(0, 3),
]
## `npc_1_keitai_talk10_tex_index` / `npc_1_keitai_talk11_tex_index` (15 frames).
const KEITAI_TALK1_EYE: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 5), Vector2i(1, 1), Vector2i(0, 7),
]
const KEITAI_TALK1_MOUTH: Array[Vector2i] = [Vector2i(0, 7), Vector2i(1, 1), Vector2i(2, 7)]

## `eye_seq_type` of each clip that is not a fixed sequence: `aNPC_EYE_TEX0` holds eye0
## (the stop index is 0 for all of these), `aNPC_EYE_TEX1` blinks.
const HOLD_EYE_CLIPS: PackedStringArray = [
	"sitdown_d1", "standup_d1", "open_d2", "keitai_on1", "keitai_off1",
]

## Clip name (`npc_1_<name>`, any prefix) → `{ eye: Eye, eye_seq, mouth_seq }`; empty when
## the clip has no rule of its own (blink / flap as usual, or a manpu emote).
static func for_clip(clip: String) -> Dictionary:
	var key: String = clip.rsplit("npc_1_", true, 1)[-1]
	match key:
		"open_d1":
			return {"eye": Eye.FIXED, "eye_seq": OPEN_D1_EYE, "mouth_seq": OPEN_D1_MOUTH}
		"to_deck_d1":
			return {"eye": Eye.FIXED, "eye_seq": TO_DECK_EYE, "mouth_seq": []}
		"keitai_talk1":
			return {"eye": Eye.FIXED, "eye_seq": KEITAI_TALK1_EYE, "mouth_seq": KEITAI_TALK1_MOUTH}
	if key in HOLD_EYE_CLIPS:
		return {"eye": Eye.HOLD, "eye_seq": [], "mouth_seq": []}
	return {}


## `seq[frame − 1]` for a run-length sequence; `index` is the 0-based clip frame and clamps
## to the last entry (a STOP clip holds its final frame).
static func pattern_at(runs: Array, index: int) -> int:
	var left: int = maxi(index, 0)
	var last: int = 0
	for run: Vector2i in runs:
		last = run.x
		if left < run.y:
			return run.x
		left -= run.y
	return last
