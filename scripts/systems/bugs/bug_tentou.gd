class_name BugTentou
extends BugProgram

## `ac_ins_tentou.c` — ladybug, spotted ladybug, mantis and snail. They sit 25 GX over
## the ground (on the flower head), rest 90–180 frames, then crawl a ±14 GX box for
## 90–149 frames (0.4 GX/frame, the snail a quarter of that), turning at random and
## bouncing off the box edge. A stopped net within 70 GX or a dig within 60 GX sends a
## ladybug / mantis off the player's facing ±60°, climbing ever faster (US: leaving the
## flower does not scare them — that check is AUS-only). The snail only reacts to its
## unit losing its flower: it drops to the ground and crawls away, sliding along walls.

enum { AVOID, AVOID_MAIMAI, LET_ESCAPE, LET_ESCAPE_MAIMAI, MOVE, WAIT }

## `ref_angl[]` (`aITT_move`) — target yaw per box-edge collision bitmask, s16→rad.
const FLOWER_Y := 25.0       ## `6 + GetBgY_OnlyCenter_FromWpos(pos, −19)`
const NET_SCARE := 70.0
const SCOOP_SCARE := 60.0

const REF_ANGL := [
	0.0, deg_to_rad(90.0), deg_to_rad(-90.0), 0.0,
	0.0, deg_to_rad(45.0), deg_to_rad(-45.0), 0.0,
	deg_to_rad(180.0), deg_to_rad(135.0), deg_to_rad(-135.0), deg_to_rad(180.0),
	deg_to_rad(90.0), deg_to_rad(90.0), deg_to_rad(-90.0), 0.0,
]


func actor_init(a: BugActor, released: bool) -> void:
	a.bg_type = 2
	match a.type:
		T_LADYBUG: a.item = 24
		T_SPOTTED_LADYBUG: a.item = 25
		T_MANTIS: a.item = 26
		T_SNAIL: a.item = 32
	if not released:
		a.pos.y = a.home.y + FLOWER_Y
		a.home = a.pos
		setup_action(a, WAIT)
	elif a.type == T_SNAIL:
		a.home.y = a.pos.y
		setup_action(a, LET_ESCAPE_MAIMAI)
	else:
		setup_action(a, LET_ESCAPE)


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


func on_release(a: BugActor) -> void:
	setup_action(a, LET_ESCAPE_MAIMAI if a.type == T_SNAIL else LET_ESCAPE)


# ---- setupAction ------------------------------------------------

func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID, LET_ESCAPE:
			a.action_proc = _avoid
			_avoid_init(a)
			if action == LET_ESCAPE:
				a.f_bit2 = true
		AVOID_MAIMAI, LET_ESCAPE_MAIMAI:
			a.action_proc = _avoid_maimai
			_avoid_maimai_init(a)
			if action == LET_ESCAPE_MAIMAI:
				a.f_bit2 = true
		MOVE:
			a.action_proc = _move
			_move_init(a)
		WAIT:
			a.action_proc = _wait
			a.timer = int((90.0 + a._rng.randf() * 90.0) * 2.0)
			a.speed = 0.0
			a.speed_step = 0.0


func _avoid_init(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 80
	a.speed = 4.0
	a.max_velocity_y = 12.0
	a.gravity = 0.06
	a.rot.x = 0.0
	if BugProgram.heading_from_player_facing(a, deg_to_rad(120.0)):
		a.rot.y = a.angle_y
	a.f_no_catch = true
	a.f_bit2 = true


func _avoid_maimai_init(a: BugActor) -> void:
	_avoid_init(a)
	a.gravity = 2.0
	a.max_velocity_y = -20.0
	a.speed = 0.2
	a.target_speed = 0.2
	a.speed_step = 0.05
	a.f_bit4 = false


func _move_init(a: BugActor) -> void:
	a.timer = int((90.0 + float(a.game_frame % 60)) * 2.0)
	a.s32_work[2] = 0                ## turn delay
	a.target_speed = 0.4
	a.speed_step = 0.1
	if a.type == T_SNAIL:
		a.target_speed *= 0.25
		a.speed_step *= 0.25


# ---- actions --------------------------------------------------

func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	## US `aITT_actor_move` sends a caught snail down the flying LET_ESCAPE (a bug fixed in
	## the AUS release); the port keeps the fix so a snail never takes off.
	if a.caught:
		setup_action(a, LET_ESCAPE_MAIMAI if a.type == T_SNAIL else LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2:
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _wait(a: BugActor, sense: BugActor.Sense) -> void:
	if _check_patience(a, sense):
		return
	if a.timer <= 0:
		setup_action(a, MOVE)
	else:
		a.timer -= 1


func _move(a: BugActor, sense: BugActor.Sense) -> void:
	if _check_patience(a, sense):
		return
	if a.timer <= 0:
		setup_action(a, WAIT)
		return
	a.timer -= 1
	var dx: float = a.pos.x - a.home.x
	var dz: float = a.pos.z - a.home.z
	var collision: int = 0
	if absf(dx) >= 15.0:
		if dx < 0.0:
			a.pos.x = a.home.x - 14.0
			collision = 1
		else:
			a.pos.x = a.home.x + 14.0
			collision = 2
	if absf(dz) >= 15.0:
		if dz < 0.0:
			a.pos.z = a.home.z - 14.0
			collision |= 4
		else:
			a.pos.z = a.home.z + 14.0
			collision |= 8
	a.pos.y = BugProgram.center_y(sense, a.pos, a.home.y - FLOWER_Y) + FLOWER_Y
	if collision != 0:
		a.s32_work[1] = int(REF_ANGL[collision] / MLib.S16)
		a.s32_work[2] = 10
		a.speed_step = 0.0
		a.speed = 0.0
	elif BugProgram.angle_reached(a.angle_y, a.s32_work[1] * MLib.S16):
		a.s32_work[1] = int(a.angle_y / MLib.S16) + int(a._rng.randf_range(-1.0, 1.0) * deg_to_rad(90.0) / MLib.S16)
	var step: float = (0x180 if a.type == T_SNAIL else 0x600) * MLib.S16
	a.angle_y = BugProgram.chase_angle(a.angle_y, a.s32_work[1] * MLib.S16, step)
	a.rot.y = a.angle_y
	if a.s32_work[2] == 0:
		a.speed_step = 0.1
	else:
		a.s32_work[2] -= 1


func _avoid(a: BugActor, _sense: BugActor.Sense) -> void:
	a.anime0 += 0.5
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0
	a.gravity = minf(a.gravity * 1.1, 12.0)


func _avoid_maimai(a: BugActor, sense: BugActor.Sense) -> void:
	## `aITT_calc_direction_angl`: a front wall turns it to run along the wall (90° off
	## the wall's facing); the shape follows at 0x800.
	if BugProgram.wall_front(a, sense):
		a.angle_y = wrapf(PI * 0.5 + BugProgram.wall_normal(a), -PI, PI)
	a.rot.y = BugProgram.chase_angle(a.rot.y, a.angle_y, 0x800 * MLib.S16)


## `aITT_check_patience`: the snail only leaves when its unit has no flower; the others
## flee a stopped net within 70 GX (not the one holding them) or a dig within 60 GX.
func _check_patience(a: BugActor, sense: BugActor.Sense) -> bool:
	if a.type == T_SNAIL:
		if not BugProgram.on_flower(a, sense):
			setup_action(a, AVOID_MAIMAI)
			a.target_speed = 0.1
			a.speed_step = 0.025
			return true
		return false
	if not a.caught and BugProgram.near_xz(a, BugProgram.net_stop_pos(sense), NET_SCARE):
		a.patience = 100.0
	elif BugProgram.near_xz(a, BugProgram.scoop_pos(sense), SCOOP_SCARE):
		a.patience = 100.0
	if a.patience > 90.0:
		setup_action(a, AVOID)
		return true
	return false
