class_name BugTonbo
extends BugProgram

## `ac_ins_tonbo.c` — dragonflies (common / red / darner / banded). Cruise in bursts
## at a hover height of ~52-62 GX, turning between bursts; dip to touch water; the
## red dragonfly perches on stakes/signs (`DUMMY_RESERVE` units). The banded
## dragonfly patrols a large area fast and leaves it when it strays too far.
##
## Height / water / perch come from `sense.bg`; without it the dragonfly just
## cruises and turns at its hover height.

enum {
	AVOID, LET_ESCAPE, FLY, ONIYANMA_FLY, WAIT, TOUCH_WATER,
	TOUCH_WATER_REVERSE, HOVER_WAIT_ON_WATER, FLY_ON_NOTICE, REST_ON_NOTICE,
}

const UNIT_GX := 20.0
const ONIYANMA_RANGE := 12.0 * UNIT_GX
const OTHER_RANGE := 6.0 * UNIT_GX
const SPEED_VAR := 2.0

const TURN_STEP := 0x600 * S16


func actor_init(a: BugActor, released: bool) -> void:
	a.gravity = 0.1
	a.bg_type = 1
	a.f_bit4 = false
	match a.type:
		T_COMMON_DRAGONFLY: a.item = 9
		T_RED_DRAGONFLY: a.item = 10
		T_DARNER_DRAGONFLY: a.item = 11
		T_BANDED_DRAGONFLY: a.item = 12
	if not released:
		a.f32_work[0] = 52.0 + a._rng.randf() * 10.0     ## hover height above ground
		a.pos.y = a.home.y + 20.0
		a.angle_y = a._rng.randf_range(-PI, PI)
		a.rot.y = a.angle_y
		a.f32_work[2] = a.home.x                          ## acre-ish centre
		a.f32_work[3] = a.home.z
		setup_action(a, ONIYANMA_FLY if a.type == T_BANDED_DRAGONFLY else FLY)
	else:
		setup_action(a, LET_ESCAPE)


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


func on_release(a: BugActor) -> void:
	setup_action(a, LET_ESCAPE)


# ---- setupAction --------------------------------------------

func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID:
			a.action_proc = _avoid
			if a._last_player_gx != Vector3.INF:
				a.angle_y = BugProgram.angle_to(a._last_player_gx, a.pos)
			a.continue_timer = 0
			a.target_speed = 4.0 + a._rng.randf() * SPEED_VAR
			a.timer = 20
		LET_ESCAPE:
			a.action_proc = _let_escape
			_let_escape_init(a)
		FLY, ONIYANMA_FLY:
			a.action_proc = _fly if action == FLY else _oniyanma_fly
			a.rot.y = a.angle_y
			_move_spd_set(a)
		WAIT:
			a.action_proc = _wait
			_wait_init(a)
		TOUCH_WATER:
			a.action_proc = _touch_water
			a.max_velocity_y = -1.0
			a.speed = 0.0
			a.target_speed = 0.0
		TOUCH_WATER_REVERSE:
			a.action_proc = _touch_water_reverse
			a.max_velocity_y = 4.0
			a.pos_speed.y = 4.0
			a.timer = 6
		HOVER_WAIT_ON_WATER:
			a.action_proc = _hover_wait
			a.max_velocity_y = 0.0
			a.pos_speed.y = 0.0
			a.timer = 20
		FLY_ON_NOTICE:
			a.action_proc = _fly_on_notice
			a.patience = 0.0
			a.flag = 0
			a.max_velocity_y = 0.0
			a.speed = 1.0
			a.target_speed = 2.0 + a._rng.randf() * SPEED_VAR
		REST_ON_NOTICE:
			a.action_proc = _rest_on_notice
			a.speed = 0.0
			a.speed_step = 0.0
			a.target_speed = 0.0
			a.timer = 200


func _let_escape_init(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 80
	a.f32_work[0] = 0.0
	a.speed = 4.0
	a.max_velocity_y = 12.0
	a.gravity = 0.06
	a.rot.x = 0.0
	a.pos_speed.y = 0.0
	a.f_no_catch = true
	a.f_bit2 = true


func _move_spd_set(a: BugActor) -> void:
	match a.type:
		T_BANDED_DRAGONFLY:
			a.target_speed = 4.0 + a._rng.randf() * SPEED_VAR
		T_DARNER_DRAGONFLY:
			a.target_speed = 2.4 + a._rng.randf() * SPEED_VAR
			a.timer = 24
		_:
			a.target_speed = 2.0 + a._rng.randf() * SPEED_VAR
			a.timer = 20
	a.speed_step = 0.2


func _wait_init(a: BugActor) -> void:
	var dx: float = a.f32_work[2] - a.pos.x
	var dz: float = a.f32_work[3] - a.pos.z
	if dx * dx + dz * dz < OTHER_RANGE * OTHER_RANGE:
		var picks := [-67.5, -33.75, 33.75, 67.5]
		a.angle_y = wrapf(a.angle_y + deg_to_rad(picks[a._rng.randi_range(0, 3)]), -PI, PI)
	else:
		a.angle_y = BugProgram.atans(dz, dx)
	a.patience = 0.0
	a.continue_timer = 0
	a.speed = 0.0
	a.speed_step = 0.0
	a.timer = 0


# ---- actions -----------------------------------------------

func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if a.caught:
		a.alpha0 = 255
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2:
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)
	if a.action != REST_ON_NOTICE:
		a.anime0 += 0.5
		if a.anime0 >= 2.0:
			a.anime0 -= 2.0


func _fly(a: BugActor, sense: BugActor.Sense) -> void:
	_turn(a)
	_height_ctrl(a, sense)
	var stop: int = _check_stop(a, sense)
	if stop == 2:
		setup_action(a, FLY_ON_NOTICE)
	elif stop == 1:
		setup_action(a, WAIT)
	else:
		_fly_ctrl(a, sense)


func _oniyanma_fly(a: BugActor, sense: BugActor.Sense) -> void:
	_turn(a)
	_height_ctrl(a, sense)
	var dx: float = a.f32_work[2] - a.pos.x
	var dz: float = a.f32_work[3] - a.pos.z
	if dx * dx + dz * dz >= ONIYANMA_RANGE * ONIYANMA_RANGE:
		setup_action(a, LET_ESCAPE)


func _wait(a: BugActor, sense: BugActor.Sense) -> void:
	_turn(a)
	_height_ctrl(a, sense)
	if absf(wrapf(a.rot.y - a.angle_y, -PI, PI)) < deg_to_rad(2.8125):
		setup_action(a, FLY)


func _avoid(a: BugActor, sense: BugActor.Sense) -> void:
	if a.type != T_BANDED_DRAGONFLY:
		_fly_ctrl(a, sense)
	_turn(a)


func _let_escape(a: BugActor, _sense: BugActor.Sense) -> void:
	a.gravity = minf(a.gravity * 1.1, 12.0)


func _touch_water(a: BugActor, sense: BugActor.Sense) -> void:
	_turn(a)
	if bool(_bg(a, sense).get("in_water", a.pos.y <= _water_y(a, sense))):
		setup_action(a, TOUCH_WATER_REVERSE)


func _touch_water_reverse(a: BugActor, _sense: BugActor.Sense) -> void:
	_turn(a)
	if a.timer > 0:
		a.timer -= 1
	if a.timer == 0:
		setup_action(a, HOVER_WAIT_ON_WATER)


func _hover_wait(a: BugActor, _sense: BugActor.Sense) -> void:
	if a.timer > 0:
		a.timer -= 1
	if a.timer == 0:
		if a.flag < 2:
			a.flag += 1
			setup_action(a, TOUCH_WATER)
		else:
			setup_action(a, WAIT)


func _fly_on_notice(a: BugActor, sense: BugActor.Sense) -> void:
	_turn(a)
	if a.patience < 90.0:
		var perch: float = _perch_y(a, sense)
		a.pos.y = BugProgram.chase_f(a.pos.y, perch, 0.5)
		if absf(a.pos.y - perch) < 3.0:
			setup_action(a, REST_ON_NOTICE)
	else:
		a.patience = 100.0
		setup_action(a, FLY)


func _rest_on_notice(a: BugActor, sense: BugActor.Sense) -> void:
	if a.timer > 0 and a.patience < 90.0:
		a.pos.y = BugProgram.chase_f(a.pos.y, _perch_y(a, sense), 0.5)
		a.s32_work[2] += 1
		if a.s32_work[2] < 20:
			a.anime0 += 0.5
			if a.anime0 >= 2.0:
				a.anime0 -= 2.0
		a.timer -= 1
	else:
		a.patience = 100.0
		setup_action(a, FLY)


# ---- helpers ---------------------------------------------

func _turn(a: BugActor) -> void:
	a.rot.y = BugProgram.chase_angle(a.rot.y, a.angle_y, TURN_STEP)


func _height_ctrl(a: BugActor, sense: BugActor.Sense) -> void:
	var ground: float = float(_bg(a, sense).get("ground_y", a.home.y))
	a.max_velocity_y = 1.0 if (a.f32_work[0] + ground > a.pos.y) else -1.0


func _fly_ctrl(a: BugActor, sense: BugActor.Sense) -> void:
	if not is_equal_approx(a.speed, a.target_speed):
		return
	if a.timer > 0:
		a.timer -= 1
		return
	if is_zero_approx(a.speed):
		if a.type != T_BANDED_DRAGONFLY and _water_touch(a, sense):
			a.flag = 1
			setup_action(a, TOUCH_WATER)
		else:
			setup_action(a, WAIT)
	else:
		a.target_speed = 0.0


func _check_stop(a: BugActor, sense: BugActor.Sense) -> int:
	if a.type == T_BANDED_DRAGONFLY:
		return 0
	var r: Dictionary = _bg(a, sense)
	if a.patience < 40.0 and bool(r.get("perch", false)):
		return 2
	if bool(r.get("hit_wall_front", false)) or bool(r.get("on_ground", false)):
		return 1
	return 0


func _bg(a: BugActor, sense: BugActor.Sense) -> Dictionary:
	if sense != null and sense.bg.is_valid():
		return sense.bg.call(a.pos)
	return {}


func _water_y(a: BugActor, sense: BugActor.Sense) -> float:
	return float(_bg(a, sense).get("water_y", -1e9))


func _perch_y(a: BugActor, sense: BugActor.Sense) -> float:
	return float(_bg(a, sense).get("perch_y", a.home.y + 20.0))


func _water_touch(a: BugActor, sense: BugActor.Sense) -> bool:
	return bool(_bg(a, sense).get("water_below", false))
