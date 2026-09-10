class_name BugDango
extends BugProgram

## `ac_ins_dango.c` — pill bug (and ant). The pill bug hides under a rock
## (`sense.player_action == REFLECT_AXE / REFLECT_SCOOP` on its cell strikes it out),
## pops up (`APPEAR`), then rolls around (`AVOID`); when scared while settled it
## curls into a ball (`STOP`). Strays out of range → retires (fades). Ants skip the
## hide and just crawl.

enum { AVOID, LET_ESCAPE, STOP, HIDE, APPEAR, DIVE, DROWN, RETIRE }

const ACTIVE_RANGE_SQ := 160000.0   ## 400²

var _rock_cell: Vector2i = Vector2i(-1, -1)


func actor_init(a: BugActor, released: bool) -> void:
	a.f_bit4 = false
	a.bg_range = 2.0
	match a.type:
		T_PILL_BUG: a.item = 36
		T_ANT: a.item = 38
	if released:
		a.drawn = true
		setup_action(a, LET_ESCAPE)
		return
	a.f32_work[2] = a.home.x
	a.f32_work[3] = a.home.z
	if a.type == T_ANT:
		setup_action(a, AVOID)     ## ants walk, no rock to hide under
	else:
		setup_action(a, HIDE)


func set_rock_cell(cell: Vector2i) -> void:
	_rock_cell = cell


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


func on_release(a: BugActor) -> void:
	a.drawn = true
	setup_action(a, LET_ESCAPE)


func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID:
			a.action_proc = _avoid
			a.speed = 1.5
			a.target_speed = 1.5
			a.speed_step = 0.3
			a.anime0 = 1.0
			if a._last_player_gx != Vector3.INF:
				a.angle_y = BugProgram.angle_to(a._last_player_gx, a.pos) + a._rng.randf_range(-1.0, 1.0) * (21845.0 * 0.5 * S16)
				a.rot.y = a.angle_y
		LET_ESCAPE:
			a.action_proc = _let_escape
			a.life_time = 0
			a.alpha_time = 80
			a.rot.x = 0.0
			a.bg_type = 2
			a.gravity = 2.0
			a.max_velocity_y = -20.0
			a.speed = 1.5
			a.target_speed = 1.5
			a.speed_step = 0.3
			if a._last_player_gx != Vector3.INF:
				a.angle_y = BugProgram.angle_to(a._last_player_gx, a.pos) + a._rng.randf_range(-1.0, 1.0) * (21845.0 * 0.5 * S16)
				a.rot.y = a.angle_y
			a.f_no_catch = true
			a.f_bit2 = true
		STOP:
			a.action_proc = _stop
			a.target_speed = 0.0
			a.speed_step = 0.05
			a.anime0 = 0.0
		HIDE:
			a.action_proc = _hide
			a.bg_type = 4
			a.drawn = false
			a.move_proc = BugProgram.freeze_move
		APPEAR:
			a.action_proc = _appear
			a.move_proc = Callable()
			a.gravity = 2.0
			a.max_velocity_y = -20.0
			a.speed = 1.5
			a.target_speed = 1.5
			a.speed_step = 0.3
			a.drawn = true
			a.anime0 = 0.0
			a.pos_speed.y = 12.0
			if a._last_player_gx != Vector3.INF:
				a.angle_y = BugProgram.angle_to(a._last_player_gx, a.pos) + a._rng.randf_range(-1.0, 1.0) * deg_to_rad(120.0)
				a.rot.y = a.angle_y
		DIVE:
			a.action_proc = _dive
			a.speed = 1.5
			a.target_speed = 1.5
			a.speed_step = 0.3
			a.pos_speed.y = 8.0
			a.anime0 = 0.0
			a.f_no_catch = true
		DROWN:
			a.action_proc = _noop
			a.f_destruct = true
			a.finished = true
		RETIRE:
			a.action_proc = _let_escape
			a.life_time = 0
			a.alpha_time = 80
			a.rot.x = 0.0
			a.bg_type = 2
			a.f_no_catch = true
			a.f_bit2 = true


func _noop(_a: BugActor, _s: BugActor.Sense) -> void:
	pass


func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if a.caught:
		a.alpha0 = 255
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _hide(a: BugActor, sense: BugActor.Sense) -> void:
	if sense == null:
		return
	if sense.player_action != BugActor.PlAct.REFLECT_AXE and sense.player_action != BugActor.PlAct.REFLECT_SCOOP:
		return
	if _rock_cell.x < 0 or sense.player_action_cell == _rock_cell:
		setup_action(a, APPEAR)


func _appear(a: BugActor, sense: BugActor.Sense) -> void:
	if a.pos.y <= _ground_y(a, sense) and a.pos_speed.y <= 0.0:
		a.pos.y = _ground_y(a, sense)
		a.pos_speed.y = 0.0
		setup_action(a, STOP)


func _stop(a: BugActor, sense: BugActor.Sense) -> void:
	if not _water_ahead(a, sense) and a.patience < 50.0:
		setup_action(a, AVOID)


func _avoid(a: BugActor, sense: BugActor.Sense) -> void:
	if _water_ahead(a, sense):
		setup_action(a, DIVE)
		return
	var dx: float = a.f32_work[2] - a.pos.x
	var dz: float = a.f32_work[3] - a.pos.z
	if dx * dx + dz * dz >= ACTIVE_RANGE_SQ:
		setup_action(a, RETIRE)
		return
	_calc_direction(a, sense)
	_ground_clamp(a, sense)
	if _check_patience(a, sense):
		setup_action(a, STOP)


func _let_escape(a: BugActor, sense: BugActor.Sense) -> void:
	if _water_ahead(a, sense):
		setup_action(a, DIVE)
		return
	_calc_direction(a, sense)
	_ground_clamp(a, sense)


func _dive(a: BugActor, sense: BugActor.Sense) -> void:
	if a.pos.y <= _water_y(a, sense):
		setup_action(a, DROWN)


func _calc_direction(a: BugActor, sense: BugActor.Sense) -> void:
	if sense != null and sense.bg.is_valid() and bool(sense.bg.call(a.pos).get("hit_wall_front", false)):
		a.angle_y = wrapf(a.angle_y + deg_to_rad(90.0), -PI, PI)
	a.rot.y = BugProgram.chase_angle(a.rot.y, a.angle_y, 0x800 * S16)


func _check_patience(a: BugActor, sense: BugActor.Sense) -> bool:
	## Only once it has left its rock unit (`ut_x/z == -1`); we approximate with
	## "has been in AVOID a while" — always allow the net/scoop scare here.
	if sense.net_swing_active and sense.net_swing_origin != Vector3.INF:
		if BugProgram.dist_xz(a.pos, sense.net_swing_origin / BugActor.GX_M) < 70.0:
			a.patience = 100.0
	if sense.player_swung_tool and sense.has_player():
		if BugProgram.dist_xz(a.pos, sense.player_position / BugActor.GX_M) < 70.0:
			a.patience = 100.0
	return a.patience > 90.0


func _ground_clamp(a: BugActor, sense: BugActor.Sense) -> void:
	var g: float = _ground_y(a, sense)
	if a.pos.y < g:
		a.pos.y = g
		if a.pos_speed.y < 0.0:
			a.pos_speed.y = 0.0


func _ground_y(a: BugActor, sense: BugActor.Sense) -> float:
	if sense != null and sense.bg.is_valid():
		return float(sense.bg.call(a.pos).get("ground_y", a.home.y))
	return a.home.y


func _water_y(a: BugActor, sense: BugActor.Sense) -> float:
	if sense != null and sense.bg.is_valid():
		return float(sense.bg.call(a.pos).get("water_y", -1e9))
	return -1e9


func _water_ahead(a: BugActor, sense: BugActor.Sense) -> bool:
	return sense != null and sense.bg.is_valid() and bool(sense.bg.call(a.pos).get("water_ahead", false))
