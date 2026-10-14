class_name TugOfWar
extends RefCounted

## The Sports Fair tug-of-war (`ac_tunahiki_control`, `ac_tunahiki_npc0/1`): one shared rope.
## Each pull cycle the pullers heave at frame 6 (the rope shakes and moves at `speed`) and ease
## off at 24, when the next pull is rolled: 45% one way, 45% the other, 10% a stand-off. The
## rope base stays within ±10 GX; a side being dragged more than 5 GX hangs on (`YURI`), a side
## winning by more than that throws its weight (`FURI`), otherwise they pull together (`AIKO`).
## Not an autoload; the pullers drive it once per frame.

const CYCLE := 30
const HEAVE_FRAME := 6
const EASE_FRAME := 24
const LIMIT_GX := 10.0
const SHAKE_GX := 0.3
const LEAD_GX := 5.0
## `aTNN1_think_init_proc`: pullers stand 85 / 95 GX in from their units, 5 GX off the line.
const PULLER_IN_GX := [0.0, 85.0, 95.0, 95.0, 85.0]
const PULLER_Z_GX := 5.0
## `aTNN0_birth`: the rope at the referee's unit + (20, 45); the referee steps to + (20, −30).
const ROPE_OFS_GX := Vector2(20.0, 45.0)
const REFEREE_OFS_GX := Vector2(20.0, -30.0)
const CLIP_AIKO := "npc_1_tunahiki_aiko1"
const CLIP_YURI := "npc_1_tunahiki_yuri1"
const CLIP_FURI := "npc_1_tunahiki_furi1"
const CLIP_REFEREE := "npc_1_hatafuri1"

static var rope_base: float = 0.0
static var rope: float = 0.0
static var speed: float = 0.0
static var next_speed: float = 0.0
static var shake: bool = false
static var frame: int = 0
static var _odd: bool = false
static var _steps := FrameStepper.new(DecompTime.FRAME_HZ, 4.0)
static var _last_engine_frame: int = -1


static func reset() -> void:
	rope_base = 0.0
	rope = 0.0
	speed = 0.0
	next_speed = 0.0
	shake = false
	frame = 0
	_odd = false
	_steps = FrameStepper.new(DecompTime.FRAME_HZ, 4.0)
	_last_engine_frame = -1


## +1 for the west team (slots 1, 2), −1 for the east (3, 4).
static func dir_of(slot: int) -> int:
	return 1 if ((slot - 1) & 2) == 0 else -1


## Once per engine frame, whoever calls first.
static func advance(delta: float, rng: RandomNumberGenerator) -> void:
	var now: int = Engine.get_process_frames()
	if now == _last_engine_frame:
		return
	_last_engine_frame = now
	_steps.add(delta)
	while _steps.next():
		step(rng)


## One game frame (`aTNC_wait` + the pullers' frame checks).
static func step(rng: RandomNumberGenerator) -> void:
	frame = (frame + 1) % CYCLE
	if frame == HEAVE_FRAME:
		shake = true
		speed = next_speed
	elif frame == EASE_FRAME:
		shake = false
		var r: float = rng.randf()
		if r < 0.45:
			next_speed = rng.randf_range(0.0, 20.0) + 3.0
		elif r < 0.9:
			next_speed = -(rng.randf_range(0.0, 20.0) + 3.0)
		else:
			next_speed = 0.0
	_odd = not _odd
	var wobble: float = 0.0
	if shake:
		wobble = SHAKE_GX if _odd else -SHAKE_GX
		rope_base += speed * 0.025
		if absf(rope_base) > LIMIT_GX:
			rope_base = clampf(rope_base, -LIMIT_GX, LIMIT_GX)
			speed = 0.0
	rope = rope_base + wobble


## `aTNN1_aiko`'s end-of-clip choice for a puller on side `dir`.
static func clip_for(dir: int) -> String:
	var lead: float = -(rope_base * float(dir))
	if lead > LEAD_GX:
		return CLIP_YURI
	if lead < -LEAD_GX and next_speed * float(dir) >= 0.0:
		return CLIP_FURI
	return CLIP_AIKO


## Where a puller stands relative to its map unit, in GX (x, z).
static func puller_offset(slot: int) -> Vector2:
	var d: int = dir_of(slot)
	return Vector2(float(d) * float(PULLER_IN_GX[clampi(slot, 0, 4)]), float(d) * PULLER_Z_GX)
