class_name BugKera
extends BugProgram

## `ac_ins_kera.c` — mole cricket. Hidden underground until the player digs its unit
## (`DIG_SCOOP` on the unit it is in); then it pops out (5 GX/frame up, gravity 1) off the
## player's facing ±60° and scurries at 1.5 GX/frame (re-rolled ±10% every 10 frames),
## sliding along walls. Leaving the dug unit turns column collision on. 400 GX from its
## acre centre it burrows (`DUG`) if it stands on a hole, else runs off (`LET_ESCAPE`).
## Water ahead makes it dive and drown. Released ones run off the player's facing ±60°.
## (The body's squash-and-stretch and the dirt / sound effects are presentation.)

enum { AVOID, LET_ESCAPE, HIDE, APPEAR, DIVE, DROWN, DUG }

const ACTIVE_RANGE := 400.0

## The unit it hides in (`ut_x/z`), set by `BugField.spawn`; else its spawn unit.
var _dig_cell: Vector2i = Vector2i(-1, -1)


func actor_init(a: BugActor, released: bool) -> void:
	a.bg_range = 5.0
	a.item = 33
	a.f_bit4 = false
	if not released:
		setup_action(a, HIDE)
	else:
		_set_avoid_player_angl(a)
		a.drawn = true
		setup_action(a, LET_ESCAPE)


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


func on_release(a: BugActor) -> void:
	a.drawn = true
	setup_action(a, LET_ESCAPE)


func set_dig_cell(cell: Vector2i) -> void:
	_dig_cell = cell


## `aIKR_set_avoid_player_angl`: the player's facing ±60°.
func _set_avoid_player_angl(a: BugActor) -> void:
	if BugProgram.heading_from_player_facing(a, deg_to_rad(120.0)):
		a.rot.y = a.angle_y


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
			a.bg_type = 4   ## no unit columns until it leaves the dug unit
		DIVE:
			a.action_proc = _dive
			a.target_speed = 1.5
			a.speed_step = 0.3
			a.speed = 1.5
			a.pos_speed.y = 8.0
			a.f_no_catch = true
		DROWN:
			a.action_proc = _noop
			a.f_no_catch = true
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
	if _dig_cell.x < 0:
		_dig_cell = BugProgram.unit_of(sense, a.home)
	if a.caught:
		a.alpha0 = 255
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)
	_hold_without_ground(a, sense)


## `aIKR_check_dig_hole_scoop`: a dig on the unit it is in.
func _hide(a: BugActor, sense: BugActor.Sense) -> void:
	if sense == null or sense.player_action != BugActor.PlAct.DIG_SCOOP:
		return
	if sense.player_action_cell == BugProgram.unit_of(sense, a.pos) or sense.player_action_cell == _dig_cell:
		_set_avoid_player_angl(a)
		setup_action(a, APPEAR)


func _appear(a: BugActor, sense: BugActor.Sense) -> void:
	a.rot.x = BugProgram.atans(a.speed, -a.pos_speed.y)
	if _on_ground(a, sense):
		setup_action(a, AVOID)


func _avoid(a: BugActor, sense: BugActor.Sense) -> void:
	a.rot.x = BugProgram.chase_angle(a.rot.x, 0.0, 0x1000 * MLib.S16)
	a.s32_work[0] -= 1
	if a.s32_work[0] <= 0:
		a.target_speed = (1.1 - a._rng.randf() * 0.2) * 1.5
		a.s32_work[0] = 10
	if BugProgram.water_ahead(a, sense):
		setup_action(a, DIVE)
		return
	var c: Vector2 = BugProgram.acre_center(a, sense)
	if Vector2(c.x - a.pos.x, c.y - a.pos.z).length_squared() >= ACTIVE_RANGE * ACTIVE_RANGE:
		setup_action(a, DUG if _on_hole(a, sense) else LET_ESCAPE)
		return
	if a.bg_type == 4 and BugProgram.unit_of(sense, a.pos) != _dig_cell:
		a.bg_type = 2
	_calc_direction(a, sense)


func _let_escape(a: BugActor, sense: BugActor.Sense) -> void:
	if BugProgram.water_ahead(a, sense):
		setup_action(a, DIVE)
		return
	_calc_direction(a, sense)


func _dive(a: BugActor, sense: BugActor.Sense) -> void:
	a.rot.x = BugProgram.atans(a.speed, -a.pos_speed.y)
	if a.pos.y <= BugProgram.water_y(a, sense):
		setup_action(a, DROWN)


func _dug(a: BugActor, _sense: BugActor.Sense) -> void:
	a.rot.x = BugProgram.chase_angle(a.rot.x, deg_to_rad(157.5), 0x300 * MLib.S16)


## `aIKR_calc_direction_angl`: a front wall turns it to run along the wall; the shape
## follows at 0x800.
func _calc_direction(a: BugActor, sense: BugActor.Sense) -> void:
	if BugProgram.wall_front(a, sense):
		a.angle_y = wrapf(BugProgram.wall_normal(a) + PI * 0.5, -PI, PI)
	a.rot.y = BugProgram.chase_angle(a.rot.y, a.angle_y, 0x800 * MLib.S16)


func _on_ground(a: BugActor, sense: BugActor.Sense) -> bool:
	if sense != null and sense.ground.is_valid():
		return a.bg_on_ground
	return a.pos.y <= a.home.y and a.pos_speed.y <= 0.0


## Without a ground sampler (no field) keep it on its spawn height.
func _hold_without_ground(a: BugActor, sense: BugActor.Sense) -> void:
	if (sense == null or not sense.ground.is_valid()) and a.drawn and a.bg_type != 0 \
			and a.pos.y < a.home.y:
		a.pos.y = a.home.y
		if a.pos_speed.y < 0.0:
			a.pos_speed.y = 0.0


## `mCoBG_CheckHole_OrgAttr` under it.
func _on_hole(a: BugActor, sense: BugActor.Sense) -> bool:
	return sense != null and sense.bg.is_valid() and bool(sense.bg.call(a.pos).get("hole", false))
