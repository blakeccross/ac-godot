class_name FootRace
extends RefCounted

## The Sports Fair foot race (`ac_tokyoso_control`, `ac_tokyoso_npc0/1`). Two runners race
## four laps round the shrine while the other pair watch, then they swap. Each warms up
## (`WARMUP1`, 240 frames), takes the line (`READY1`) while the starter loads and raises the
## pistol (`TAMAKOME1`, `YOUI1` for 115 frames) and fires (`DON1`, `NA_SE_53`). A runner heads
## for a point 22–44° further round (`aTKC_clip_next_run`): 160–180 GX out on the outside lane,
## 35 GX in on the inside, now and then tripping (`KOKERU1`, `KOKERU_GETUP1`). After the last
## lap it runs for the finish; the first in cheers (`BANZAI1`), the second is spent (`TIRED1`),
## the watchers clap, and after 600 frames the other pair goes. Not an autoload.

enum Phase { WARMUP, READY, RACE, GOAL }

const LAP_NUM := 4
const WARMUP_FRAMES := 240
const READY_FRAMES := 115
const GOAL_FRAMES := 600
## `aTKC_ANGLE_FOR_LAP_COMPLETION` (≈22°): each leg is one to two of these.
const LEG_ANGLE := 4000.0 / 65536.0 * TAU
## A trip now and then on a leg.
const TRIP_CHANCE := 0.04
## The shrine sits at the centre of unit (7, 7) of its acre.
const CENTER_UNIT := Vector2i(7, 7)
## `aTKC_clip_next_run`: the finish, from the centre, per lane (GX).
const FINISH_GX := Vector2(220.0, -130.0)
const FINISH_LANE_GX := Vector2(-60.0, 60.0)
const CLIP_WARMUP := "npc_1_warmup1"
const CLIP_READY := "npc_1_ready1"
const CLIP_RUN := "npc_1_run1"
const CLIP_TRIP := "npc_1_kokeru1"
const CLIP_GETUP := "npc_1_kokeru_getup1"
const CLIP_WIN := "npc_1_banzai1"
const CLIP_LOSE := "npc_1_tired1"
const CLIP_CLAP := "npc_1_clap1"
const CLIP_LOAD := "npc_1_tamakome1"
const CLIP_SET := "npc_1_youi1"
const CLIP_FIRE := "npc_1_don1"

static var phase: int = Phase.WARMUP
static var timer: int = WARMUP_FRAMES
## 0: slots 1 and 2 race; 1: slots 3 and 4.
static var team: int = 0
## Per lane: angle travelled (radians), finished (0 no, 1 first, 2 second).
static var travelled: Array[float] = [0.0, 0.0]
static var finish: Array[int] = [0, 0]
static var _steps := FrameStepper.new(DecompTime.FRAME_HZ, 4.0)
static var _last_engine_frame: int = -1


static func reset() -> void:
	phase = Phase.WARMUP
	timer = WARMUP_FRAMES
	team = 0
	travelled = [0.0, 0.0]
	finish = [0, 0]
	_steps = FrameStepper.new(DecompTime.FRAME_HZ, 4.0)
	_last_engine_frame = -1


## Lane 0 (outside) or 1 (inside) for a runner slot.
static func lane_of(slot: int) -> int:
	return (slot - 1) & 1


static func team_of(slot: int) -> int:
	return 0 if slot <= 2 else 1


static func racing(slot: int) -> bool:
	return slot > 0 and team_of(slot) == team


## Once per engine frame, whoever calls first.
static func advance(delta: float) -> void:
	var now: int = Engine.get_process_frames()
	if now == _last_engine_frame:
		return
	_last_engine_frame = now
	_steps.add(delta)
	while _steps.next():
		step()


## One frame of `aTKC_*`.
static func step() -> void:
	match phase:
		Phase.WARMUP:
			timer -= 1
			if timer <= 0:
				phase = Phase.READY
				timer = READY_FRAMES
		Phase.READY:
			timer -= 1
			if timer <= 0:
				phase = Phase.RACE
				travelled = [0.0, 0.0]
				finish = [0, 0]
		Phase.RACE:
			if finish[0] != 0 and finish[1] != 0:
				phase = Phase.GOAL
				timer = GOAL_FRAMES
		Phase.GOAL:
			timer -= 1
			if timer <= 0:
				team = 1 - team
				phase = Phase.WARMUP
				timer = WARMUP_FRAMES


## A runner reached the finish.
static func cross(lane: int) -> void:
	if finish[lane] != 0:
		return
	finish[lane] = 2 if finish[1 - lane] != 0 else 1


static func done_laps(lane: int) -> bool:
	return travelled[lane] >= TAU * float(LAP_NUM)


## `aTKC_clip_next_run`: the next point round, from `angle` (radians, from the centre), and the
## run speed (GX a frame). Returns `[point_offset_gx: Vector2, new_angle, speed_gx]`.
static func next_leg(lane: int, angle: float, rng: RandomNumberGenerator) -> Array:
	var leg: float = LEG_ANGLE + rng.randf_range(0.0, LEG_ANGLE)
	var a: float = angle + leg
	var radius: float = 160.0 + rng.randf_range(0.0, 20.0) - float(lane) * 35.0
	var speed: float = 4.0 + radius / 90.0 - float(lane) * 0.5
	travelled[lane] += leg
	return [Vector2(cos(a), -sin(a)) * radius, a, speed]


static func finish_offset(lane: int) -> Vector2:
	return FINISH_GX + FINISH_LANE_GX * float(lane)
