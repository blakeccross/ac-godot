class_name BugAmenbo
extends BugProgram

## `ac_ins_amenbo.c` — pond skater. Darts across the water surface in short bursts
## (`MOVE`), decelerating to a stop, rests a moment, then picks a new heading. Only
## flees (straight up) when caught. Turns 180° on a wall.

enum { WAIT, LET_ESCAPE, MOVE, REST }

const UNIT_GX := 20.0


func actor_init(a: BugActor, released: bool) -> void:
	a.bg_range = UNIT_GX
	a.bg_height = -14.0
	a.item = 34
	if not released:
		a.pos.y = a.home.y
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
			if a._last_player_gx != Vector3.INF:
				a.angle_y = BugProgram.angle_to(a._last_player_gx, a.pos) + a._rng.randf_range(-1.0, 1.0) * deg_to_rad(60.0)
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
	a.pos.y = a.home.y                     ## kept on the surface
	_bg(a, sense)
	if is_zero_approx(a.speed) or a.s32_work[3] == 1:
		setup_action(a, REST)


func _rest(a: BugActor, sense: BugActor.Sense) -> void:
	_bg(a, sense)
	a.pos.y = a.home.y
	a.timer -= 1
	if a.timer <= 0:
		setup_action(a, MOVE)


func _let_escape(a: BugActor, _sense: BugActor.Sense) -> void:
	a.anime0 += 0.5
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0
	a.gravity = minf(a.gravity + a.gravity * 0.05, 12.0)


func _bg(a: BugActor, sense: BugActor.Sense) -> void:
	if sense != null and sense.bg.is_valid() and bool(sense.bg.call(a.pos).get("hit_wall_front", false)):
		a.s32_work[3] = 1
