class_name BugProgram
extends RefCounted

## Base for the 14 `aINS_PROGRAM_*` movement overlays (`ac_ins_*.c`). One instance
## per live `BugActor`. `BugActor` runs the shared per-frame framework
## (`aINS_actor_move`) then calls `actor_move()` here — the program's state machine
## (`*_actor_move` → `action_proc`). Subclasses live beside this file.
##
## Angles: decomp uses s16 (0..65535, wrapping). We keep radians; `S16` converts a
## decomp step (`0x800` etc.) to radians. Distances are GX unless noted.

const S16 := TAU / 65536.0
const GAME_FPS := 30.0

## `aINS_INSECT_TYPE_*` for readability inside the overlays.
const T_COMMON_BUTTERFLY := 0
const T_YELLOW_BUTTERFLY := 1
const T_TIGER_BUTTERFLY := 2
const T_PURPLE_BUTTERFLY := 3
const T_ROBUST_CICADA := 4
const T_WALKER_CICADA := 5
const T_EVENING_CICADA := 6
const T_BROWN_CICADA := 7
const T_BEE := 8
const T_COMMON_DRAGONFLY := 9
const T_RED_DRAGONFLY := 10
const T_DARNER_DRAGONFLY := 11
const T_BANDED_DRAGONFLY := 12
const T_LONG_LOCUST := 13
const T_MIGRATORY_LOCUST := 14
const T_CRICKET := 15
const T_GRASSHOPPER := 16
const T_BELL_CRICKET := 17
const T_PINE_CRICKET := 18
const T_DRONE_BEETLE := 19
const T_DYNASTID_BEETLE := 20
const T_FLAT_STAG_BEETLE := 21
const T_JEWEL_BEETLE := 22
const T_LONGHORN_BEETLE := 23
const T_LADYBUG := 24
const T_SPOTTED_LADYBUG := 25
const T_MANTIS := 26
const T_FIREFLY := 27
const T_COCKROACH := 28
const T_SAW_STAG_BEETLE := 29
const T_MOUNTAIN_BEETLE := 30
const T_GIANT_BEETLE := 31
const T_SNAIL := 32
const T_MOLE_CRICKET := 33
const T_POND_SKATER := 34
const T_BAGWORM := 35
const T_PILL_BUG := 36
const T_SPIDER := 37
const T_ANT := 38
const T_MOSQUITO := 39
const T_SPIRIT := 40


## Called once from `BugActor.create()` after shared setup. `released` mirrors
## `actor->actor_specific` (0 = field spawn, 1 = net release / `aINS_MAKE_EXIST`).
func actor_init(_a: BugActor, _released: bool) -> void:
	pass


## `mv_proc` — the per-frame state-machine entry. Default routes to `action_proc`.
func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


## Draw pose. `aINS_actor_draw`: `(int)insect->_1E0` (0 or 1) for most; overlays that
## keep a still idle return 0.
func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


## Net release (`aINS_make_actor` → `actor_specific = 1`). Default: mark terminal so
## `alpha_time` fades it out.
func on_release(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 0x50
	a.f_bit2 = true


## `*_setupAction`: switch action, install its `action_proc`, run its `*_init`.
## Subclasses override.
func setup_action(_a: BugActor, _action: int) -> void:
	pass


## True when the type flees at patience >= 90 rather than > 90 (flyers).
func flees_at_ninety(_a: BugActor) -> bool:
	return false


# ---- shared math (libultra / m_lib analogs) --------------------------------

## `chase_f`: move `cur` toward `target` by at most `step` (>= 0).
static func chase_f(cur: float, target: float, step: float) -> float:
	if cur < target:
		return minf(cur + step, target)
	if cur > target:
		return maxf(cur - step, target)
	return target


## `chase_angle`: radian analog of the s16 `chase_angle` — shortest-arc chase.
static func chase_angle(cur: float, target: float, step: float) -> float:
	var diff: float = wrapf(target - cur, -PI, PI)
	if absf(diff) <= step:
		return wrapf(target, -PI, PI)
	return wrapf(cur + signf(diff) * step, -PI, PI)


## `search_position_angleY(from, to)` — yaw that points from `from` toward `to`.
## Decomp yaw convention: +X = sin, +Z = cos (`pos_speed = speed * {sin, cos}`).
static func angle_to(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


## `atans_table(dz, dx)` in decomp order → radian yaw (dx = sin term, dz = cos term).
static func atans(dz: float, dx: float) -> float:
	return atan2(dx, dz)


static func dist_xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func deg2s(deg: float) -> float:
	## `DEG2SHORT_ANGLE2` then to radians == plain deg→rad, kept for provenance.
	return deg_to_rad(deg)


## `move_proc` for a HIDE/DUG state — the actor is a frozen point in the ground.
static func freeze_move(a: BugActor) -> void:
	a.last_pos = a.pos
	a.speed = 0.0
	a.pos_speed = Vector3.ZERO


# ---- factory --------------------------------------------------------------

static func create(program: int) -> BugProgram:
	match program:
		BugData.Program.CHOU:
			return BugChou.new()
		BugData.Program.BATTA:
			return BugBatta.new()
		BugData.Program.TONBO:
			return BugTonbo.new()
		BugData.Program.TENTOU:
			return BugTentou.new()
		BugData.Program.HOTARU:
			return BugHotaru.new()
		BugData.Program.SEMI:
			return BugSemi.new()
		BugData.Program.KABUTO:
			return BugKabuto.new()
		BugData.Program.GOKI:
			return BugGoki.new()
		BugData.Program.HITODAMA:
			return BugHitodama.new()
		BugData.Program.AMENBO:
			return BugAmenbo.new()
		BugData.Program.KA:
			return BugKa.new()
		BugData.Program.DANGO:
			return BugDango.new()
		BugData.Program.KERA:
			return BugKera.new()
		BugData.Program.MINO:
			return BugMino.new()
		_:
			return BugChou.new()
