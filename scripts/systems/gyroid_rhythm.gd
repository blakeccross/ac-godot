class_name GyroidRhythm
extends RefCounted

## How a switched-on gyroid keeps time (`ac_hnw_common.c` `aFTR_HNW_STATE_ON`). The game
## reads an animation counter from the rhythm group (`Na_GetRhythmAnimCounter`, 0 → 1 over
## each step) and poses the gyroid's own clip at `counter * (frames - 1) + 1`; every wrap of
## the counter flips a flag. Six gyroids run their clip twice a step, the plinkoids once
## over two steps.
##
## The rhythm group runs at 120 BPM until room music sets its tempo
## (`Na_SetRhythmInfo`), which is the pace used here. The rhythm sequence's own sounds
## (seq 246) are not rendered by the pipeline yet, so gyroids dance without their voices.

## `FTR_HNW_COMMON000`: the first gyroid's furniture number.
const FIRST_FTR := 0x16C
const COUNT := 127
const BPM := 120.0
## Steps per beat at the default beat type (24 of 48 tatums: `Na_RhythmGrpProcess`).
const STEPS_PER_BEAT := 2.0
## Tall oombloid, sputnoid, mini bowtoid, bowtoid, mega timpanoid, mini puffoid.
const TWICE := [7, 12, 38, 39, 48, 89]
## Mega plinkoid, plinkoid, mini plinkoid.
const HALVED := [121, 122, 123]


## The gyroid number (0–126) of furniture `ftr_index`, or -1.
static func haniwa_index(ftr_index: int) -> int:
	var i: int = ftr_index - FIRST_FTR
	return i if i >= 0 and i < COUNT else -1


## Steps played after `seconds` switched on.
static func steps(seconds: float, bpm: float = BPM) -> float:
	return maxf(seconds, 0.0) * bpm / 60.0 * STEPS_PER_BEAT


## 0 → 1 position in the clip after `step_count` steps.
static func counter(step_count: float, haniwa_idx: int) -> float:
	var c: float = fposmod(step_count, 1.0)
	if TWICE.has(haniwa_idx):
		return (c - 0.5) * 2.0 if c >= 0.5 else c * 2.0
	if HALVED.has(haniwa_idx):
		## `dynamic_work_s[0]` flips on every wrap.
		var flip: int = int(floor(step_count)) % 2
		return c * 0.5 + (0.5 if flip == 1 else 0.0)
	return c


## Clip time for `counter` on a clip of `frames` frames (`cKF` frames from 1).
static func clip_frame(c: float, frames: float) -> float:
	return c * maxf(frames - 1.0, 0.0) + 1.0
