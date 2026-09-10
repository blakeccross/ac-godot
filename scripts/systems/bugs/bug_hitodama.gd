class_name BugHitodama
extends BugProgram

## `ac_ins_hitodama.c` — the spirit / Wisp. Drifts very slowly (`FLY`, 0.3 GX/frame)
## in wide lazy curves toward an acre corner, bobbing gently (`fuwafuwa`). When
## caught or the ghost event ends it rises away (`AVOID` / LET_ESCAPE). Type 40 is
## level-Y, so the program drives `pos_speed.y`.

enum { AVOID, LET_ESCAPE, FLY }

const RANGE := 8.0 * 20.0        ## 8 units
const ANGL_ADD := [40.0, 56.0, 80.0, 104.0]
const MOVE_TIM := [240, 360, 480, 600]

var _frame: int = 0


func actor_init(a: BugActor, released: bool) -> void:
	a.bg_type = 2
	a.bg_range = 20.0
	a.item = -1
	if not released:
		a.pos.y = a.home.y
		a.home.y = a.pos.y
		a.angle_y = a._rng.randf_range(-PI, PI)
		_set_move_info(a)
		a.s32_work[3] = a._rng.randi_range(0, 65535)   ## bob angle
		a.continue_timer = a._rng.randi_range(0, 4)
		a.f32_work[0] = a.home.x + RANGE               ## target corner
		a.f32_work[1] = a.home.z + RANGE
		setup_action(a, FLY)
	else:
		setup_action(a, AVOID)


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
			a.rot.x = 0.0
			a.speed = 1.5
			if not a.f_no_catch and a._last_player_gx != Vector3.INF:
				a.angle_y = BugProgram.angle_to(a._last_player_gx, a.pos) + a._rng.randf_range(-1.0, 1.0) * deg_to_rad(60.0)
			a.s32_work[3] = 0
			a.f_no_catch = true
			if action == LET_ESCAPE:
				a.f_bit2 = true
		FLY:
			a.action_proc = _fly
			a.flag = 0
			a.rot.x = 0.0


func _set_move_info(a: BugActor) -> void:
	_frame += 1
	var add: float = ANGL_ADD[_frame & 3]
	if a.s32_work[1] > 0:
		add = -add
	a.s32_work[1] = int(add)
	a.s32_work[2] = MOVE_TIM[(_frame >> 2) & 3]


func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	a.anime0 += 0.5
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0
	if a.caught:
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2:
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _fuwafuwa(a: BugActor, hard: bool) -> void:
	var dir: int = 0x400 if hard else (0x100 + a._rng.randi_range(0, 0x2FF))
	var grav: float = 13.0 if hard else 10.0
	var last: float = sin(a.s32_work[3] * S16) * 10.0
	a.s32_work[3] = (a.s32_work[3] + dir) & 0xFFFF
	var now: float = grav * sin(a.s32_work[3] * S16)
	a.pos_speed.y = a.gravity + (now - last)


func _fly(a: BugActor, _sense: BugActor.Sense) -> void:
	a.target_speed = 0.3
	a.speed_step = 0.1
	_fuwafuwa(a, false)
	## `calc_move_drt`: curve toward the corner; re-roll turn info near it / on approach.
	var d: float = BugProgram.dist_xz(a.pos, Vector3(a.f32_work[0], a.pos.y, a.f32_work[1]))
	if d > RANGE * 0.5:
		var to: float = BugProgram.angle_to(a.pos, Vector3(a.f32_work[0], a.pos.y, a.f32_work[1]))
		if absf(wrapf(a.angle_y - to, -PI, PI)) < deg_to_rad(22.5):
			_set_move_info(a)
	else:
		a.s32_work[2] -= 1
		if a.s32_work[2] < 0:
			_set_move_info(a)
	a.angle_y = wrapf(a.angle_y + a.s32_work[1] * S16, -PI, PI)
	a.rot.y = a.angle_y


func _avoid(a: BugActor, _sense: BugActor.Sense) -> void:
	_fuwafuwa(a, true)
	a.gravity += 0.1
