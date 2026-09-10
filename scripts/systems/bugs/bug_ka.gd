class_name BugKa
extends BugProgram

## `ac_ins_ka.c` — mosquito. Drifts and buzzes (`FLY`); when the player is in its
## acre and within 60 GX of its height it homes in (`SEARCH`), hovers at the player
## (`ATTACK_WAIT`) for 180 frames, then bites (`ATTACK`) and flies off. Type 39 is
## level-Y, so `fuwafuwa` drives the vertical bob.
##
## The bite is surfaced via `a.flag = BIT` for the game layer to apply damage /
## let the player swat.

enum { AVOID, LET_ESCAPE, FLY, SEARCH, ATTACK_WAIT, ATTACK }

const ATTACK_DIST := 10.0     ## `mFI_UNIT_BASE_SIZE_F / 2`
const ATTACK_TIME := 180
const BIT := 99


func actor_init(a: BugActor, released: bool) -> void:
	a.bg_range = 6.0
	a.bg_height = -14.0
	a.bg_type = 1
	a.item = 39
	if not released:
		a.pos.y = a.home.y + 30.0
		a.home = a.pos
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
			if a._last_player_gx != Vector3.INF:
				a.angle_y = BugProgram.angle_to(a._last_player_gx, a.pos) + a._rng.randf_range(-1.0, 1.0) * deg_to_rad(60.0)
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
	var ang: int = a.s32_work[0]
	var last: float = a.f32_work[0] * sin(ang * S16)
	a.s32_work[0] = int(ang + 0x180) & 0xFFFF
	if (int(ang + 0x180) & 0xFFFF) < 32768 and ang >= 32768:
		pass
	if ((ang + 0x180) & 0x8000) != 0 and (ang & 0x8000) == 0:
		a.f32_work[0] = 10.0 + a._rng.randf() * 10.0
	var na: int = ang + 0x180
	var now: float = a.f32_work[0] * sin(na * S16)
	a.f32_work[1] = BugProgram.chase_f(a.f32_work[1], a.max_velocity_y, a.gravity * 0.5)
	a.pos_speed.y = a.f32_work[1] + (now - last)


func _in_reach(a: BugActor, sense: BugActor.Sense) -> bool:
	if not sense.has_player():
		return false
	return absf((sense.player_position.y / BugActor.GX_M) - a.pos.y) < 60.0


func _fly(a: BugActor, sense: BugActor.Sense) -> void:
	if sense != null and sense.bg.is_valid() and bool(sense.bg.call(a.pos).get("hit_wall_front", false)):
		a.angle_y = wrapf(a.angle_y + PI, -PI, PI)
		a.rot.y = a.angle_y
	if _in_reach(a, sense):
		setup_action(a, SEARCH)
	else:
		a.rot.y += 0x80 * S16
		a.angle_y = a.rot.y


func _search(a: BugActor, sense: BugActor.Sense) -> void:
	if not _in_reach(a, sense):
		setup_action(a, FLY)
		return
	var d: float = BugProgram.dist_xz(a.pos, sense.player_position / BugActor.GX_M)
	if d <= ATTACK_DIST:
		setup_action(a, ATTACK_WAIT)
		return
	var step: float = (0x100 if d <= 20.0 else 0x200) * S16
	var to_pl: float = BugProgram.angle_to(a.pos, sense.player_position / BugActor.GX_M)
	a.rot.y = BugProgram.chase_angle(a.rot.y, to_pl, step)
	a.angle_y = a.rot.y


func _attack_wait(a: BugActor, sense: BugActor.Sense) -> void:
	if not _in_reach(a, sense):
		setup_action(a, FLY)
		return
	if BugProgram.dist_xz(a.pos, sense.player_position / BugActor.GX_M) > ATTACK_DIST:
		setup_action(a, SEARCH)
		return
	var to_pl: float = BugProgram.angle_to(a.pos, sense.player_position / BugActor.GX_M)
	a.rot.y = BugProgram.chase_angle(a.rot.y, to_pl, 0x600 * S16)
	a.angle_y = a.rot.y
	a.s32_work[1] += 1
	if a.s32_work[1] > ATTACK_TIME:
		setup_action(a, ATTACK)


func _attack(a: BugActor, _sense: BugActor.Sense) -> void:
	## Deliver the bite once, then leave.
	a.flag = BIT
	setup_action(a, AVOID)


func _avoid(a: BugActor, _sense: BugActor.Sense) -> void:
	a.gravity = minf(a.gravity * 1.1, 12.0)
