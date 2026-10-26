class_name Firefly
extends BugBehavior

## `ac_ins_hotaru.c` — firefly. Hovers 70 GX over the ground by water at night, bobbing
## ±10 GX (`fuwafuwa`) at 1.5 GX/frame and weaving ±67.5° about its target point once
## more than 30 GX off it (a wall pushes the target one unit over). Stressed (patience
## > 90) it veers away from the player — or back toward the acre centre once 240 GX out —
## and, calm again (< 10), re-centres on the unit below. Caught / released / timed out it
## rises away and its glow fades (`fade_out`, the `alpha2` ramp in `aINS_calc_alpha_time`). Type 27 is
## level-Y in the shared mover, so the program drives `pos_speed.y` itself.

enum { AVOID, LET_ESCAPE, FLY }

## `aIHT_anim_data` — the glow pulse (`_1E0` / `_1E4`).
const PULSE := [0.0, 1.0, 2.0, 3.0, 2.0, 1.0]
## `GetBgY_OnlyCenter_FromWpos(pos, −70)`.
const HOVER_GX := 70.0
## `aIHT_BGcheck` only nudges the target while within 200 GX of the acre centre.
const WALL_SHIFT_RANGE := 200.0


## The point it hovers about (`f32_work0/1`, GX x and z), the heading it is turning to
## (`s32_work1`, radians), the bob's phase (s16, `s32_work2`) and whether it is against a
## wall (`s32_work3`: the target shifts once per wall).
var target: Vector2 = Vector2.ZERO
var target_yaw: float = 0.0
var _bob_phase: int = 0
var _at_wall: bool = false

func actor_init(a: BugActor, released: bool) -> void:
	a.terrain_mode = BugActor.TerrainMode.GROUND
	a.item = 27
	if not released:
		a.pos.y = a.home.y + HOVER_GX
		a.home.y = a.pos.y
		_bob_phase = a._rng.randi_range(0, 65535)
		a.pos.x += a._rng.randf_range(-UNIT_GX * 0.5, UNIT_GX * 0.5)
		a.pos.z += a._rng.randf_range(-UNIT_GX * 0.5, UNIT_GX * 0.5)
		target = Vector2(a.pos.x, a.pos.z)
		a.speed_step = 0.0
		a.target_speed = 10.0 + a._rng.randf() * 15.0
		a.continue_timer = a._rng.randi_range(0, 4)
		setup_action(a, FLY)
	else:
		a.anim_frame = 0.0
		a.prev_anim_frame = 0.0
		a.opacity = 255
		a.prev_frame_opacity = 255
		a.fade_out = 0
		setup_action(a, LET_ESCAPE)


func pose_index(a: BugActor) -> int:
	return int(a.anim_frame)


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
				a.escaping = true
		FLY:
			a.action_proc = _fly
			a.flag = 0
			a.rot.x = 0.0


func _avoid_init(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 80
	a.rot.x = 0.0
	if a.catchable:
		## Off the player's facing ±60°.
		BugBehavior.heading_from_player_facing(a, deg_to_rad(120.0))
	_bob_phase = 0
	a.anim_frame = 0.0
	a.prev_anim_frame = 0.0
	a.opacity = 255
	a.prev_frame_opacity = 255
	a.fade_out = 0
	a.catchable = false


# ---- actions --------------------------------------------------

func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	_anime(a)
	if a.caught:
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.escaping:
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _anime(a: BugActor) -> void:
	## `aIHT_anime_proc` — the two-lobe glow crossfade: 25 a tick over 10 ticks, then the
	## pulse moves on a step.
	if a.timer > 0.0:
		a.timer -= a.n
		a.opacity = minf(a.opacity + 25.0 * a.n, 255.0)
		a.prev_frame_opacity = maxf(a.prev_frame_opacity - 25.0 * a.n, 0.0)
	else:
		a.timer += 10.0
		var step: int = int(a.continue_timer)
		a.prev_anim_frame = PULSE[step]
		a.opacity = 0.0
		a.prev_frame_opacity = 255.0
		step = (step + 1) % PULSE.size()
		a.continue_timer = step
		a.anim_frame = PULSE[step]


## The bob: a sine on a phase that turns a few hundred s16 a tick, the height eased half
## the way there each tick (the mover moves half `pos_speed` a tick).
func _fuwafuwa(a: BugActor, hard: bool) -> void:
	if not hard:
		_bob_phase += int((a._rng.randf() * float(0x600) + float(0x200)) * 0.5 * a.n)
	else:
		_bob_phase += roundi(0x400 * a.n)
		a.speed = 1.5
	_bob_phase &= 0xFFFF
	var ofs: float = sin(_bob_phase * MathUtil.S16) * 10.0
	var closed: float = 1.0 - pow(0.5, a.n)
	a.pos_speed.y = ((a.home.y + ofs) - a.pos.y) * closed / (0.5 * maxf(a.n, 0.0001))


func _fly(a: BugActor, sense: BugActor.Sense) -> void:
	_bg_check(a, sense)
	a.target_speed = 1.5
	a.speed_step = 0.1
	_fuwafuwa(a, false)
	if absf(target.x - a.pos.x) > 30.0 or absf(target.y - a.pos.z) > 30.0:
		var to_target: float = BugBehavior.angle_to(a.pos, Vector3(target.x, a.pos.y, target.y))
		## `+ (67.5° − RANDOM_F(135°))`.
		target_yaw = to_target + deg_to_rad(67.5) - a._rng.randf() * deg_to_rad(135.0)
		if a.patience > 90.0:
			var c: Vector2 = BugBehavior.acre_center(a, sense)
			var dx: float = c.x - a.pos.x
			var dz: float = c.y - a.pos.z
			if absf(dx) > 240.0 or absf(dz) > 240.0:
				target_yaw = BugBehavior.atans(dz, dx)
			else:
				target_yaw = a.player_angle_y + PI
			a.flag = 1
		elif a.flag == 1 and a.patience < 10.0:
			var u: Vector3 = BugBehavior.unit_center(sense, BugBehavior.unit_of(sense, a.pos))
			target = Vector2(u.x, u.z)
			a.flag = 0
	## `add_calc_short_angle2(world.angle.y, aIHT_TARGET_ANGLE, 1 − √0.9, 250, 0)` — the
	## shape keeps its own rotation.
	a.angle_y = MathUtil.short_angle2(
		a.angle_y, target_yaw, 1.0 - pow(sqrt(0.9), a.n), 250.0 * MathUtil.S16 * a.n
	)


## `aIHT_BGcheck`: the first frame against a front wall shifts the target one unit
## (by heading quadrant) while within 200 GX of the acre centre.
func _bg_check(a: BugActor, sense: BugActor.Sense) -> void:
	if not BugBehavior.wall_front(a, sense):
		_at_wall = false
		return
	if _at_wall:
		return
	_at_wall = true
	var c: Vector2 = BugBehavior.acre_center(a, sense)
	var dx: float = c.x - a.pos.x
	var dz: float = c.y - a.pos.z
	var deg: float = fposmod(rad_to_deg(a.angle_y), 360.0)
	if deg > 45.0 and deg <= 135.0:
		if dx >= -WALL_SHIFT_RANGE:
			target.x -= UNIT_GX
	elif deg > 135.0 and deg <= 225.0:
		if dz >= -WALL_SHIFT_RANGE:
			target.y -= UNIT_GX
	elif deg > 225.0 and deg <= 315.0:
		if dx <= WALL_SHIFT_RANGE:
			target.x += UNIT_GX
	else:
		if dz <= WALL_SHIFT_RANGE:
			target.y += UNIT_GX


func _avoid(a: BugActor, _sense: BugActor.Sense) -> void:
	_fuwafuwa(a, true)
	## Gravity grows 0.75 a tick and adds itself to the climb each tick.
	var was: float = a.gravity
	a.gravity += 0.75 * a.n
	a.pos_speed.y += (was + a.gravity) * 0.5 * a.n
