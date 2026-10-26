class_name TugOfWar
extends EventCrew

## The Sports Fair tug-of-war (`ac_tunahiki_control`, `ac_tunahiki_npc0/1`): one shared rope.
## Each one-second pull cycle the pullers heave at 0.2 s (the rope shakes and moves at `speed`)
## and ease off at 0.8 s, when the next pull is rolled: 45% one way, 45% the other, 10% a
## stand-off. The rope base stays within ±10 GX (0.5 m); a side being dragged more than 5 GX hangs on
## (`YURI`), a side winning by more than that throws its weight (`FURI`), otherwise they pull
## together (`AIKO`). One per tug, shared by the referee and pullers (an `EventCrew`); it steps
## the rope itself, before they read it each frame.

## The 30-frame cycle with its heave on frame 6 and ease-off on frame 24, in seconds.
const CYCLE := 30.0 / DecompTime.FRAME_HZ
const HEAVE_AT := 6.0 / DecompTime.FRAME_HZ
const EASE_AT := 24.0 / DecompTime.FRAME_HZ
## Lengths in metres, from the decomp's GX.
const GX := FieldCatalog.GX_TO_METERS
const LIMIT := 10.0 * GX
const SHAKE := 0.3 * GX
## The shake flips side every 1/30 s frame.
const SHAKE_HZ := DecompTime.FRAME_HZ
## `rope_base += speed · 0.025` GX a frame: metres a second per unit of `speed`.
const PULL_RATE := 0.025 * GX * DecompTime.FRAME_HZ
const LEAD := 5.0 * GX
## `aTNN1_think_init_proc`: pullers stand 85 / 95 GX in from their units, 5 GX off the line.
const PULLER_IN: Array[float] = [0.0, 85.0 * GX, 95.0 * GX, 95.0 * GX, 85.0 * GX]
const PULLER_Z := 5.0 * GX
## `aTNN0_birth`: the rope at the referee's unit + (20, 45) GX; the referee steps to + (20, −30).
const ROPE_OFFSET := Vector2(20.0, 45.0) * GX
const REFEREE_OFFSET := Vector2(20.0, -30.0) * GX
const CLIP_AIKO := "npc_1_tunahiki_aiko1"
const CLIP_YURI := "npc_1_tunahiki_yuri1"
const CLIP_FURI := "npc_1_tunahiki_furi1"
const CLIP_REFEREE := "npc_1_hatafuri1"

## Metres off the line: where the pull has dragged the rope, and that plus the shake.
var rope_base: float = 0.0
var rope: float = 0.0
## The pull, in the decomp's units (3–23).
var speed: float = 0.0
var next_speed: float = 0.0
var shake: bool = false
## Seconds into the pull cycle.
var time: float = 0.0
var rng := RandomNumberGenerator.new()


## The tug under `host`, made on first use. Pair with `leave`.
static func join(host: Node) -> TugOfWar:
	return gather(host, &"TugOfWar", func() -> Node: return TugOfWar.new()) as TugOfWar


func _init() -> void:
	## Ahead of the pullers' physics step, so they read this frame's rope.
	process_physics_priority = -1
	rng.randomize()


func _physics_process(delta: float) -> void:
	advance(delta, rng)


## +1 for the west team (slots 1, 2), −1 for the east (3, 4).
static func dir_of(slot: int) -> int:
	return 1 if ((slot - 1) & 2) == 0 else -1


## `delta` seconds of `aTNC_wait` and the pullers' checks, split at the heave and the ease-off.
func advance(delta: float, roll: RandomNumberGenerator) -> void:
	var left: float = delta
	while left > 0.0:
		var mark: float = HEAVE_AT if time < HEAVE_AT else (EASE_AT if time < EASE_AT else CYCLE)
		var dt: float = minf(left, mark - time)
		if shake:
			rope_base += speed * PULL_RATE * dt
			if absf(rope_base) > LIMIT:
				rope_base = clampf(rope_base, -LIMIT, LIMIT)
				speed = 0.0
		time += dt
		left -= dt
		if time >= mark:
			_reach(mark, roll)
	var wobble: float = 0.0
	if shake:
		wobble = SHAKE if int(time * SHAKE_HZ) % 2 == 0 else -SHAKE
	rope = rope_base + wobble


func _reach(mark: float, roll: RandomNumberGenerator) -> void:
	if mark == HEAVE_AT:
		shake = true
		speed = next_speed
	elif mark == EASE_AT:
		shake = false
		var r: float = roll.randf()
		if r < 0.45:
			next_speed = roll.randf_range(0.0, 20.0) + 3.0
		elif r < 0.9:
			next_speed = -(roll.randf_range(0.0, 20.0) + 3.0)
		else:
			next_speed = 0.0
	else:
		time = 0.0


## `aTNN1_aiko`'s end-of-clip choice for a puller on side `dir`.
func clip_for(dir: int) -> String:
	var lead: float = -(rope_base * float(dir))
	if lead > LEAD:
		return CLIP_YURI
	if lead < -LEAD and next_speed * float(dir) >= 0.0:
		return CLIP_FURI
	return CLIP_AIKO


## Where a puller stands relative to its map unit, in metres (x, z).
static func puller_offset(slot: int) -> Vector2:
	var d: int = dir_of(slot)
	return Vector2(float(d) * PULLER_IN[clampi(slot, 0, 4)], float(d) * PULLER_Z)
