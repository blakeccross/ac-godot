class_name BugTonbo
extends BugProgram

## `ac_ins_tonbo.c` — dragonflies (common / red / darner / banded). Cruise in bursts
## at 52–62 GX over the ground (climbing / sinking at 1 GX/frame toward it), stopping
## to turn between bursts (WAIT: ±33.75° / ±67.5°, or back toward the acre centre once
## 240 GX out). At a stop over pond / river water (20 frames of every 100) they dip three
## times (TOUCH_WATER → REVERSE → HOVER). Calm ones (patience < 40) crossing a reserved
## unit settle on it (FLY_ON_NOTICE → REST_ON_NOTICE, 200 frames). Walls / the ground
## deflect them; four in a row and they leave. The banded dragonfly never stops: it
## patrols fast and leaves once 480 GX from the acre centre.

enum {
	AVOID, LET_ESCAPE, FLY, ONIYANMA_FLY, WAIT, TOUCH_WATER,
	TOUCH_WATER_REVERSE, HOVER_WAIT_ON_WATER, FLY_ON_NOTICE, REST_ON_NOTICE,
}

const ONIYANMA_RANGE := 12.0 * UNIT_GX
const OTHER_RANGE := 6.0 * UNIT_GX
const SPEED_VAR := 2.0
## `aITB_GET_STOP_STATE` (`s32_work0`).
const STOP_NONE := 0
const STOP_COLLISION := 1
const STOP_REST := 2
const BG_NONE := 0
const BG_COLLIDE := 1
const BG_ESCAPE := 2
## `angl_add` (`aITB_wait_init`).
const TURN_ADD := [-67.5, -33.75, 33.75, 67.5]
## `add_calc_short_angle2(rot.y, angle.y, 1 − √0.7, 2500, 0)`.
const TURN_FRACTION := 0.16333997
const TURN_MAX := 2500.0

var _s: BugActor.Sense = null


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
		a.f32_work[0] = 52.0 + a._rng.randf() * 10.0     ## hover height over the ground
		a.pos.y = a.home.y + 20.0
		a.angle_y = wrapf(PI - a._rng.randf() * TAU, -PI, PI)
		a.rot.y = a.angle_y
		setup_action(a, ONIYANMA_FLY if a.type == T_BANDED_DRAGONFLY else FLY)
	else:
		## Off the player's facing ±60°.
		if BugProgram.heading_from_player_facing(a, deg_to_rad(120.0)):
			a.rot.y = a.angle_y
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
			if a.has_player_info:
				a.angle_y = wrapf(a.player_angle_y + PI, -PI, PI)
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
			_wait_init(a)
			a.max_velocity_y = -1.0
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
			a.continue_timer = 0
			a.flag = 0
			a.s32_work[2] = 0
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
	if a.s32_work[0] == STOP_NONE:
		var c: Vector2 = BugProgram.acre_center(a, _s)
		var dx: float = c.x - a.pos.x
		var dz: float = c.y - a.pos.z
		if dx * dx + dz * dz < OTHER_RANGE * OTHER_RANGE:
			a.angle_y = wrapf(a.angle_y + deg_to_rad(TURN_ADD[a._rng.randi_range(0, 3)]), -PI, PI)
		else:
			a.angle_y = BugProgram.atans(dz, dx)
	a.patience = 0.0
	a.continue_timer = 0
	a.s32_work[2] = 0
	a.speed = 0.0
	a.speed_step = 0.0
	a.timer = 0
	## `mCoBG_BgCheckControll(… REVERSE)` along the new heading, up to four deflections.
	for _i: int in 4:
		if _bg_check(a, _s, true) != BG_COLLIDE:
			return


# ---- actions -----------------------------------------------

func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	_s = sense
	if a.caught:
		a.alpha0 = 255
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2:
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)
	if a.s32_work[0] != STOP_REST:
		_anime(a)


func _fly(a: BugActor, sense: BugActor.Sense) -> void:
	_turn(a)
	_height_ctrl(a, sense)
	if _check_stop(a, sense):
		setup_action(a, FLY_ON_NOTICE if a.s32_work[0] == STOP_REST else WAIT)
	else:
		_fly_ctrl(a, sense)


func _oniyanma_fly(a: BugActor, sense: BugActor.Sense) -> void:
	_turn(a)
	_height_ctrl(a, sense)
	if _bg_check(a, sense) == BG_ESCAPE:
		return
	var c: Vector2 = BugProgram.acre_center(a, sense)
	var dx: float = c.x - a.pos.x
	var dz: float = c.y - a.pos.z
	if dx * dx + dz * dz >= ONIYANMA_RANGE * ONIYANMA_RANGE:
		setup_action(a, LET_ESCAPE)


func _wait(a: BugActor, sense: BugActor.Sense) -> void:
	_turn(a)
	_height_ctrl(a, sense)
	if absf(wrapf(a.rot.y - a.angle_y, -PI, PI)) < deg_to_rad(2.8125):
		a.s32_work[0] = STOP_NONE
		setup_action(a, FLY)


func _avoid(a: BugActor, sense: BugActor.Sense) -> void:
	if a.type != T_BANDED_DRAGONFLY:
		_fly_ctrl(a, sense)
	_bg_check(a, sense)
	_turn(a)


func _let_escape(a: BugActor, _sense: BugActor.Sense) -> void:
	a.gravity = minf(a.gravity * 1.1, 12.0)


func _touch_water(a: BugActor, _sense: BugActor.Sense) -> void:
	_turn(a)
	if a.bg_in_water:
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


## Head for the centre of the reserved unit while easing down onto its top; settle once
## within 5 GX of the centre and 3 GX of the height. A scare (patience ≥ 90) sends it off.
func _fly_on_notice(a: BugActor, sense: BugActor.Sense) -> void:
	_turn(a)
	if a.patience < 90.0:
		a.pos.y = BugProgram.add_calc(a.pos.y, a.f32_work[1], 1.0 - sqrt(0.8), 0.5)
		var c: Vector3 = BugProgram.unit_center(sense, BugProgram.unit_of(sense, a.pos))
		var d2: float = Vector2(c.x - a.pos.x, c.z - a.pos.z).length_squared()
		if d2 > 25.0:
			a.angle_y = BugProgram.angle_to(a.pos, c)
		elif absf(a.f32_work[1] - a.pos.y) < 3.0:
			setup_action(a, REST_ON_NOTICE)
	else:
		a.s32_work[0] = STOP_NONE
		a.patience = 100.0
		setup_action(a, FLY)


func _rest_on_notice(a: BugActor, _sense: BugActor.Sense) -> void:
	if a.timer > 0 and a.patience < 90.0:
		a.pos.y = BugProgram.add_calc(a.pos.y, a.f32_work[1], 1.0 - sqrt(0.8), 0.5)
		a.s32_work[2] += 1
		if a.s32_work[2] < 20:
			_anime(a)
		if a.timer > 0:
			a.timer -= 1
	else:
		a.s32_work[0] = STOP_NONE
		a.patience = 100.0
		setup_action(a, FLY)


# ---- helpers ---------------------------------------------

func _anime(a: BugActor) -> void:
	a.anime0 += 0.5
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0


func _turn(a: BugActor) -> void:
	## `add_calc_short_angle2(rot.y, angle.y, 1 - sqrt(0.7), 2500, 0)` in every flying action.
	a.rot.y = MLib.short_angle2(a.rot.y, a.angle_y, TURN_FRACTION, TURN_MAX * MLib.S16)


## `aITB_height_ctrl`: climb / sink at 1 GX/frame toward hover height over the unit centre.
func _height_ctrl(a: BugActor, sense: BugActor.Sense) -> void:
	var ground: float = BugProgram.center_y(sense, a.pos, a.home.y)
	a.max_velocity_y = 1.0 if (a.f32_work[0] + ground > a.pos.y) else -1.0


## `aITB_fly_ctrl`: hold cruise speed for `timer` frames, then brake to a stop; stopped →
## dip into water (20 frames in every 100, over pond / river) or turn (WAIT).
func _fly_ctrl(a: BugActor, sense: BugActor.Sense) -> void:
	if a.speed != a.target_speed:
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


func _check_stop(a: BugActor, sense: BugActor.Sense) -> bool:
	a.s32_work[0] = STOP_NONE
	if a.type == T_BANDED_DRAGONFLY:
		return false
	## `aITB_check_reserve_dummy`: a calm dragonfly over a reserved unit perches on it.
	if a.patience < 40.0 and sense != null and sense.layout != null:
		var cell: Vector2i = BugProgram.unit_of(sense, a.pos)
		if BugBg.is_reserve(sense.layout, cell):
			a.s32_work[0] = STOP_REST
			a.f32_work[1] = BugProgram.center_y(sense, a.pos, a.home.y) + BugBg.COLUMN_GX
			return true
	if BugProgram.wall_front(a, sense) or a.bg_on_ground:
		a.s32_work[0] = STOP_COLLISION
		return true
	return false


## `aITB_BGcheck`: on a front wall or the ground, deflect (±45° off the wall's reflected
## heading); the fourth deflection in a row sends it away.
func _bg_check(a: BugActor, sense: BugActor.Sense, probe_only: bool = false) -> int:
	var wall: bool = BugProgram.wall_front(a, sense)
	if not wall and (probe_only or not a.bg_on_ground):
		a.continue_timer = 0
		return BG_NONE
	var angle: float = 0.0
	if wall:
		var normal: float = BugProgram.wall_normal(a)
		angle = wrapf(normal - (PI + a.angle_y), -PI, PI)
	var jitter: float = a._rng.randf() * deg_to_rad(45.0)
	angle += jitter if wrapf(a.angle_y - angle, -PI, PI) >= 0.0 else -jitter
	a.angle_y = wrapf(angle, -PI, PI)
	a.continue_timer += 1
	if a.continue_timer >= 4:
		setup_action(a, LET_ESCAPE)
		return BG_ESCAPE
	return BG_COLLIDE


## `aITB_check_water_touch`: in a field acre, `game_frame % 100 < 20`, over river / pond
## (not sea) water.
func _water_touch(a: BugActor, sense: BugActor.Sense) -> bool:
	if a.game_frame % 100 >= 20 or sense == null or sense.grid == null:
		return false
	return BugBg.water_at(sense.grid, a.pos)
