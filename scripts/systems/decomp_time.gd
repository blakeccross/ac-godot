class_name DecompTime
extends RefCounted

## The two clock rates decomp numbers are written in. Use these instead of local 60 / 30
## constants so every port converts the same way.
##
## - A **tick** is one play-loop update (`game.frame_counter`), 1/60 s. Per-frame steps —
##   `add_calc`, brakes, `timer--`, `RANDOM(n)` rolls — run once per tick. Drive them with
##   `FrameStepper`; don't rescale them by `delta`, the results are not equivalent.
## - A **frame** is the original 30 fps frame, 1/30 s. cKF keyframes and clip event frames,
##   `speed` in GX per frame (`Actor_position_move` adds `0.5 · speed` per tick) and most
##   `*_FRAMES` / morph counts are authored at this rate. Animation GLBs are already baked
##   in seconds at this rate (`tools/asset_pipeline/ckf.py` `FPS`), so Godot clips play at
##   the right speed as is; only code that names a frame number needs `FRAME_HZ`.

const TICK_HZ := 60.0
const TICK_SEC := 1.0 / TICK_HZ
const FRAME_HZ := 30.0
const FRAME_SEC := 1.0 / FRAME_HZ
## Ticks per 30 fps frame.
const TICKS_PER_FRAME := TICK_HZ / FRAME_HZ


static func ticks_to_sec(ticks: float) -> float:
	return ticks * TICK_SEC


static func sec_to_ticks(sec: float) -> float:
	return sec * TICK_HZ


static func frames_to_sec(frames: float) -> float:
	return frames * FRAME_SEC


static func sec_to_frames(sec: float) -> float:
	return sec * FRAME_HZ
