class_name BugAmenbo
extends BugProgram

## `ac_ins_amenbo.c` — pond skater. Rides 14 GX over the pond bed (`bg_height` −14,
## pulled down at up to 2 GX/frame) and darts in bursts: 2.3 GX/frame easing to a stop,
## a 0–59-frame rest, then a new heading ±60° off the last. Anything that is not water a
## unit ahead is a wall: it stops at once and turns about. Only a caught / released one
## leaves, flying off the player's facing ±60°. (The squash-and-stretch scale and ripple
## effect are presentation.)

enum { WAIT, LET_ESCAPE, MOVE, REST }



func actor_init(a: BugActor, released: bool) -> void:
	a.bg_range = UNIT_GX
	a.bg_height = -14.0
	a.item = 34
	if not released:
		a.pos.y = a.home.y + 14.0     ## `GetBgY_OnlyCenter_FromWpos(pos, −14)`
		a.home = a.pos
		a.bg_type = 2
		setup_action(a, MOVE)
	else:
		setup_action(a, LET_ESCAPE)


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


func on_release(a: BugActor) -> void:
	setup_action(a, LET_ESCAPE)


func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		LET_ESCAPE:
			a.action_proc = _let_escape
			a.life_time = 0
			a.alpha_time = 80
			a.gravity = 0.06
			a.max_velocity_y = 12.0
			a.speed = 4.0
			a.rot.x = 0.0
			if BugProgram.heading_from_player_facing(a, deg_to_rad(120.0)):
				a.rot.y = a.angle_y
			a.f_no_catch = true
			a.f_bit2 = true
		MOVE:
			a.action_proc = _move
			if a.s32_work[3] == 1:                       ## hit a wall → about-face
				a.angle_y += PI
			a.angle_y += a._rng.randf_range(-1.0, 1.0) * deg_to_rad(60.0)
			a.rot.y = a.angle_y
			a.gravity = 0.3
			a.max_velocity_y = -2.0
			a.target_speed = 0.0
			a.speed_step = 0.05 - a._rng.randf() * 0.03
			a.speed = 2.3
			a.s32_work[3] = 0
		REST:
			a.action_proc = _rest
			a.speed = 0.0
			a.speed_step = 0.0
			a.timer = 0 if a.s32_work[3] == 1 else int(2.0 * a._rng.randf() * 30.0)


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


func _move(a: BugActor, sense: BugActor.Sense) -> void:
	_hold_without_ground(a, sense)
	_bg(a, sense)
	if is_zero_approx(a.speed) or a.s32_work[3] == 1:
		setup_action(a, REST)


func _rest(a: BugActor, sense: BugActor.Sense) -> void:
	_bg(a, sense)
	_hold_without_ground(a, sense)
	a.timer -= 1
	if a.timer <= 0:
		setup_action(a, MOVE)


func _let_escape(a: BugActor, _sense: BugActor.Sense) -> void:
	a.anime0 += 0.5
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0
	a.gravity = minf(a.gravity + a.gravity * 0.05, 12.0)


## `aIAB_BGcheck`: a front wall latches `HIT_WALL`. On the field the pond bank is that
## wall; here, any unit a unit ahead that is not water (or a real wall / column).
func _bg(a: BugActor, sense: BugActor.Sense) -> void:
	if a.s32_work[3] == 1 or sense == null or sense.grid == null:
		return
	var ahead: Vector3 = a.pos + Vector3(sin(a.angle_y), 0.0, cos(a.angle_y)) * a.bg_range
	if BugProgram.wall_front(a, sense) or not BugBg.water_at(sense.grid, ahead):
		a.s32_work[3] = 1


## Without a ground sampler (no field) there is no bed to land on: hold the spawn height.
func _hold_without_ground(a: BugActor, sense: BugActor.Sense) -> void:
	if sense == null or not sense.ground.is_valid():
		a.pos.y = a.home.y
		a.pos_speed.y = 0.0
