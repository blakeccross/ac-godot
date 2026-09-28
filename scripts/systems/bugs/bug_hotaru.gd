class_name BugHotaru
extends BugProgram

## `ac_ins_hotaru.c` — firefly. Hovers 70 GX over the ground by water at night, bobbing
## ±10 GX (`fuwafuwa`) at 1.5 GX/frame and weaving ±67.5° about its target point once
## more than 30 GX off it (a wall pushes the target one unit over). Stressed (patience
## > 90) it veers away from the player — or back toward the acre centre once 240 GX out —
## and, calm again (< 10), re-centres on the unit below. Caught / released / timed out it
## rises away and its glow fades (`alpha2` ramp in `aINS_calc_alpha_time`). Type 27 is
## level-Y in the shared mover, so the program drives `pos_speed.y` itself.

enum { AVOID, LET_ESCAPE, FLY }

## `aIHT_anim_data` — the glow pulse (`_1E0` / `_1E4`).
const PULSE := [0.0, 1.0, 2.0, 3.0, 2.0, 1.0]
## `GetBgY_OnlyCenter_FromWpos(pos, −70)`.
const HOVER_GX := 70.0
## `aIHT_BGcheck` only nudges the target while within 200 GX of the acre centre.
const WALL_SHIFT_RANGE := 200.0


func actor_init(a: BugActor, released: bool) -> void:
	a.bg_type = 2
	a.item = 27
	if not released:
		a.pos.y = a.home.y + HOVER_GX
		a.home.y = a.pos.y
		a.s32_work[2] = a._rng.randi_range(0, 65535)   ## float angle
		a.pos.x += a._rng.randf_range(-UNIT_GX * 0.5, UNIT_GX * 0.5)
		a.pos.z += a._rng.randf_range(-UNIT_GX * 0.5, UNIT_GX * 0.5)
		a.f32_work[0] = a.pos.x       ## target x
		a.f32_work[1] = a.pos.z       ## target z
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
	if not a.f_no_catch:
		## Off the player's facing ±60°.
		BugProgram.heading_from_player_facing(a, deg_to_rad(120.0))
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
	var ofs: float = sin(a.s32_work[2] * MLib.S16) * 10.0
	a.pos_speed.y = (a.home.y + ofs) - a.pos.y


func _fly(a: BugActor, sense: BugActor.Sense) -> void:
	_bg_check(a, sense)
	a.target_speed = 1.5
	a.speed_step = 0.1
	_fuwafuwa(a, false)
	if absf(a.f32_work[0] - a.pos.x) > 30.0 or absf(a.f32_work[1] - a.pos.z) > 30.0:
		var to_target: float = BugProgram.angle_to(a.pos, Vector3(a.f32_work[0], a.pos.y, a.f32_work[1]))
		## `+ (67.5° − RANDOM_F(135°))`.
		a.s32_work[1] = int((to_target + deg_to_rad(67.5) - a._rng.randf() * deg_to_rad(135.0)) / MLib.S16)
		if a.patience > 90.0:
			var c: Vector2 = BugProgram.acre_center(a, sense)
			var dx: float = c.x - a.pos.x
			var dz: float = c.y - a.pos.z
			if absf(dx) > 240.0 or absf(dz) > 240.0:
				a.s32_work[1] = int(BugProgram.atans(dz, dx) / MLib.S16)
			else:
				a.s32_work[1] = int((a.player_angle_y + PI) / MLib.S16)
			a.flag = 1
		elif a.flag == 1 and a.patience < 10.0:
			var u: Vector3 = BugProgram.unit_center(sense, BugProgram.unit_of(sense, a.pos))
			a.f32_work[0] = u.x
			a.f32_work[1] = u.z
			a.flag = 0
	## `add_calc_short_angle2(world.angle.y, aIHT_TARGET_ANGLE, 1 − √0.9, 250, 0)` — the
	## shape keeps its own rotation.
	a.angle_y = MLib.short_angle2(a.angle_y, a.s32_work[1] * MLib.S16, 1.0 - sqrt(0.9), 250.0 * MLib.S16)


## `aIHT_BGcheck`: the first frame against a front wall shifts the target one unit
## (by heading quadrant) while within 200 GX of the acre centre.
func _bg_check(a: BugActor, sense: BugActor.Sense) -> void:
	if not BugProgram.wall_front(a, sense):
		a.s32_work[3] = 0
		return
	if a.s32_work[3] != 0:
		return
	a.s32_work[3] = 1
	var c: Vector2 = BugProgram.acre_center(a, sense)
	var dx: float = c.x - a.pos.x
	var dz: float = c.y - a.pos.z
	var deg: float = fposmod(rad_to_deg(a.angle_y), 360.0)
	if deg > 45.0 and deg <= 135.0:
		if dx >= -WALL_SHIFT_RANGE:
			a.f32_work[0] -= UNIT_GX
	elif deg > 135.0 and deg <= 225.0:
		if dz >= -WALL_SHIFT_RANGE:
			a.f32_work[1] -= UNIT_GX
	elif deg > 225.0 and deg <= 315.0:
		if dx <= WALL_SHIFT_RANGE:
			a.f32_work[0] += UNIT_GX
	else:
		if dz <= WALL_SHIFT_RANGE:
			a.f32_work[1] += UNIT_GX


func _avoid(a: BugActor, _sense: BugActor.Sense) -> void:
	_fuwafuwa(a, true)
	a.gravity += 0.75
	a.pos_speed.y += a.gravity
