class_name BugKa
extends BugProgram

## `ac_ins_ka.c` — mosquito. Circles slowly at 1.2 GX/frame 14 GX over the ground
## (`FLY`, turning 0x80 a frame, reversing off walls and the ground); when the player is
## in its acre and within 60 GX of its height it homes in (`SEARCH`, 0x200 a frame, 0x100
## within a unit), hovers at the player inside 20 GX (`ATTACK_WAIT`) for 180 frames,
## then bites (`ATTACK`) and flies off the player's facing ±60°. Type 39 is level-Y, so
## `fuwafuwa` drives the vertical bob.
##
## The bite is surfaced via `a.flag = BIT` for the game layer to apply damage /
## let the player swat.

enum { AVOID, LET_ESCAPE, FLY, SEARCH, ATTACK_WAIT, ATTACK }

const ATTACK_DIST := 0.5 * UNIT_GX     ## `mFI_UNIT_BASE_SIZE_F / 2`
const ATTACK_TIME := 180
const BIT := 99


func actor_init(a: BugActor, released: bool) -> void:
	a.bg_range = 6.0
	a.bg_height = -14.0
	a.bg_type = 1
	a.item = 39
	if not released:
		## `GetBgY_OnlyCenter_FromWpos(pos, 30)`: 30 GX under the ground; the BG check
		## (`bg_height` −14) lifts it to 14 GX over it.
		a.pos.y = a.home.y - 30.0
	a.home = a.pos
	if not released:
		setup_action(a, FLY)
	else:
		setup_action(a, LET_ESCAPE)


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


func on_release(a: BugActor) -> void:
	setup_action(a, LET_ESCAPE)


func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID, LET_ESCAPE:
			a.action_proc = _avoid
			a.life_time = 0
			a.alpha_time = 80
			a.gravity = 0.06
			a.max_velocity_y = 12.0
			a.speed = 4.0
			a.rot.x = 0.0
			a.f32_work[1] = a.pos_speed.y
			if BugProgram.heading_from_player_facing(a, deg_to_rad(120.0)):
				a.rot.y = a.angle_y
			a.f_no_catch = true
			a.f_bit2 = true
		FLY:
			a.action_proc = _fly
			a.speed = 1.2
		SEARCH:
			a.action_proc = _search
		ATTACK_WAIT:
			a.action_proc = _attack_wait
			a.s32_work[1] = 0
		ATTACK:
			a.action_proc = _attack
			a.speed = 0.0
			a.target_speed = 0.0
			a.speed_step = 0.0
			a.pos_speed.y = 0.0


func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if a.action != ATTACK:
		a.anime0 += 0.2
		if a.anime0 >= 2.0:
			a.anime0 -= 2.0
		_fuwafuwa(a)
	if a.caught:
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2 and a.action != LET_ESCAPE:
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _fuwafuwa(a: BugActor) -> void:
	## A sine bob of 10–20 GX amplitude (re-rolled at each crest) on top of a chased climb.
	var ang: int = a.s32_work[0]
	var na: int = ang + 0x180
	var last: float = a.f32_work[0] * sin(ang * MLib.S16)
	a.s32_work[0] = na & 0xFFFF
	if (na & 0x8000) != 0 and (ang & 0x8000) == 0:
		a.f32_work[0] = 10.0 + a._rng.randf() * 10.0
	var now: float = a.f32_work[0] * sin(na * MLib.S16)
	a.f32_work[1] = BugProgram.chase_f(a.f32_work[1], a.max_velocity_y, a.gravity * 0.5)
	a.pos_speed.y = a.f32_work[1] + (now - last)


## `aIKA_check_condition`: the player is in the mosquito's acre and within 60 GX of its
## height.
func _in_reach(a: BugActor, sense: BugActor.Sense) -> bool:
	if not a.has_player_info:
		return false
	if not BugProgram.in_home_acre(a, sense, a.player_pos):
		return false
	return absf(a.player_distance_y) < 60.0


func _fly(a: BugActor, sense: BugActor.Sense) -> void:
	## `aIKA_BGcheck`: a front wall or the ground turns it round.
	if BugProgram.wall_front(a, sense) or a.bg_on_ground:
		a.angle_y = wrapf(a.angle_y + PI, -PI, PI)
		a.rot.y = a.angle_y
	if _in_reach(a, sense):
		setup_action(a, SEARCH)
	else:
		a.rot.y = wrapf(a.rot.y + 0x80 * MLib.S16, -PI, PI)
		a.angle_y = a.rot.y


func _search(a: BugActor, sense: BugActor.Sense) -> void:
	if not _in_reach(a, sense):
		setup_action(a, FLY)
		return
	if a.player_distance_xz <= ATTACK_DIST:
		setup_action(a, ATTACK_WAIT)
		return
	var step: float = (0x100 if a.player_distance_xz <= UNIT_GX else 0x200) * MLib.S16
	a.rot.y = BugProgram.chase_angle(a.rot.y, a.player_angle_y, step)
	a.angle_y = a.rot.y


func _attack_wait(a: BugActor, sense: BugActor.Sense) -> void:
	if not _in_reach(a, sense):
		setup_action(a, FLY)
		return
	if a.player_distance_xz > ATTACK_DIST:
		setup_action(a, SEARCH)
		return
	a.rot.y = BugProgram.chase_angle(a.rot.y, a.player_angle_y, 0x600 * MLib.S16)
	a.angle_y = a.rot.y
	a.s32_work[1] += 1
	if a.s32_work[1] > ATTACK_TIME:
		setup_action(a, ATTACK)


func _attack(a: BugActor, _sense: BugActor.Sense) -> void:
	## The original holds here while the player plays the stung reaction
	## (`mPlib_request_main_stung_mosquito_type1`); there is no such player state yet, so
	## the bite lands at once and the mosquito leaves.
	a.flag = BIT
	setup_action(a, AVOID)


func _avoid(a: BugActor, _sense: BugActor.Sense) -> void:
	a.gravity = minf(a.gravity * 1.1, 12.0)
