class_name BugChou
extends BugProgram

## `ac_ins_chou.c` — butterflies (common / yellow / tiger / purple).
## Actions: AVOID, LET_ESCAPE, FLY, LANDING, HOVER, REST.
##
## Acre-content queries the decomp makes against the field (flower units, BG height,
## water height) are routed through `BugActor.Sense`: `bg` for ground/water height,
## `flower_near` for the nearest flower unit. Both degrade to "flat ground / no
## flower" so the flight state machine still runs faithfully without them.

enum { AVOID, LET_ESCAPE, FLY, LANDING, HOVER, REST }

const PT_X := [10.0, 10.0, -10.0, -10.0]
const PT_Z := [10.0, -10.0, 10.0, -10.0]
const CHK_X := [-1.0, 1.0, 1.0, -1.0]
const CHK_Z := [-1.0, 1.0, -1.0, 1.0]
## `rest_wait_data` (`aICH_landing`) — settle offset + bg_height per `light_flag`.
const REST_WAIT := [
	Vector3(-11.0, -22.0, -4.0),
	Vector3(10.0, -22.0, -8.0),
	Vector3(2.0, -24.0, 14.0),
]

var _frame_counter: int = 0


func actor_init(a: BugActor, released: bool) -> void:
	a.bg_type = 2
	match a.type:
		T_COMMON_BUTTERFLY: a.item = 0
		T_YELLOW_BUTTERFLY: a.item = 1
		T_TIGER_BUTTERFLY: a.item = 2
		T_PURPLE_BUTTERFLY: a.item = 3
	if not released:
		## `aICH_check_live_condition` is a spawn-time cull (height gap / bad unit);
		## the scheduler already placed us on a good unit, so accept it.
		a.home = a.pos
		a.f32_work[0] = a.pos.x
		a.f32_work[1] = a.pos.z
		setup_action(a, FLY)
	else:
		setup_action(a, LET_ESCAPE)


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


func on_release(a: BugActor) -> void:
	setup_action(a, LET_ESCAPE)


# ---- setupAction ------------------------------------------------------

func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID:
			a.action_proc = _avoid
			_avoid_init(a)
		LET_ESCAPE:
			a.action_proc = _let_escape
			_let_escape_init(a)
		FLY:
			a.action_proc = _fly
			_fly_init(a)
		LANDING:
			a.action_proc = _landing
			_landing_init(a)
		HOVER:
			a.action_proc = _hover
			_hover_init(a)
		REST:
			a.action_proc = _hover
			_rest_init(a)


func _avoid_init(a: BugActor) -> void:
	a.bg_height = 0.0
	a.target_speed = 3.0
	a.speed_step = 0.3
	a.speed = 2.0


func _let_escape_init(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 0x50
	a.rot.x = 0.0
	a.bg_height = 0.0
	a.flag = 0
	a.home.y = a.pos.y
	a.speed = 1.5
	a.f_no_catch = true
	a.f_bit2 = true


func _fly_init(a: BugActor) -> void:
	a.bg_height = 0.0
	a.gravity = 0.3
	a.max_velocity_y = -2.0
	a.target_speed = 2.0
	a.speed_step = 0.2
	a.s32_work[0] = 0
	a.s32_work[3] = 0
	a.f32_work[0] = a.pos.x
	a.f32_work[1] = a.pos.z
	a.f32_work[2] = 0.0
	a.f32_work[3] = 120.0
	_flower_search(a, null)


func _landing_init(a: BugActor) -> void:
	a.light_flag = _frame_counter % 3
	a.pos_speed.y = 0.0


func _hover_init(a: BugActor) -> void:
	a.target_speed = 0.0
	a.speed_step = 0.0
	a.speed = 0.0
	a.timer = 10


func _rest_init(a: BugActor) -> void:
	a.anime0 = 1.0
	a.timer = int(0.5 * (30.0 + randf_range_i(a, 60)))


# ---- actor_move ------------------------------------------------------

func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	_frame_counter += 1
	if a.caught:
		a.alpha0 = 255
		_anime(a)
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2:
		setup_action(a, LET_ESCAPE)
		return
	_check_block_edge(a)
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _check_block_edge(a: BugActor) -> void:
	if a.action == LET_ESCAPE:
		return
	## Leaving the home acre → escape. `home` marks the spawn acre origin.
	if BugProgram.dist_xz(a.pos, a.home) > 7.5 * BugActor.UNIT_GX:
		setup_action(a, LET_ESCAPE)


# ---- actions -------------------------------------------------------

func _fly(a: BugActor, sense: BugActor.Sense) -> void:
	_anime(a)
	_bg_wall_check(a, sense)
	var base: float = -30.0
	if a.type == T_TIGER_BUTTERFLY:
		base = -40.0
	elif a.type == T_PURPLE_BUTTERFLY:
		base = -50.0
	_jump_ctrl(a, sense, base)
	_loop_move_ctrl(a, sense)
	match a.type:
		T_TIGER_BUTTERFLY:
			if a.patience > 90.0:
				setup_action(a, AVOID)
				return
			_rest_check(a, sense)
		T_PURPLE_BUTTERFLY:
			if a.patience > 90.0:
				setup_action(a, AVOID)
		_:
			_rest_check(a, sense)


func _landing(a: BugActor, sense: BugActor.Sense) -> void:
	_anime(a)
	if _check_patience(a, sense):
		var next: int = FLY
		if a.type == T_TIGER_BUTTERFLY or a.type == T_PURPLE_BUTTERFLY:
			next = AVOID
		setup_action(a, next)
		return
	var target: Vector3 = Vector3(a.f32_work[0], a.pos.y, a.f32_work[1])
	var off: Vector3 = REST_WAIT[a.light_flag]
	target.x += off.x
	target.z += off.z
	a.bg_height = off.y
	if a.type == T_COMMON_BUTTERFLY or a.type == T_YELLOW_BUTTERFLY:
		a.bg_height -= 3.0
	var ang: float = BugProgram.angle_to(a.pos, target)
	a.rot.y = BugProgram.chase_angle(a.rot.y, ang, 0x1000 * S16)
	a.angle_y = a.rot.y
	if is_zero_approx(a.target_speed) or (
		absf(a.pos.x - target.x) < 2.0 and absf(a.pos.z - target.z) < 2.0
	):
		setup_action(a, HOVER)


func _hover(a: BugActor, sense: BugActor.Sense) -> void:
	if a.action == HOVER:
		_anime(a)
	if _check_patience(a, sense):
		var next: int = FLY
		if a.type == T_TIGER_BUTTERFLY or a.type == T_PURPLE_BUTTERFLY:
			next = AVOID
		setup_action(a, next)
		return
	a.timer -= 1
	if a.timer <= 0:
		var next: int = REST
		if a.action == REST:
			next = FLY
		setup_action(a, next)


func _avoid(a: BugActor, sense: BugActor.Sense) -> void:
	_anime(a)
	var base: float = -60.0
	if a.type == T_TIGER_BUTTERFLY:
		base = -80.0
	elif a.type == T_PURPLE_BUTTERFLY:
		base = -100.0
	_jump_ctrl(a, sense, base)
	_avoid_move_ctrl(a, sense)
	if a.patience < 70.0:
		a.f32_work[0] = a.pos.x
		a.f32_work[1] = a.pos.z
		setup_action(a, FLY)


func _let_escape(a: BugActor, _sense: BugActor.Sense) -> void:
	_chou_fuwafuwa(a)
	a.gravity += 0.1
	_anime(a)


# ---- helpers ------------------------------------------------------

func _anime(a: BugActor) -> void:
	a.anime0 += 0.2
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0


func _ground_y_gx(a: BugActor, sense: BugActor.Sense) -> float:
	if sense != null and sense.bg.is_valid():
		var r: Dictionary = sense.bg.call(a.pos)
		if r.has("ground_y"):
			return float(r["ground_y"])
	return a.home.y


func _jump_ctrl(a: BugActor, sense: BugActor.Sense, base: float) -> void:
	var h: float = _ground_y_gx(a, sense) - base
	if a.pos.y < h:
		a.pos_speed.y = 2.0 + a._rng.randf()
	a.pos_speed.y = BugProgram.chase_f(a.pos_speed.y, a.max_velocity_y, 0.5 * a.gravity)


func _loop_move_ctrl(a: BugActor, sense: BugActor.Sense) -> void:
	var idx: int = a.s32_work[0]
	var x: float = a.pos.x - (a.f32_work[0] + PT_X[idx])
	var z: float = a.pos.z - (a.f32_work[1] + PT_Z[idx])
	var sq: float = sqrt(x * x + z * z)
	var ang: float = BugProgram.atans(-z, -x)
	var step: float = (0x800 if sq < 15.0 else 0x400) * S16
	a.rot.y = BugProgram.chase_angle(a.rot.y, ang, step)
	a.angle_y = a.rot.y
	if x * CHK_X[idx] < 0.0 or z * CHK_Z[idx] < 0.0:
		if a.s32_work[3] == 0:
			a.s32_work[3] = 1
			a.s32_work[0] += 1
			if a.s32_work[0] > 3:
				a.s32_work[0] = 0
				_flower_search(a, sense)
	else:
		a.s32_work[3] = 0


func _flower_search(a: BugActor, sense: BugActor.Sense) -> void:
	## `aICH_flower_search` → `aICH_flower_search_sub(1)`: hop the patrol centre to a
	## neighbouring flower unit (needs `CheckFGNpcOn` true). Purple butterfly never
	## flower-searches. With no flower probe, `CheckFGNpcOn` is false everywhere, so
	## `f32_work0/1` is left unchanged and the butterfly loops around its spawn — the
	## exact decomp outcome for a flowerless acre.
	if a.type == T_PURPLE_BUTTERFLY:
		return
	if sense == null or not sense.bg.is_valid():
		return
	var probe: Dictionary = sense.bg.call(a.pos)
	var flower: Variant = probe.get("flower_center_gx", null)
	if flower is Vector3:
		a.f32_work[0] = (flower as Vector3).x
		a.f32_work[1] = (flower as Vector3).z


func _rest_check(a: BugActor, sense: BugActor.Sense) -> void:
	## `aICH_rest_check`: land on a pansy when the cooldown (`f32_work3`) is 0.
	if is_zero_approx(a.f32_work[3]):
		if _on_flower(a, sense):
			setup_action(a, LANDING)
	else:
		a.f32_work[3] = maxf(a.f32_work[3] - 0.5, 0.0)


func _on_flower(a: BugActor, sense: BugActor.Sense) -> bool:
	if sense != null and sense.bg.is_valid():
		var r: Dictionary = sense.bg.call(a.pos)
		return bool(r.get("on_flower", false))
	return false


func _chou_fuwafuwa(a: BugActor) -> void:
	var save_ang: float = 10.0 * sin(a.flag * S16)
	a.flag += 0x800
	var cur_ang: float = 10.0 * sin(a.flag * S16)
	a.pos_speed.y = a.gravity + (cur_ang - save_ang)


func _bg_wall_check(a: BugActor, sense: BugActor.Sense) -> void:
	## `aICH_BGcheck`: on a front wall hit, retarget a flower (cooldown `f32_work2`).
	if a.f32_work[2] <= 0.0 and sense != null and sense.bg.is_valid():
		var r: Dictionary = sense.bg.call(a.pos)
		if bool(r.get("hit_wall_front", false)):
			_flower_search(a, sense)
			a.f32_work[2] = 10.0
	a.f32_work[2] = maxf(a.f32_work[2] - 1.0, 0.0)


func _avoid_player(a: BugActor, sense: BugActor.Sense) -> void:
	if not sense.has_player():
		return
	var to_player: float = BugProgram.angle_to(a.pos, sense.player_position / BugActor.GX_M)
	var away: float = wrapf(to_player + PI, -PI, PI)
	away += (0x1000 * S16) * (1.0 if (_frame_counter >> 5) & 1 else -1.0)
	a.rot.y = BugProgram.chase_angle(a.rot.y, away, 0x600 * S16)
	a.angle_y = a.rot.y


func _avoid_move_ctrl(a: BugActor, sense: BugActor.Sense) -> void:
	## Near the acre centre → dodge the player; near the edge → steer back in.
	var to_home: float = BugProgram.dist_xz(a.pos, a.home)
	if to_home < 6.0 * BugActor.UNIT_GX:
		_avoid_player(a, sense)
		return
	var ang: float = BugProgram.angle_to(a.pos, a.home)
	a.rot.y = BugProgram.chase_angle(a.rot.y, ang, 0x600 * S16)
	a.angle_y = a.rot.y


func _check_patience(a: BugActor, sense: BugActor.Sense) -> bool:
	## `aICH_check_patience`: ball / stopped-net / dig-scoop within 60 GX → panic.
	if sense.net_swing_active and sense.net_swing_origin != Vector3.INF:
		if BugProgram.dist_xz(a.pos, sense.net_swing_origin / BugActor.GX_M) < 60.0:
			a.patience = 100.0
	if sense.player_swung_tool and sense.has_player():
		if BugProgram.dist_xz(a.pos, sense.player_position / BugActor.GX_M) < 60.0:
			a.patience = 100.0
	return a.patience >= 90.0


static func randf_range_i(a: BugActor, n: int) -> float:
	return a._rng.randf() * float(n)
