class_name BallToss
extends RefCounted

## The Sports Fair ball toss (`ac_tamaire_npc0/1`). Slots 1 and 2 throw red at the west basket,
## 3 and 4 white at the east one. A thrower runs to a spot 70–90 GX from its basket, a bit round
## from where it stood (`aTMN1_Next_move`), scoops up three balls (`TAMAHIROI1`), turns and
## throws them one at a time (`TAMANAGE1`, the ball leaves the hand on frame 15), watches, has a
## look round (`KYORO1`, 124 frames) and goes again. Slot 0 cheers, walking between the teams
## and clapping. Not an autoload.

enum Step { RUN, PICK, TURN, THROW, WATCH, LOOK }

const BASKET_UNITS: Array[Vector2i] = [Vector2i(3, 8), Vector2i(12, 8)]
const CLIP_PICK := "npc_1_tamahiroi1"
const CLIP_THROW := "npc_1_tamanage1"
const CLIP_LOOK := "npc_1_kyoro1"
const CLIP_RUN := "npc_1_run1"
const CLIP_CLAP := "npc_1_clap1"
const BALLS := 3
const RELEASE_FRAME := 15.0
const LOOK_FRAMES := 124
const WATCH_FRAMES := 20


## Red (0) for slots 1–2, white (1) for 3–4.
static func team_of(slot: int) -> int:
	return 0 if ((slot - 1) & 2) == 0 else 1


## `aTMN1_Next_move`: a spot round the basket, `[angle, distance]` in radians / GX.
static func next_spot(basket_xz: Vector2, me_xz: Vector2, rng: RandomNumberGenerator) -> Vector2:
	var away: float = atan2(me_xz.x - basket_xz.x, me_xz.y - basket_xz.y)
	var turn: float = (rng.randf_range(0.0, 1500.0) + 2000.0) / 65536.0 * TAU
	if rng.randf() < 0.5:
		turn = -turn
	var angle: float = away + turn
	var dist: float = rng.randf_range(0.0, 20.0) + 70.0
	return basket_xz + Vector2(sin(angle), cos(angle)) * dist


## `eTamaire_ct` launch: elevation 67.5° + up to ~16°, speed 4.9–6.4 GX a frame.
static func launch_rise(rng: RandomNumberGenerator) -> float:
	return deg_to_rad(67.5) + rng.randf_range(0.0, 3000.0) / 65536.0 * TAU


static func launch_speed(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(0.0, 1.5) + 4.9
