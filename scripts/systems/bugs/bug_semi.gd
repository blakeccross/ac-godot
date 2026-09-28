class_name BugSemi
extends BugProgram

## `ac_ins_semi.c` — cicadas (robust / walker / evening / brown) and the bee.
## Sits 35 GX up a tree trunk (30 on a cedar) facing north; calm cicadas (patience < 50)
## cry after 60 quiet frames and, while not raining, jitter up to 0.4 GX on X every frame
## they cry. A shaken tree, an axe hit in the acre within 150 GX, a stopped net within
## 70 GX or a dig within 30 GX sends it off (AVOID) at 4 GX/frame, climbing ever faster,
## on a heading within ±67.5° of south. Released / timed-out ones leave off the player's
## facing ±60°.

enum { AVOID, LET_ESCAPE, WAIT }

const NET_SCARE := 70.0
const SCOOP_SCARE := 30.0
const AXE_SCARE := 150.0
const CRY_TIMER := 60

var _placed: bool = false


func actor_init(a: BugActor, released: bool) -> void:
	match a.type:
		T_ROBUST_CICADA: a.item = 4
		T_WALKER_CICADA: a.item = 5
		T_EVENING_CICADA: a.item = 6
		T_BROWN_CICADA: a.item = 7
		T_BEE: a.item = 8
	if not released:
		BugProgram.cling_to_trunk(a)
		a.rot.x = PI * 0.5
		setup_action(a, WAIT)
	else:
		_placed = true
		setup_action(a, LET_ESCAPE)


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


# ---- setupAction ---------------------------------------------------

func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID:
			a.action_proc = _avoid
			_avoid_init(a)
		LET_ESCAPE:
			a.action_proc = _avoid
			_avoid_init(a)
			a.f_bit2 = true
		WAIT:
			a.action_proc = _wait
			a.rot.y = BugActor.TREE_FACE_YAW
			a.angle_y = 0.0  ## `world.angle.y` keeps its spawn 0: netted from the south side


## `aISM_avoid_init`: a scared cicada picks a heading within ±67.5° of south (never
## straight at the camera: ±22.5° either side is pushed out); a released / timed-out one
## goes off the player's facing ±60°.
func _avoid_init(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 80
	a.speed = 4.0
	a.max_velocity_y = 12.0
	a.gravity = 0.06
	a.rot.x = 0.0
	if a.action == AVOID:
		var r: float = a._rng.randf()
		var base: float = deg_to_rad(22.5) * (1.0 if r >= 0.5 else -1.0)
		a.rot.y = (r * deg_to_rad(90.0) - deg_to_rad(45.0)) + base
		a.angle_y = a.rot.y
	elif BugProgram.heading_from_player_facing(a, deg_to_rad(120.0)):
		a.rot.y = a.angle_y
	a.f_no_catch = true


# ---- actions -----------------------------------------------------

func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if not _placed:
		_placed = true
		BugProgram.settle_on_cedar(a, sense)
	if a.caught:
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2:
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _wait(a: BugActor, sense: BugActor.Sense) -> void:
	if _check_patience(a, sense):
		setup_action(a, AVOID)
		return
	## `aISM_IS_CAUGHT` (`s32_work0`): a net stopped on this cicada silences it.
	if a.type == T_BEE or a.s32_work[0] != 0:
		return
	if a.patience < 50.0:
		a.timer -= 1
		if not BugProgram.raining() and a.timer < 0:
			a.timer = 0
			a.pos.x = a.home.x + a._rng.randf() * 0.4
	else:
		a.timer = CRY_TIMER


func _avoid(a: BugActor, sense: BugActor.Sense) -> void:
	a.anime0 += 0.5
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0
	a.gravity = minf(a.gravity * 1.1, 12.0)
	## Ground / wall collision switches on once it has flown off its home unit.
	if a.bg_type == 0 and BugProgram.unit_of(sense, a.home) != BugProgram.unit_of(sense, a.pos):
		a.bg_type = 2


## `aISM_check_patience`: shaken tree → axe hit in the acre within 150 GX → stopped net
## within 70 GX → dig within 30 GX; scared over 90.
func _check_patience(a: BugActor, sense: BugActor.Sense) -> bool:
	if sense.tree_shaken_at(a.position):
		a.patience = 100.0
	elif BugProgram.vib_unit(a, sense) and a.player_distance_xz < AXE_SCARE:
		a.patience = 100.0
	elif _net_scare(a, sense):
		a.patience = 100.0
	elif BugProgram.near_xz(a, BugProgram.scoop_pos(sense), SCOOP_SCARE):
		a.patience = 100.0
	return a.patience > 90.0


func _net_scare(a: BugActor, sense: BugActor.Sense) -> bool:
	var net: Vector3 = BugProgram.net_stop_pos(sense)
	if net == Vector3.INF:
		return false
	if a.caught:
		a.s32_work[0] = 1
		return false
	return BugProgram.near_xz(a, net, NET_SCARE)
