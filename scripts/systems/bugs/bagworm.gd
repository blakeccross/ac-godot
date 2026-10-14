class_name Bagworm
extends BugBehavior

## `ac_ins_mino.c` — bagworm (minomushi) and spider. Hidden 65 GX up its tree until
## that tree's unit is shaken; then it drops on a thread (along the 47.8° thread line)
## on the side away from the player — 30 GX east, 18 north when the player is west of
## the tree, else 30 west, 25 north and 6 lower — bounces to a stop at 41 / 47 GX down,
## and hangs for 1200 frames. Shaking the tree again swings it like a pendulum (50 GX
## arm, damped by half each swing); once still after the timer it climbs back in. A
## felled tree drops it to the ground, where it crawls off the player's facing ±60°
## (bagworm 0.75, spider 1.5 GX/frame), sliding along walls, and drowns in water.

enum { AVOID, LET_ESCAPE, HIDE, APPEAR, APPEAR_STOP, WAIT, DISAPPEAR, DIVE, DROWN, FALL }

## `shape_info.rotation.x` for the thread line.
const THREAD_PITCH := deg_to_rad(47.8125)
const MOVE_RANGE := [-41.0, -47.0]
const HANG_Y := 65.0          ## `5 + GetBgY_OnlyCenter_FromWpos2(pos, −60)`
const SHAKE_ARM := 50.0

var _tree_cell: Vector2i = Vector2i(-1, -1)


## How far down its thread it hangs (`f32_work0`, GX) from the thread's base Z (`f32_work3`).
var _thread_length: float = 0.0
var _thread_base_z: float = 0.0
## The shake's pendulum: its pivot (`f32_work1/2`, GX x and y), its swing speed and the
## swing it eases toward (`s32_work0` / `s32_work3`, s16).
var _pivot: Vector2 = Vector2.ZERO
var _swing_speed: int = 0
var _swing_target: int = 0

func actor_init(a: BugActor, released: bool) -> void:
	a.bg_range = 4.0
	a.wall_check = false
	a.item = 35 if a.type == T_BAGWORM else 37
	a.move_proc = _position_move
	if not released:
		a.pos.y = a.home.y + HANG_Y
		a.rot.x = THREAD_PITCH
		a.rot.y = BugActor.TREE_FACE_YAW
		a.angle_y = a.rot.y
		a.home = a.pos
		_thread_base_z = a.pos.z - 25.0
		a.drawn = false
		setup_action(a, HIDE)
	else:
		a.drawn = true
		setup_action(a, LET_ESCAPE)


func set_tree_cell(cell: Vector2i) -> void:
	_tree_cell = cell


func pose_index(a: BugActor) -> int:
	## `_1E0` is set to a fixed 0 / 2 per action rather than cycled.
	return int(a.anim_frame) & 1


func on_release(a: BugActor) -> void:
	a.drawn = true
	setup_action(a, LET_ESCAPE)


# ---- custom position_move (`aIMN_position_move`) --------------------

func _position_move(a: BugActor) -> void:
	a.last_pos = a.pos
	a.speed = BugBehavior.chase_f(a.speed, a.target_speed, a.speed_step * 0.5 * a.n)
	_thread_length += a.speed * 0.5 * a.n  ## along the thread (`world.angle.x`)
	a.pos.y = a.home.y + cos(THREAD_PITCH) * _thread_length
	a.pos.z = _thread_base_z - sin(THREAD_PITCH) * _thread_length


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
			a.one_shot_sounds.append(&"438")
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
	a.terrain_mode = BugActor.TerrainMode.GROUND
	a.gravity = 2.0
	a.max_velocity_y = -20.0
	a.rot.x = 0.0
	a.rot.z = 0.0
	a.move_proc = Callable()   ## back to the shared mover
	BugBehavior.heading_from_player_facing(a, deg_to_rad(120.0))
	if a.type == T_BAGWORM:
		a.target_speed = 0.75
		a.speed_step = 0.15
		a.anim_frame = 2.0
		a.rot.y = a.angle_y
	else:
		a.target_speed = 1.5
		a.speed_step = 0.3
		a.anim_frame = 0.0
		a.rot.y = a.angle_y + PI
	a.catchable = false
	a.escaping = true


func _hide_init(a: BugActor) -> void:
	a.speed = 0.0
	a.target_speed = 0.0
	a.speed_step = 0.0
	a.pos.y = a.home.y
	_thread_length = 0.0
	a.anim_frame = 1.0
	a.drawn = false
	a.catchable = false


func _appear_init(a: BugActor) -> void:
	## Drop on the side of the tree away from the player.
	if a.has_player_info:
		if a.player_pos.x < a.home.x:
			a.pos.x = a.home.x + 30.0
			a.pos.z = a.home.z - 18.0
			_thread_length = 0.0
			a.flag = 0
		else:
			a.pos.x = a.home.x - 30.0
			a.pos.z = a.home.z - 25.0
			a.pos.y = a.home.y - 6.0
			_thread_length = -6.0
			a.flag = 1
	_thread_base_z = a.pos.z
	a.speed = 0.0
	a.target_speed = -20.0
	a.speed_step = 2.0
	a.drawn = true
	a.catchable = true


func _wait_init(a: BugActor) -> void:
	a.timer = 1200
	a.speed = 0.0
	a.target_speed = 0.0
	a.speed_step = 0.0
	_pivot = Vector2(a.pos.x, a.pos.y)


func _dive_init(a: BugActor) -> void:
	a.target_speed = 1.5
	a.speed_step = 0.3
	a.speed = a.target_speed
	a.pos_speed.y = 8.0
	a.anim_frame = 2.0 if a.type == T_BAGWORM else 0.0
	a.catchable = false


func _fall_init(a: BugActor) -> void:
	a.gravity = 2.0
	a.max_velocity_y = -20.0
	a.rot.z = 0.0
	a.move_proc = Callable()
	a.drawn = true
	a.anim_frame = 2.0 if a.type == T_BAGWORM else 0.0


# ---- actions ----------------------------------------------------

func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if _tree_cell.x < 0:
		_tree_cell = BugBehavior.unit_of(sense, a.home)
	if a.caught:
		a.opacity = 255
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
	if _thread_length < MOVE_RANGE[a.flag]:
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
		_swing_speed = 0x80
		_swing_target = -0x80
	a.timer -= a.n
	if a.timer <= 0.0:
		if _swing_target == 0:
			setup_action(a, DISAPPEAR)
		else:
			a.timer = 0.0
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
	if a.pos.y <= BugBehavior.water_y(a, sense):
		setup_action(a, DROWN)


func _let_escape(a: BugActor, sense: BugActor.Sense) -> void:
	if BugBehavior.water_ahead(a, sense):
		setup_action(a, DIVE)
		return
	_calc_direction(a, sense)
	if (sense == null or not sense.ground.is_valid()) and a.pos.y < a.home.y:
		a.pos.y = a.home.y   ## no field: the ground it fell to
		a.pos_speed.y = 0.0


# ---- helpers --------------------------------------------------

func _twist(a: BugActor) -> void:
	a.continue_timer = fmod(a.continue_timer + 0x100 * a.n, 65536.0)
	a.rot.z = sin(a.continue_timer * MathUtil.S16) * deg_to_rad(22.5)


## `aIMN_calc_shake_angl`: a damped pendulum hanging 50 GX under its pivot. The s16
## yaw gains half the swing speed each tick; each time it crosses due south the target
## swing flips and halves, and under 16 it snaps still facing south. The body rides the
## arm: x = pivot − 50·sin(yaw), y = pivot + 50 + 50·cos(yaw).
func _shake_angle(a: BugActor) -> void:
	var ang: int = _s16(roundi(a.rot.y / MathUtil.S16))
	var cur: int = _swing_speed
	var tgt: int = _swing_target
	if tgt * ang < 0:
		tgt = int(-(tgt * 0.5))
		if absi(tgt) < 16:
			tgt = 0
			cur = 0
			ang = -0x8000
		_swing_target = tgt
	cur = roundi(BugBehavior.chase_angle(cur * MathUtil.S16, tgt * MathUtil.S16, 16 * MathUtil.S16, a.n) / MathUtil.S16)
	_swing_speed = cur
	ang = _s16(ang + roundi(cur * 0.5 * a.n))
	a.rot.y = ang * MathUtil.S16
	a.pos.x = _pivot.x - SHAKE_ARM * sin(a.rot.y)
	a.pos.y = _pivot.y + SHAKE_ARM + SHAKE_ARM * cos(a.rot.y)


static func _s16(v: int) -> int:
	return ((v + 0x8000) & 0xFFFF) - 0x8000


## `aIMN_calc_direction_angl`: the bagworm turns along a front wall; the spider (which
## walks backwards) along a wall behind it. The shape chases the heading (spider: +180°).
func _calc_direction(a: BugActor, sense: BugActor.Sense) -> void:
	var probe_yaw: float = a.angle_y if a.type == T_BAGWORM else a.angle_y + PI
	if sense != null and sense.grid != null and BugTerrain.wall_front(sense.grid, sense.layout, a.pos, probe_yaw, maxf(a.bg_range, 1.0)):
		a.angle_y = wrapf(BugBehavior.wall_normal(a) + PI * 0.5, -PI, PI)
	var target: float = a.angle_y if a.type == T_BAGWORM else a.angle_y + PI
	a.rot.y = BugBehavior.chase_angle(a.rot.y, target, 0x800 * MathUtil.S16, a.n)


## `aIMN_check_cut_tree`: the home unit holds no tree any more, or a stump.
func _tree_cut(a: BugActor, sense: BugActor.Sense) -> bool:
	if sense == null or sense.layout == null:
		return false
	return BugTerrain.tree_cut(sense.layout, BugBehavior.unit_of(sense, a.home))


## `aIMN_check_shake_tree`: a shake on its tree's unit.
func _shaken(_a: BugActor, sense: BugActor.Sense) -> bool:
	if sense == null or sense.player_action != BugActor.PlAct.SHAKE_TREE:
		return false
	return sense.player_action_cell == _tree_cell


## `mCoBG_GetBgY_AngleS_FromWpos` under it (without a field: 65 GX under its hang point).
func _ground_y(a: BugActor, sense: BugActor.Sense) -> float:
	if sense != null and sense.ground.is_valid():
		return float(sense.ground.call(a.pos).get("ground_y", a.home.y - HANG_Y))
	return a.home.y - HANG_Y
