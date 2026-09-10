class_name BugHotaru
extends BugProgram

## `ac_ins_hotaru.c` — firefly. Hovers near water at night, drifting between random
## points ~30 GX apart with a gentle vertical bob (`fuwafuwa`), pulsing its glow.
## When scared it rises fast and its light fades out (`alpha2` ramp in
## `aINS_calc_alpha_time`). Type 27 is level-Y in the shared mover, so the program
## drives `pos_speed.y` itself.

enum { AVOID, LET_ESCAPE, FLY }

## `aIHT_anim_data` — the glow pulse (`_1E0` / `_1E4`).
const PULSE := [0.0, 1.0, 2.0, 3.0, 2.0, 1.0]
const UNIT_GX := 20.0


func actor_init(a: BugActor, released: bool) -> void:
	a.bg_type = 2
	a.item = 27
	if not released:
		a.pos.y = a.home.y            ## already at ~70 GX above ground from spawn
		a.home = a.pos
		a.s32_work[2] = a._rng.randi_range(0, 65535)   ## float angle
		a.pos.x += a._rng.randf_range(-UNIT_GX * 0.5, UNIT_GX * 0.5)
		a.pos.z += a._rng.randf_range(-UNIT_GX * 0.5, UNIT_GX * 0.5)
		a.f32_work[0] = a.pos.x       ## target x
		a.f32_work[1] = a.pos.z       ## target z
		a.f32_work[2] = a.home.x      ## acre-ish centre x
		a.f32_work[3] = a.home.z
		a.speed_step = 0.0
		a.target_speed = 10.0 + a._rng.randf() * 15.0
		a.continue_timer = a._rng.randi_range(0, 4)
		setup_action(a, FLY)
	else:
		a.anime0 = 0.0
		a.anime1 = 0.0
		a.alpha0 = 255
		a.alpha1 = 255
		a.alpha2 = 0
		setup_action(a, LET_ESCAPE)


func pose_index(a: BugActor) -> int:
	return int(a.anime0)


func on_release(a: BugActor) -> void:
	setup_action(a, LET_ESCAPE)


# ---- setupAction ----------------------------------------------

func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID, LET_ESCAPE:
			a.action_proc = _avoid
			_avoid_init(a)
			if action == LET_ESCAPE:
				a.f_bit2 = true
		FLY:
			a.action_proc = _fly
			a.flag = 0
			a.rot.x = 0.0


func _avoid_init(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 80
	a.rot.x = 0.0
	if not a.f_no_catch and a._last_player_gx != Vector3.INF:
		a.angle_y = BugProgram.angle_to(a.pos, a._last_player_gx) + a._rng.randf_range(-1.0, 1.0) * deg_to_rad(120.0)
	a.s32_work[2] = 0
	a.s32_work[0] = 0
	a.anime0 = 0.0
	a.anime1 = 0.0
	a.alpha0 = 255
	a.alpha1 = 255
	a.alpha2 = 0
	a.f_no_catch = true


# ---- actions --------------------------------------------------

func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	_anime(a)
	if a.caught:
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2:
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _anime(a: BugActor) -> void:
	## `aIHT_anime_proc` — the two-lobe glow crossfade.
	if a.timer > 0:
		a.timer -= 1
		a.alpha0 = mini(a.alpha0 + 25, 255)
		a.alpha1 = maxi(a.alpha1 - 25, 0)
	else:
		a.timer = 10
		a.anime1 = PULSE[a.continue_timer]
		a.alpha0 = 0
		a.alpha1 = 255
		a.continue_timer += 1
		if a.continue_timer > 5:
			a.continue_timer = 0
		a.anime0 = PULSE[a.continue_timer]


func _fuwafuwa(a: BugActor, hard: bool) -> void:
	if not hard:
		a.s32_work[2] += int((a._rng.randf() * float(0x600) + float(0x200)) * 0.5)
	else:
		a.s32_work[2] += 0x400
		a.speed = 1.5
	var ofs: float = sin(a.s32_work[2] * S16) * 10.0
	a.pos_speed.y = (a.home.y + ofs) - a.pos.y


func _fly(a: BugActor, sense: BugActor.Sense) -> void:
	a.target_speed = 1.5
	a.speed_step = 0.1
	_fuwafuwa(a, false)
	if absf(a.f32_work[0] - a.pos.x) > 30.0 or absf(a.f32_work[1] - a.pos.z) > 30.0:
		var to_target: float = BugProgram.angle_to(a.pos, Vector3(a.f32_work[0], a.pos.y, a.f32_work[1]))
		a.s32_work[1] = int((to_target + a._rng.randf_range(-1.0, 1.0) * deg_to_rad(67.5)) / S16)
		if a.patience > 90.0:
			var dx: float = a.f32_work[2] - a.pos.x
			var dz: float = a.f32_work[3] - a.pos.z
			if absf(dx) > 240.0 or absf(dz) > 240.0:
				a.s32_work[1] = int(BugProgram.atans(dz, dx) / S16)
			elif sense.has_player():
				var to_pl: float = BugProgram.angle_to(a.pos, sense.player_position / BugActor.GX_M)
				a.s32_work[1] = int((to_pl + PI) / S16)
			a.flag = 1
		elif a.flag == 1 and a.patience < 10.0:
			a.f32_work[0] = a.pos.x
			a.f32_work[1] = a.pos.z
			a.flag = 0
	## Smooth heading chase toward the target angle.
	a.angle_y = BugProgram.chase_angle(a.angle_y, a.s32_work[1] * S16, 0x400 * S16)
	a.rot.y = a.angle_y


func _avoid(a: BugActor, _sense: BugActor.Sense) -> void:
	_fuwafuwa(a, true)
	a.gravity += 0.75
	a.pos_speed.y += a.gravity
