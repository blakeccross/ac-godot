class_name BugKera
extends BugProgram

## `ac_ins_kera.c` — mole cricket. Stays hidden underground until the player digs
## its unit with the shovel (`sense.player_action == DIG_SCOOP`), then pops out
## (`APPEAR`) and scurries around fast (`AVOID`), changing heading on walls, until
## it strays out of its acre range and burrows back down (`DUG`) or escapes. Can
## dive into water and drown.

enum { AVOID, LET_ESCAPE, HIDE, APPEAR, DIVE, DROWN, DUG }

const ACTIVE_RANGE_SQ := 160000.0   ## 400²


func actor_init(a: BugActor, released: bool) -> void:
	a.bg_range = 5.0
	a.item = 33
	a.f_bit4 = false
	if not released:
		a.f32_work[2] = a.home.x        ## acre-ish centre
		a.f32_work[3] = a.home.z
		setup_action(a, HIDE)
	else:
		if a._last_player_gx != Vector3.INF:
			a.angle_y = BugProgram.angle_to(a._last_player_gx, a.pos)
		a.drawn = true
		setup_action(a, LET_ESCAPE)


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


func on_release(a: BugActor) -> void:
	a.drawn = true
	setup_action(a, LET_ESCAPE)


func set_dig_cell(cell: Vector2i) -> void:
	_dig_cell = cell


var _dig_cell: Vector2i = Vector2i(-1, -1)


func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID:
			a.action_proc = _avoid
			a.target_speed = 1.5
			a.speed_step = 0.3
			a.rot.x = 0.0
			a.s32_work[0] = 0
		LET_ESCAPE:
			a.action_proc = _let_escape
			a.life_time = 0
			a.alpha_time = 80
			a.gravity = 1.0
			a.max_velocity_y = -20.0
			a.target_speed = 1.5
			a.speed_step = 0.3
			a.rot.x = 0.0
			a.bg_type = 2
			a.f_no_catch = true
			a.f_bit2 = true
		HIDE:
			a.action_proc = _hide
			a.drawn = false
			a.move_proc = BugProgram.freeze_move
		APPEAR:
			a.action_proc = _appear
			a.move_proc = Callable()
			a.target_speed = 1.5
			a.speed_step = 0.3
			a.speed = 1.5
			a.gravity = 1.0
			a.max_velocity_y = -20.0
			a.pos_speed.y = 5.0
			a.drawn = true
			a.bg_type = 4
		DIVE:
			a.action_proc = _dive
			a.target_speed = 1.5
			a.speed_step = 0.3
			a.speed = 1.5
			a.pos_speed.y = 8.0
			a.f_no_catch = true
		DROWN:
			a.action_proc = _noop
			a.f_destruct = true
			a.finished = true
		DUG:
			a.action_proc = _dug
			a.life_time = 0
			a.alpha_time = 80
			a.rot.x = 0.0
			a.bg_type = 0
			a.gravity = 0.01
			a.max_velocity_y = -0.2
			a.pos_speed.y = 0.0
			a.speed = 0.0
			a.target_speed = 0.0
			a.speed_step = 0.0
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
	if sense == null or sense.player_action != BugActor.PlAct.DIG_SCOOP:
		return
	if _dig_cell.x < 0 or sense.player_action_cell == _dig_cell:
		if a._last_player_gx != Vector3.INF:
			a.angle_y = BugProgram.angle_to(a._last_player_gx, a.pos) + a._rng.randf_range(-1.0, 1.0) * deg_to_rad(60.0)
		setup_action(a, APPEAR)


func _appear(a: BugActor, sense: BugActor.Sense) -> void:
	a.rot.x = BugProgram.atans(a.speed, -a.pos_speed.y)
	if a.pos.y <= _ground_y(a, sense) and a.pos_speed.y <= 0.0:
		a.pos.y = _ground_y(a, sense)
		a.pos_speed.y = 0.0
		setup_action(a, AVOID)


func _avoid(a: BugActor, sense: BugActor.Sense) -> void:
	a.rot.x = BugProgram.chase_angle(a.rot.x, 0.0, 0x1000 * S16)
	a.s32_work[0] -= 1
	if a.s32_work[0] <= 0:
		a.target_speed = (1.1 - a._rng.randf() * 0.2) * 1.5
		a.s32_work[0] = 10
	if _water_ahead(a, sense):
		setup_action(a, DIVE)
		return
	var dx: float = a.f32_work[2] - a.pos.x
	var dz: float = a.f32_work[3] - a.pos.z
	if dx * dx + dz * dz >= ACTIVE_RANGE_SQ:
		setup_action(a, DUG if _on_hole(a, sense) else LET_ESCAPE)
		return
	_calc_direction(a, sense)
	_ground_clamp(a, sense)


func _let_escape(a: BugActor, sense: BugActor.Sense) -> void:
	if _water_ahead(a, sense):
		setup_action(a, DIVE)
		return
	_calc_direction(a, sense)
	_ground_clamp(a, sense)


func _dive(a: BugActor, sense: BugActor.Sense) -> void:
	a.rot.x = BugProgram.atans(a.speed, -a.pos_speed.y)
	if a.pos.y <= _water_y(a, sense):
		setup_action(a, DROWN)


func _dug(a: BugActor, _sense: BugActor.Sense) -> void:
	a.rot.x = BugProgram.chase_angle(a.rot.x, deg_to_rad(157.5), 0x300 * S16)


func _calc_direction(a: BugActor, sense: BugActor.Sense) -> void:
	if sense != null and sense.bg.is_valid() and bool(sense.bg.call(a.pos).get("hit_wall_front", false)):
		a.angle_y = wrapf(a.angle_y + PI * 0.5, -PI, PI)
	a.rot.y = BugProgram.chase_angle(a.rot.y, a.angle_y, 0x800 * S16)


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


func _on_hole(a: BugActor, sense: BugActor.Sense) -> bool:
	return sense != null and sense.bg.is_valid() and bool(sense.bg.call(a.pos).get("hole", false))
