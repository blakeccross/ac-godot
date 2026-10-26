class_name FootRace
extends EventCrew

## The Sports Fair foot race (`ac_tokyoso_control`, `ac_tokyoso_npc0/1`). Two runners race
## four laps round the shrine while the other pair watch, then they swap. Each warms up
## (`WARMUP1`, 8 s), takes the line (`READY1`) while the starter loads and raises the
## pistol (`TAMAKOME1`, `YOUI1` for 3.8 s) and fires (`DON1`, `NA_SE_53`). A runner heads
## for a point 22–44° further round (`aTKC_clip_next_run`): 160–180 GX out on the outside lane,
## 35 GX in on the inside, now and then tripping (`KOKERU1`, `KOKERU_GETUP1`). After the last
## lap it runs for the finish; the first in cheers (`BANZAI1`), the second is spent (`TIRED1`),
## the watchers clap, and after 20 s the other pair goes.
##
## One `foot_race.tscn` per race, shared by its runners (an `EventCrew`): each `join`s it and
## `leave`s it, and the last to leave frees it. `PhaseTimer` times the warm-up, the line-up and the goal; the
## race itself ends when both runners `cross`.

## The race moved on; runners and the starter react to it.
signal phase_changed(phase: Phase)

enum Phase { WARMUP, READY, RACE, GOAL }

const SCENE := "res://features/events/actors/foot_race.tscn"
const LAP_NUM := 4
## 240, 115 and 600 frames at 30 fps.
const WARMUP_TIME := 240.0 * DecompTime.FRAME_SEC
const READY_TIME := 115.0 * DecompTime.FRAME_SEC
const GOAL_TIME := 600.0 * DecompTime.FRAME_SEC
## `aTKC_ANGLE_FOR_LAP_COMPLETION` (≈22°): each leg is one to two of these.
const LEG_ANGLE := 4000.0 / 65536.0 * TAU
## A trip now and then on a leg.
const TRIP_CHANCE := 0.04
## The shrine sits at the centre of unit (7, 7) of its acre.
const CENTER_UNIT := Vector2i(7, 7)
## Lengths in metres, from the decomp's GX.
const GX := FieldCatalog.GX_TO_METERS
## `aTKC_clip_next_run`: the finish, from the centre, per lane.
const FINISH := Vector2(220.0, -130.0) * GX
const FINISH_LANE := Vector2(-60.0, 60.0) * GX
## A runner's `aNPC` run speed (GX a frame) on the field: about 6 GX a frame is 4.5 m/s.
const RUN_MPS_PER_GX_FRAME := 0.75
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

var phase: Phase = Phase.WARMUP
## 0: slots 1 and 2 race; 1: slots 3 and 4.
var team: int = 0
## Per lane: angle travelled (radians), finished (0 no, 1 first, 2 second).
var travelled: Array[float] = [0.0, 0.0]
var finish: Array[int] = [0, 0]

@onready var _timer: Timer = $PhaseTimer


## The race under `host`, made on first use. Pair with `leave`.
static func join(host: Node) -> FootRace:
	return gather(host, &"FootRace", func() -> Node: return (load(SCENE) as PackedScene).instantiate()) as FootRace


func _ready() -> void:
	_enter(Phase.WARMUP)


func _enter(next: Phase) -> void:
	phase = next
	match next:
		Phase.WARMUP:
			_timer.start(WARMUP_TIME)
		Phase.READY:
			_timer.start(READY_TIME)
		Phase.RACE:
			travelled = [0.0, 0.0]
			finish = [0, 0]
		Phase.GOAL:
			_timer.start(GOAL_TIME)
	phase_changed.emit(next)


## `aTKC_*`: warm-up → line-up → race; after the goal the other pair goes.
func _on_phase_timer_timeout() -> void:
	match phase:
		Phase.WARMUP:
			_enter(Phase.READY)
		Phase.READY:
			_enter(Phase.RACE)
		Phase.GOAL:
			team = 1 - team
			_enter(Phase.WARMUP)


## Lane 0 (outside) or 1 (inside) for a runner slot.
static func lane_of(slot: int) -> int:
	return (slot - 1) & 1


static func team_of(slot: int) -> int:
	return 0 if slot <= 2 else 1


func racing(slot: int) -> bool:
	return slot > 0 and team_of(slot) == team


## A runner reached the finish; once both are in, the goal.
func cross(lane: int) -> void:
	if finish[lane] != 0:
		return
	finish[lane] = 2 if finish[1 - lane] != 0 else 1
	if finish[0] != 0 and finish[1] != 0:
		_enter(Phase.GOAL)


func done_laps(lane: int) -> bool:
	return travelled[lane] >= TAU * float(LAP_NUM)


## `aTKC_clip_next_run`: the next point round, from `angle` (radians, from the centre), and the
## run speed. Returns `[point_offset: Vector2 (metres), new_angle, speed (m/s)]`.
func next_leg(lane: int, angle: float, rng: RandomNumberGenerator) -> Array:
	var leg: float = LEG_ANGLE + rng.randf_range(0.0, LEG_ANGLE)
	var a: float = angle + leg
	## 160–180 GX out, 35 GX in on the inside lane; 4 + radius / 90 GX a frame, 0.5 less inside.
	var radius: float = (160.0 + rng.randf_range(0.0, 20.0) - float(lane) * 35.0) * GX
	var speed: float = (4.0 + radius / (90.0 * GX) - float(lane) * 0.5) * RUN_MPS_PER_GX_FRAME
	travelled[lane] += leg
	return [Vector2(cos(a), -sin(a)) * radius, a, speed]


static func finish_offset(lane: int) -> Vector2:
	return FINISH + FINISH_LANE * float(lane)
