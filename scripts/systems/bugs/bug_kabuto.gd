class_name BugKabuto
extends BugProgram

## `ac_ins_kabuto.c` — beetles (drone / dynastid / stag / jewel / longhorn / saw /
## mountain / giant). Clings 35 GX up a tree trunk (30 on a cedar) facing the trunk,
## shuffles ±4.2° (`aIKB_wait`), and on a shaken tree / an axe hit in the acre within
## 150 GX / a stopped net within 70 GX / a dig within 30 GX flies off the player's facing
## ±60° at 4 GX/frame, climbing ever faster (`aIKB_avoid`, also the LET_ESCAPE proc).

enum { AVOID, LET_ESCAPE, WAIT }

## `angle_table` — ±175.78125° from north == ±4.21875° either side of due south.
const SWAY := deg_to_rad(4.21875)
const BALL_SCARE := 60.0
const NET_SCARE := 70.0
const SCOOP_SCARE := 30.0
const VIB_SCARE := 150.0
const MAX_PATIENCE := 90.0

var _placed: bool = false


func actor_init(a: BugActor, released: bool) -> void:
	match a.type:
		T_DRONE_BEETLE: a.item = 19
		T_DYNASTID_BEETLE: a.item = 20
		T_FLAT_STAG_BEETLE: a.item = 21
		T_JEWEL_BEETLE: a.item = 22
		T_LONGHORN_BEETLE: a.item = 23
		T_SAW_STAG_BEETLE: a.item = 29
		T_MOUNTAIN_BEETLE: a.item = 30
		T_GIANT_BEETLE: a.item = 31
	if not released:
		## `GetBgY_OnlyCenter_FromWpos2(pos, -climb)` puts us `climb` GX up the trunk; the
		## cedar variant is settled on the first frame, once the FG is known.
		BugProgram.cling_to_trunk(a)
		a.rot.x = PI * 0.5           ## `shape_info.rotation.x = 90°`
		a.rot.y = -BugActor.TREE_FACE_YAW
		a.angle_y = 0.0  ## `world.angle.y` keeps its spawn 0: netted from the south side
		a.s32_work[3] = 0
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
		AVOID, LET_ESCAPE:
			a.action_proc = _avoid
			_avoid_init(a)
		WAIT:
			a.action_proc = _wait
			_wait_init(a)


func _avoid_init(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 80
	a.gravity = 0.06
	a.max_velocity_y = 12.0
	a.speed = 4.0
	a.rot.x = 0.0
	## `player->shape_info.rotation.y + (rand − 0.5)·120°`, scared or released alike.
	if BugProgram.heading_from_player_facing(a, deg_to_rad(120.0)):
		a.rot.y = a.angle_y
	a.f_no_catch = true
	a.f_bit2 = true


func _wait_init(a: BugActor) -> void:
	## Only the shape turns: `world.angle.y` stays 0, the catch-range facing.
	a.rot.y = -BugActor.TREE_FACE_YAW


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
	## `aIKB_wait` leg-shuffle: chase ±4.2° a few times, hold 30f, pause 20-40f.
	if a.s32_work[0] == 0:
		## `angle_table[timer1 & 1]`: +175.78125°, −175.78125°.
		var target: float = (PI - SWAY) if (a.s32_work[1] & 1) == 0 else (-PI + SWAY)
		a.rot.y = BugProgram.chase_angle(a.rot.y, target, 128 * MLib.S16)
		if a.s32_work[2] == 0:
			if a.s32_work[1] == 0:
				a.s32_work[0] = int((10.0 + a._rng.randf() * 10.0) * 2.0)
				a.s32_work[1] = 3 + a._rng.randi_range(0, 1)
			else:
				a.s32_work[1] -= 1
			a.s32_work[2] = 30
		else:
			a.s32_work[2] -= 1
	else:
		a.s32_work[0] -= 1


func _avoid(a: BugActor, sense: BugActor.Sense) -> void:
	a.anime0 += 0.5
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0
	a.gravity = minf(a.gravity * 1.1, 12.0)
	## `aIKB_avoid`: ground / wall collision switches on once it has flown off its home unit.
	if a.bg_type != 2 and BugProgram.unit_of(sense, a.home) != BugProgram.unit_of(sense, a.pos):
		a.bg_type = 2


## `aIKB_check_patience`: shaken tree → axe hit in the acre within 150 GX → stopped net
## within 70 GX → dig within 30 GX; scared over 90.
func _check_patience(a: BugActor, sense: BugActor.Sense) -> bool:
	if sense.tree_shaken_at(a.position):
		a.patience = 100.0
	elif BugProgram.vib_unit(a, sense) and a.player_distance_xz < VIB_SCARE:
		a.patience = 100.0
	elif not a.caught and BugProgram.near_xz(a, BugProgram.net_stop_pos(sense), NET_SCARE):
		a.patience = 100.0
	elif BugProgram.near_xz(a, BugProgram.scoop_pos(sense), SCOOP_SCARE):
		a.patience = 100.0
	return a.patience > MAX_PATIENCE
