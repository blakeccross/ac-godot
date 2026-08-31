class_name FishSize
extends RefCounted

## Per-size and per-species fish tables, transcribed from `ac_gyo_test.c` / `ac_gyo_kage.c`.
## Every array here is indexed by `FishData.SizeClass` unless it says otherwise. Not an
## autoload — `FishShadow` reads it.
##
## The originals are in GX per logic frame. Movement runs at 60 Hz (the authored dwell
## values are all multiplied by 2 on their way into a counter), so a speed converts with
## `GX_TO_METERS * GAME_FPS` and a frame count with `/ GAME_FPS`.

const GAME_FPS := 60.0
const GX := FieldCatalog.GX_TO_METERS
## The dwell tables are authored in 30 Hz frames and every site that loads one into a
## counter doubles it (`work0 = (100 + RANDOM_F(30)) * 2`, `bite_time * 2.0f`). Speeds and
## the escape / puff timers are already in mover frames and must *not* be scaled.
const AUTHORED_TICK_SCALE := 2.0

## `aGTT_speed`: the dart speed once a fish has committed to the bobber.
const SPEED_GX: Array[float] = [1.0, 1.25, 1.25, 1.5, 1.75, 2.0, 2.2, 2.2]
## `aGTT_back_speed`: backing off after a nibble. Negative — it swims away tail-first.
const BACK_SPEED_GX: Array[float] = [-0.38, -0.4, -0.42, -0.42, -0.45, -0.5, -0.7, -0.7]
## `aGTT_touch_count`: base frames between nibbles, before the `RANDOM2_F(30)` jitter.
const TOUCH_FRAMES: Array[int] = [19, 19, 19, 19, 20, 22, 24, 24]
const TOUCH_JITTER_FRAMES := 30.0
## `aGTT_touch`: `speed = back_speed + RANDOM2_F(0.2)`.
const BACK_SPEED_JITTER_GX := 0.2
## `aGTT_touch_distance`: how close counts as touching the bobber.
const TOUCH_DIST_GX: Array[float] = [12.0, 13.0, 15.0, 15.0, 20.0, 25.0, 30.0, 30.0]
## `aGYO_shadow_scale`: shadow length. The draw also scales X by 0.4, so a shadow is always
## 2.5x longer than it is wide. WHALE is 10.0 and deliberately absurd.
const SHADOW_SCALE: Array[float] = [0.3, 0.4, 0.5, 0.5, 0.6, 0.8, 1.2, 10.0]
## `aGTT_position_calc` `hosei`: how far behind the bobber the fish body sits once hooked.
const HOOK_TRAIL_GX: Array[float] = [-8.0, -10.0, -12.0, -12.0, -15.0, -20.0, -25.0, -25.0]
## `aGYO_shadow_scale` is multiplied by 0.02 to reach an actor scale, and the shadow art is
## 1000 GX square, so one scale unit is 20 GX of shadow length.
const SCALE_TO_GX := 0.02 * 1000.0
## Shadow X is scaled by 0.4 at draw time (`Matrix_scale(scale.x * 0.4, ...)`).
const SHADOW_ASPECT := 0.4

## `aGTT_search_Uki`: casting on top of a fish this close scares it off. Small fish are
## twitchier, so their bubble is *smaller* — they let you get closer before bolting.
const ESCAPE_DIST_SMALL_GX := 17.0
const ESCAPE_DIST_LARGE_GX := 22.0

## `aGYO_search_area` / `aGYO_search_angle` / `aGYO_bite_time`, normal rod row only. Indexed
## by `FishData.search_area` / `.bite_time`, not by size. The golden rod rows are omitted
## with the rest of the golden rod.
const SEARCH_AREA_GX: Array[float] = [40.0, 40.0, 40.0, 50.0, 60.0]
const SEARCH_ANGLE_DEG: Array[float] = [3.0, 7.0, 30.0, 50.0, 180.0]
const BITE_FRAMES: Array[float] = [10.0, 11.0, 12.0, 15.0, 45.0]

## `aGTT_touch_init`: nibbles before the fish is forced to commit.
const TOUCH_TRIES := 5
## `aGTT_touch`: `aGTT_random_check(4.0f)` — a 1-in-4 chance to commit on any approach.
const COMMIT_CHANCE := 4.0
## `aGTT_wait_init`: `work0 = (100 + RANDOM_F(30)) * 2`, `speed = -0.15 + RANDOM2_F(0.2)`.
const WAIT_FRAMES := 100.0
const WAIT_FRAMES_JITTER := 30.0
const DRIFT_SPEED_GX := -0.15
const DRIFT_JITTER_GX := 0.2
## `aGTT_escape_init`: bolt at 2.0 for 100 frames, easing off by 0.02 a frame.
const ESCAPE_SPEED_GX := 2.0
const ESCAPE_FRAMES := 100.0
const ESCAPE_DECAY_GX := 0.02
## `aGTT_swim_speed_check(gyo, 360.0f, 5.0f, 0.5f)`: cruise is half the dart speed, and the
## sweep angle advances 5 degrees per call at half rate.
const CRUISE_SPEED_GX := 0.5
const SWEEP_DEG_PER_FRAME := 2.5
## `aGTT_player_near`: a dashing player scares fish from 110 GX, a swung tool from 150.
const SCARE_DASH_GX := 110.0
const SCARE_TOOL_GX := 150.0
## `aGTT_Get_water_surface_position_y`: the shadow rides 8 GX under the surface.
const DEPTH_GX := 8.0

## `aGYO_prim_f`: the 20-entry LOD ramp that cross-fades the two shadow tiles. Reused here
## as the body-flex curve, since the pair of tiles it blends *is* the tail sway.
const PRIM_F: Array[int] = [
	51, 102, 153, 204, 255, 204, 153, 102, 51, 0,
	51, 102, 153, 204, 255, 204, 153, 102, 51, 0,
]
## `aGYO_2tile_texture_idx`: which two of the four shadow tiles each frame blends. The pair
## changes every 5 frames, so the 20-frame loop walks 0-3, 2-3, 2-1, 0-1.
const TILE_PAIRS: Array[Vector2i] = [
	Vector2i(0, 3), Vector2i(0, 3), Vector2i(0, 3), Vector2i(0, 3), Vector2i(0, 3),
	Vector2i(2, 3), Vector2i(2, 3), Vector2i(2, 3), Vector2i(2, 3), Vector2i(2, 3),
	Vector2i(2, 1), Vector2i(2, 1), Vector2i(2, 1), Vector2i(2, 1), Vector2i(2, 1),
	Vector2i(0, 1), Vector2i(0, 1), Vector2i(0, 1), Vector2i(0, 1), Vector2i(0, 1),
]
## `aGYO_position_move`: `fwork0` runs 19 down to 0 at `dec_step * 0.5` and wraps by +19, so
## each of the 20 entries is held two frames — a 38-frame swim loop.
const ANIM_FRAMES := 20
const ANIM_FRAME_HOLD := 2.0
const ANIM_LOOP_SECONDS := ANIM_FRAMES * ANIM_FRAME_HOLD / GAME_FPS
## `dec_step`: 1.0 for every size but WHALE, which is 0.0 and therefore never wiggles.
const WHALE_IS_STILL := true

## `aGYO_KAGE_actor_ct` / `_draw`: the puff a scared fish leaves behind lives 100 frames and
## its alpha is `(delete_timer * 0.5 - 10) * 6`, so it holds solid then fades over the last 40.
const PUFF_FRAMES := 100.0
const PUFF_ALPHA_BIAS := 10.0
const PUFF_ALPHA_GAIN := 6.0


static func _at(table: Array, size: FishData.SizeClass) -> Variant:
	return table[clampi(int(size), 0, table.size() - 1)]


static func speed(size: FishData.SizeClass) -> float:
	return gx_per_frame_to_mps(float(_at(SPEED_GX, size)))


static func back_speed(size: FishData.SizeClass) -> float:
	return gx_per_frame_to_mps(float(_at(BACK_SPEED_GX, size)))


static func cruise_speed() -> float:
	return gx_per_frame_to_mps(CRUISE_SPEED_GX)


static func escape_speed() -> float:
	return gx_per_frame_to_mps(ESCAPE_SPEED_GX)


static func touch_distance(size: FishData.SizeClass) -> float:
	return float(_at(TOUCH_DIST_GX, size)) * GX


static func touch_seconds(size: FishData.SizeClass) -> float:
	return float(_at(TOUCH_FRAMES, size)) * AUTHORED_TICK_SCALE / GAME_FPS


static func touch_jitter_seconds() -> float:
	return TOUCH_JITTER_FRAMES * AUTHORED_TICK_SCALE / GAME_FPS


static func back_speed_jitter() -> float:
	return gx_per_frame_to_mps(BACK_SPEED_JITTER_GX)


## Shadow footprint in meters: length along the facing, width across it.
static func shadow_size(size: FishData.SizeClass) -> Vector2:
	var length: float = float(_at(SHADOW_SCALE, size)) * SCALE_TO_GX * GX
	return Vector2(length * SHADOW_ASPECT, length)


static func hook_trail(size: FishData.SizeClass) -> float:
	return float(_at(HOOK_TRAIL_GX, size)) * GX


static func splash_escape_distance(size: FishData.SizeClass) -> float:
	var small: bool = size == FishData.SizeClass.XXS or size == FishData.SizeClass.XS
	return (ESCAPE_DIST_SMALL_GX if small else ESCAPE_DIST_LARGE_GX) * GX


static func search_distance(area_index: int) -> float:
	return SEARCH_AREA_GX[clampi(area_index, 0, SEARCH_AREA_GX.size() - 1)] * GX


static func search_half_angle(area_index: int) -> float:
	return deg_to_rad(SEARCH_ANGLE_DEG[clampi(area_index, 0, SEARCH_ANGLE_DEG.size() - 1)])


static func bite_seconds(bite_index: int) -> float:
	var frames: float = BITE_FRAMES[clampi(bite_index, 0, BITE_FRAMES.size() - 1)]
	return frames * AUTHORED_TICK_SCALE / GAME_FPS


## The `WAIT` dwell before a fish gives up holding station and swims.
static func wait_seconds(jitter01: float) -> float:
	var frames: float = WAIT_FRAMES + clampf(jitter01, 0.0, 1.0) * WAIT_FRAMES_JITTER
	return frames * AUTHORED_TICK_SCALE / GAME_FPS


static func depth() -> float:
	return DEPTH_GX * GX


static func gx_per_frame_to_mps(gx_per_frame: float) -> float:
	return gx_per_frame * GX * GAME_FPS


## Which of the 20 swim frames a shadow is on, given how long it has been swimming.
static func anim_frame(elapsed: float) -> int:
	if elapsed <= 0.0:
		return 0
	var frame: int = int(elapsed / ANIM_LOOP_SECONDS * float(ANIM_FRAMES))
	return posmod(frame, ANIM_FRAMES)


## The tile cross-fade at a given frame, 0–1. Drives the body flex in the shader.
static func body_blend(frame: int) -> float:
	return float(PRIM_F[posmod(frame, ANIM_FRAMES)]) / 255.0


static func tile_pair(frame: int) -> Vector2i:
	return TILE_PAIRS[posmod(frame, ANIM_FRAMES)]


## Escape-puff alpha at an age in seconds, 0–1. `(timer * 0.5 - 10) * 6` over 255.
static func puff_alpha(age: float) -> float:
	var timer: float = PUFF_FRAMES - age * GAME_FPS
	if timer <= 0.0:
		return 0.0
	var alpha: float = (timer * 0.5 - PUFF_ALPHA_BIAS) * PUFF_ALPHA_GAIN
	return clampf(alpha / 255.0, 0.0, 1.0)


static func puff_seconds() -> float:
	return PUFF_FRAMES / GAME_FPS
