class_name BugDango
extends BugProgram

## `ac_ins_dango.c` — pill bug (and ant). The pill bug hides under its rock until the
## player strikes that rock's unit (`REFLECT_AXE` / `REFLECT_SCOOP`), pops up 12 GX/frame
## (`APPEAR`), curls on landing (`STOP`), then crawls off at 1.5 GX/frame along the
## player's facing ±60° (`AVOID`), sliding along walls. Only once it has crawled off the
## rock's unit does it scare — a stopped net, a dig or an axe hit within 70 GX curls it
## up again until patience falls under 50. Water ahead makes it dive and drown; 400 GX
## from its acre centre it retires (fades). Released ones crawl off the same way.
##
## In the original an ant is its own actor (`ac_ant.c`) that only becomes a dango-program
## insect once netted; here an ant simply crawls like a pill bug that is already out.

enum { AVOID, LET_ESCAPE, STOP, HIDE, APPEAR, DIVE, DROWN, RETIRE }

const ACTIVE_RANGE := 400.0
const SCARE := 70.0          ## net / scoop / axe, 4900 = 70²
## `21845 × (rand − 0.5)`: ±60° (a third of the circle) about the player's facing.
const HEADING_SPREAD := 21845.0 * MLib.S16

## The unit it spawned on (its rock); `(-1, -1)` once it has crawled off (`ut_x/z = −1`).
var _rock_cell: Vector2i = Vector2i(-1, -1)
var _cell_known: bool = false
## The crawl heading waits for the player's facing (no player on the spawn frame).
var _heading_pending: bool = false


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
	if a.type == T_ANT:
		_cell_known = true   ## already off any rock
		a.bg_type = 2
		setup_action(a, AVOID)
	else:
		setup_action(a, HIDE)


## Set by `BugField.spawn` to the spawn cell.
func set_rock_cell(cell: Vector2i) -> void:
	_rock_cell = cell
	_cell_known = true


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
			_avoid_init(a)
		LET_ESCAPE:
			a.action_proc = _let_escape
			a.life_time = 0
			a.alpha_time = 80
			a.rot.x = 0.0
			a.bg_type = 2
			a.gravity = 2.0
			a.max_velocity_y = -20.0
			_avoid_init(a)
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
			a.gravity = 2.0
			a.max_velocity_y = -20.0
			a.drawn = false
			a.move_proc = BugProgram.freeze_move
		APPEAR:
			a.action_proc = _appear
			a.move_proc = Callable()
			_avoid_init(a)
			a.drawn = true
			a.anime0 = 0.0
			a.pos_speed.y = 12.0
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
			a.f_no_catch = true
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


## `aIDG_avoid_init`: crawl 1.5 GX/frame off the player's facing ±60°.
func _avoid_init(a: BugActor) -> void:
	a.speed = 1.5
	a.target_speed = 1.5
	a.speed_step = 0.3
	a.anime0 = 1.0
	_heading_pending = not BugProgram.heading_from_player_facing(a, HEADING_SPREAD)
	if not _heading_pending:
		a.rot.y = a.angle_y


func _noop(_a: BugActor, _s: BugActor.Sense) -> void:
	pass


func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if not _cell_known:
		_cell_known = true
		_rock_cell = BugProgram.unit_of(sense, a.home)
	if _heading_pending and a.has_player_info:
		_heading_pending = false
		BugProgram.heading_from_player_facing(a, HEADING_SPREAD)
		a.rot.y = a.angle_y
	if a.caught:
		a.alpha0 = 255
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)
	_hold_without_ground(a, sense)


## `aIDG_check_strike_stone`: a rock strike on the unit it is under.
func _hide(a: BugActor, sense: BugActor.Sense) -> void:
	if sense == null:
		return
	if sense.player_action != BugActor.PlAct.REFLECT_AXE and sense.player_action != BugActor.PlAct.REFLECT_SCOOP:
		return
	if sense.player_action_cell == BugProgram.unit_of(sense, a.pos) or sense.player_action_cell == _rock_cell:
		setup_action(a, APPEAR)


func _appear(a: BugActor, sense: BugActor.Sense) -> void:
	if _on_ground(a, sense):
		setup_action(a, STOP)


func _stop(a: BugActor, sense: BugActor.Sense) -> void:
	if _water_check(a, sense):
		return
	if a.patience < 50.0:
		setup_action(a, AVOID)


func _avoid(a: BugActor, sense: BugActor.Sense) -> void:
	if _water_check(a, sense):
		return
	var c: Vector2 = BugProgram.acre_center(a, sense)
	if Vector2(c.x - a.pos.x, c.y - a.pos.z).length_squared() >= ACTIVE_RANGE * ACTIVE_RANGE:
		setup_action(a, RETIRE)
		return
	_calc_direction(a, sense)
	if a.bg_type == 4:
		## Still on the rock's unit: no scares until it crawls off it.
		if BugProgram.unit_of(sense, a.pos) != _rock_cell:
			_rock_cell = Vector2i(-1, -1)
			a.bg_type = 2
	elif _check_patience(a, sense):
		setup_action(a, STOP)


func _let_escape(a: BugActor, sense: BugActor.Sense) -> void:
	if not _water_check(a, sense):
		_calc_direction(a, sense)


func _dive(a: BugActor, sense: BugActor.Sense) -> void:
	if a.pos.y <= BugProgram.water_y(a, sense):
		setup_action(a, DROWN)


## `aIDG_chk_water_attr`: on the ground with water `bg_range + speed` ahead → DIVE.
func _water_check(a: BugActor, sense: BugActor.Sense) -> bool:
	if BugProgram.water_ahead(a, sense):
		setup_action(a, DIVE)
		return true
	return false


## `aIDG_calc_direction_angl`: a front wall turns it to run along the wall; the shape
## follows at 0x800.
func _calc_direction(a: BugActor, sense: BugActor.Sense) -> void:
	if BugProgram.wall_front(a, sense):
		a.angle_y = wrapf(BugProgram.wall_normal(a) + PI * 0.5, -PI, PI)
	a.rot.y = BugProgram.chase_angle(a.rot.y, a.angle_y, 0x800 * MLib.S16)


## `aIDG_check_patience`: off the rock only — stopped net, dig, axe hit within 70 GX.
func _check_patience(a: BugActor, sense: BugActor.Sense) -> bool:
	if _rock_cell.x != -1 or _rock_cell.y != -1:
		return false
	if BugProgram.near_xz(a, BugProgram.net_stop_pos(sense), SCARE):
		a.patience = 100.0
	elif BugProgram.near_xz(a, BugProgram.scoop_pos(sense), SCARE):
		a.patience = 100.0
	elif BugProgram.near_xz(a, BugProgram.axe_hit_pos(sense), SCARE):
		a.patience = 100.0
	return a.patience > 90.0


func _on_ground(a: BugActor, sense: BugActor.Sense) -> bool:
	if sense != null and sense.ground.is_valid():
		return a.bg_on_ground
	return a.pos.y <= a.home.y and a.pos_speed.y <= 0.0


## Without a ground sampler (no field) keep it on its spawn height.
func _hold_without_ground(a: BugActor, sense: BugActor.Sense) -> void:
	if (sense == null or not sense.ground.is_valid()) and a.drawn and a.pos.y < a.home.y:
		a.pos.y = a.home.y
		if a.pos_speed.y < 0.0:
			a.pos_speed.y = 0.0
