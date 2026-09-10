class_name BugMino
extends BugProgram

## `ac_ins_mino.c` — bagworm (minomushi) and spider. Hidden inside the tree until
## the player shakes it, then drops on a silk thread, hangs and sways, and either
## climbs back up, falls when the tree is felled, or crawls off (and can dive into
## water). Movement while on the thread uses a custom `position_move`.
##
## `sense.player_action == SHAKE_TREE` with `player_action_cell` matching the bug's
## tree cell is the APPEAR trigger. `sense.bg` supplies cut-tree / water / ground.

enum { AVOID, LET_ESCAPE, HIDE, APPEAR, APPEAR_STOP, WAIT, DISAPPEAR, DIVE, DROWN, FALL }

## `shape_info.rotation.x` for the thread line.
const THREAD_PITCH := deg_to_rad(47.8125)
const MOVE_RANGE := [-41.0, -47.0]

var _tree_cell: Vector2i = Vector2i(-1, -1)


func actor_init(a: BugActor, released: bool) -> void:
	a.bg_range = 4.0
	a.f_bit4 = false
	a.item = 35 if a.type == T_BAGWORM else 37
	a.move_proc = _position_move
	if not released:
		## 60 GX up the trunk, then + 5.
		a.pos.y = a.home.y + 60.0 + 5.0
		a.rot.x = THREAD_PITCH
		a.rot.y = BugActor.TREE_FACE_YAW
		a.angle_y = a.rot.y
		a.home = a.pos
		a.f32_work[3] = a.pos.z - 25.0     ## base Z
		a.drawn = false
		setup_action(a, HIDE)
	else:
		a.drawn = true
		setup_action(a, LET_ESCAPE)


func set_tree_cell(cell: Vector2i) -> void:
	_tree_cell = cell


func pose_index(a: BugActor) -> int:
	## `_1E0` is set to a fixed 0 / 2 per action rather than cycled.
	return int(a.anime0) & 1


func on_release(a: BugActor) -> void:
	a.drawn = true
	setup_action(a, LET_ESCAPE)


# ---- custom position_move (`aIMN_position_move`) --------------------

func _position_move(a: BugActor) -> void:
	a.last_pos = a.pos
	a.speed = BugProgram.chase_f(a.speed, a.target_speed, a.speed_step * 0.5)
	a.f32_work[0] += a.speed * 0.5           ## counter
	a.pos.y = a.home.y + cos(a.rot.x) * a.f32_work[0]
	a.pos.z = a.f32_work[3] - sin(a.rot.x) * a.f32_work[0]


# ---- setupAction --------------------------------------------------

func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		LET_ESCAPE:
			a.action_proc = _let_escape
			_let_escape_init(a)
		HIDE:
			a.action_proc = _hide
			_hide_init(a)
		APPEAR:
			a.action_proc = _appear
			_appear_init(a)
		APPEAR_STOP:
			a.action_proc = _appear_stop
			a.speed_step = 8.0
			a.target_speed = 0.0
		WAIT:
			a.action_proc = _wait
			_wait_init(a)
		DISAPPEAR:
			a.action_proc = _disappear
			a.target_speed = 0.5
			a.speed_step = 0.025
			a.rot.z = 0.0
		DIVE:
			a.action_proc = _dive
			_dive_init(a)
		DROWN:
			a.action_proc = _noop
			a.f_destruct = true
			a.finished = true
		FALL:
			a.action_proc = _fall
			_fall_init(a)
		_:
			a.action_proc = _noop


func _noop(_a: BugActor, _s: BugActor.Sense) -> void:
	pass


func _let_escape_init(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 80
	a.bg_type = 2
	a.gravity = 2.0
	a.max_velocity_y = -20.0
	a.rot.x = 0.0
	a.rot.z = 0.0
	a.move_proc = Callable()   ## back to the shared mover
	if a.f32_work[2] != 0.0 or a._last_player_gx != Vector3.INF:
		a.angle_y = a.f32_work[2] + a._rng.randf_range(-1.0, 1.0) * deg_to_rad(120.0)
	if a.type == T_BAGWORM:
		a.target_speed = 0.75
		a.speed_step = 0.15
		a.anime0 = 2.0
		a.rot.y = a.angle_y
	else:
		a.target_speed = 1.5
		a.speed_step = 0.3
		a.anime0 = 0.0
		a.rot.y = a.angle_y + PI
	a.f_no_catch = true
	a.f_bit2 = true


func _hide_init(a: BugActor) -> void:
	a.speed = 0.0
	a.target_speed = 0.0
	a.speed_step = 0.0
	a.pos.y = a.home.y
	a.f32_work[0] = 0.0
	a.anime0 = 1.0
	a.drawn = false
	a.f_no_catch = true


func _appear_init(a: BugActor) -> void:
	## Descend on the thread from a side offset chosen by which side the player is.
	a.f32_work[0] = 0.0
	a.f32_work[3] = a.pos.z
	a.speed = 0.0
	a.target_speed = -20.0
	a.speed_step = 2.0
	a.drawn = true
	a.f_no_catch = false
	a.flag = 0


func _wait_init(a: BugActor) -> void:
	a.timer = 1200
	a.speed = 0.0
	a.target_speed = 0.0
	a.speed_step = 0.0
	a.f32_work[1] = a.pos.x
	a.f32_work[2] = a.pos.y


func _dive_init(a: BugActor) -> void:
	a.target_speed = 1.5
	a.speed_step = 0.3
	a.speed = a.target_speed
	a.pos_speed.y = 8.0
	a.anime0 = 2.0 if a.type == T_BAGWORM else 0.0
	a.f_no_catch = true


func _fall_init(a: BugActor) -> void:
	a.gravity = 2.0
	a.max_velocity_y = -20.0
	a.rot.z = 0.0
	a.move_proc = Callable()
	a.drawn = true
	a.anime0 = 2.0 if a.type == T_BAGWORM else 0.0


# ---- actions ----------------------------------------------------

func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if a.caught:
		a.alpha0 = 255
		a.rot.y = BugActor.TREE_FACE_YAW
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _hide(a: BugActor, sense: BugActor.Sense) -> void:
	if _tree_cut(a, sense):
		setup_action(a, FALL)
	elif _shaken(a, sense):
		setup_action(a, APPEAR)


func _appear(a: BugActor, sense: BugActor.Sense) -> void:
	if _tree_cut(a, sense):
		setup_action(a, FALL)
		return
	if a.f32_work[0] < MOVE_RANGE[a.flag]:
		if a.target_speed < 0.0 and a.speed < 0.0:
			if a.speed > -2.0:
				setup_action(a, APPEAR_STOP)
			else:
				a.target_speed = -a.speed * 0.2
				a.speed_step = 8.0
	else:
		a.target_speed = -12.0
		a.speed_step = 2.0
	_twist(a)


func _appear_stop(a: BugActor, sense: BugActor.Sense) -> void:
	if _tree_cut(a, sense):
		setup_action(a, FALL)
		return
	if is_zero_approx(a.speed):
		setup_action(a, WAIT)
	_twist(a)


func _wait(a: BugActor, sense: BugActor.Sense) -> void:
	if _tree_cut(a, sense):
		setup_action(a, FALL)
		return
	if _shaken(a, sense):
		a.s32_work[0] = 0x80
		a.s32_work[3] = -0x80
	a.timer -= 1
	if a.timer <= 0:
		if a.s32_work[3] == 0:
			setup_action(a, DISAPPEAR)
		else:
			a.timer = 0
	_shake_angle(a)
	_twist(a)


func _disappear(a: BugActor, sense: BugActor.Sense) -> void:
	if _tree_cut(a, sense):
		setup_action(a, FALL)
		return
	if a.pos.y > a.home.y:
		setup_action(a, HIDE)
	_twist(a)


func _fall(a: BugActor, sense: BugActor.Sense) -> void:
	var g: float = _ground_y(a, sense)
	if a.pos.y < g:
		a.pos.y = g
		setup_action(a, LET_ESCAPE)


func _dive(a: BugActor, sense: BugActor.Sense) -> void:
	var w: float = _water_y(a, sense)
	if a.pos.y <= w:
		setup_action(a, DROWN)


func _let_escape(a: BugActor, sense: BugActor.Sense) -> void:
	if _water_ahead(a, sense):
		setup_action(a, DIVE)
		return
	_calc_direction(a, sense)


# ---- helpers --------------------------------------------------

func _twist(a: BugActor) -> void:
	a.continue_timer += 0x100
	a.rot.z = sin(a.continue_timer * S16) * deg_to_rad(22.5)


func _shake_angle(a: BugActor) -> void:
	## `aIMN_calc_shake_angl`: decaying yaw wobble; snap back to south when tiny.
	var cur: int = a.s32_work[0]
	var tgt: int = a.s32_work[3]
	if tgt * int(a.rot.y * 100.0) < 0:
		tgt = int(-(tgt * 0.5))
		if absi(tgt) < 16:
			tgt = 0
			cur = 0
			a.rot.y = BugActor.TREE_FACE_YAW
		a.s32_work[3] = tgt
	cur = int(BugProgram.chase_angle(float(cur) * S16, float(tgt) * S16, 16 * S16) / S16)
	a.s32_work[0] = cur
	a.rot.y = wrapf(BugActor.TREE_FACE_YAW + (cur * 0.5) * S16, -PI, PI)


func _calc_direction(a: BugActor, sense: BugActor.Sense) -> void:
	var probe: Dictionary = _bg(a, sense)
	if bool(probe.get("hit_wall", false)):
		a.angle_y = wrapf(a.angle_y + PI * 0.5, -PI, PI)
	var target: float = a.angle_y if a.type == T_BAGWORM else a.angle_y + PI
	a.rot.y = BugProgram.chase_angle(a.rot.y, target, 0x800 * S16)


func _bg(a: BugActor, sense: BugActor.Sense) -> Dictionary:
	if sense != null and sense.bg.is_valid():
		return sense.bg.call(a.pos)
	return {}


func _tree_cut(a: BugActor, sense: BugActor.Sense) -> bool:
	return bool(_bg(a, sense).get("tree_cut", false))


func _shaken(_a: BugActor, sense: BugActor.Sense) -> bool:
	if sense == null or sense.player_action != BugActor.PlAct.SHAKE_TREE:
		return false
	if _tree_cell.x < 0:
		return true
	return sense.player_action_cell == _tree_cell


func _ground_y(a: BugActor, sense: BugActor.Sense) -> float:
	return float(_bg(a, sense).get("ground_y", a.home.y - 60.0))


func _water_y(a: BugActor, sense: BugActor.Sense) -> float:
	return float(_bg(a, sense).get("water_y", -1e9))


func _water_ahead(a: BugActor, sense: BugActor.Sense) -> bool:
	return bool(_bg(a, sense).get("water_ahead", false))
