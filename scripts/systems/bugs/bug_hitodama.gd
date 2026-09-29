class_name BugHitodama
extends BugProgram

## `ac_ins_hitodama.c` — the spirit / Wisp. Floats 40 GX over the ground (or water)
## and drifts at 0.3 GX/frame in lazy circles (turning 40–104 s16 a frame, flipping the
## turn on a 240–600-frame play-clock timer), bobbing (`fuwafuwa`). More than 160 GX
## from its acre centre it flips its turn whenever it heads within 22.5° of straight
## away, so it curls back in. When caught or the ghost event ends it rises away off
## the player's facing ±60° (`AVOID` / LET_ESCAPE). Type 40 is level-Y, so the program
## drives `pos_speed.y`.

enum { AVOID, LET_ESCAPE, FLY }

const RANGE := 8.0 * UNIT_GX     ## 8 units: 320 GX (corner + 320 = acre centre)
const HOVER := UNIT_GX           ## over the ground / water surface
const ANGL_ADD := [40.0, 56.0, 80.0, 104.0]
const MOVE_TIM := [240, 360, 480, 600]

var _placed: bool = false


func actor_init(a: BugActor, released: bool) -> void:
	a.bg_type = 2
	a.bg_range = 20.0
	a.item = -1
	if not released:
		## `GetBgY_OnlyCenter_FromWpos(pos, −40)` (water: surface + 40); settled on the
		## first frame once the field is known.
		a.pos.y = a.home.y + HOVER
		a.home.y = a.pos.y
		a.angle_y = a._rng.randf_range(-PI, PI)
		_set_move_info(a)
		a.s32_work[3] = a._rng.randi_range(0, 65535)   ## bob angle
		a.continue_timer = a._rng.randi_range(0, 4)
		setup_action(a, FLY)
	else:
		_placed = true
		setup_action(a, AVOID)


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


func on_release(a: BugActor) -> void:
	setup_action(a, LET_ESCAPE)


func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID, LET_ESCAPE:
			a.action_proc = _avoid
			a.life_time = 0
			a.alpha_time = 80
			a.rot.x = 0.0
			a.speed = 1.5
			if not a.f_no_catch and BugProgram.heading_from_player_facing(a, deg_to_rad(120.0)):
				a.home.y = a.pos.y
			a.s32_work[3] = 0
			a.f_no_catch = true
			if action == LET_ESCAPE:
				a.f_bit2 = true
		FLY:
			a.action_proc = _fly
			a.flag = 0
			a.rot.x = 0.0


## `aIHD_set_move_info`: turn rate and timer from the frame counter; the turn flips
## direction each time.
func _set_move_info(a: BugActor) -> void:
	var frame: int = a.game_frame
	var add: float = ANGL_ADD[frame & 3]
	if a.s32_work[1] > 0:
		add = -add
	a.s32_work[1] = int(add)
	a.s32_work[2] = MOVE_TIM[(frame >> 2) & 3]


func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if not _placed:
		_placed = true
		_settle(a, sense)
	a.anime0 += 0.5
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0
	if a.caught:
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2:
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _fuwafuwa(a: BugActor, hard: bool) -> void:
	var dir: int = 0x400 if hard else (0x100 + a._rng.randi_range(0, 0x2FF))
	var grav: float = 13.0 if hard else 10.0
	var last: float = sin(a.s32_work[3] * MLib.S16) * 10.0
	a.s32_work[3] = (a.s32_work[3] + dir) & 0xFFFF
	var now: float = grav * sin(a.s32_work[3] * MLib.S16)
	a.pos_speed.y = a.gravity + (now - last)


## Hover height over the unit centre, or over the water surface.
func _settle(a: BugActor, sense: BugActor.Sense) -> void:
	if sense == null or sense.grid == null:
		return
	var base: float = BugProgram.center_y(sense, a.pos, a.pos.y - HOVER)
	if BugBg.water_at(sense.grid, a.pos):
		var wy: float = BugProgram.water_y(a, sense)
		if wy > -1e8:
			base = wy
	a.pos.y = base + HOVER
	a.home.y = a.pos.y


func _fly(a: BugActor, sense: BugActor.Sense) -> void:
	a.target_speed = 0.3
	a.speed_step = 0.1
	_fuwafuwa(a, false)
	## `calc_move_drt`: beyond 160 GX of the acre centre, heading within 22.5° of straight
	## away from it flips the turn; nearer in, the turn flips when its timer runs out.
	var c: Vector2 = BugProgram.acre_center(a, sense)
	var centre := Vector3(c.x, a.pos.y, c.y)
	var d: float = BugProgram.dist_xz(a.pos, centre)
	if d > RANGE * 0.5:
		var away: float = BugProgram.angle_to(centre, a.pos)
		if absf(wrapf(a.angle_y - away, -PI, PI)) < deg_to_rad(22.5):
			_set_move_info(a)
	else:
		a.s32_work[2] -= 1
		if a.s32_work[2] < 0:
			_set_move_info(a)
	a.angle_y = wrapf(a.angle_y + a.s32_work[1] * MLib.S16, -PI, PI)
	a.rot.y = a.angle_y


func _avoid(a: BugActor, _sense: BugActor.Sense) -> void:
	_fuwafuwa(a, true)
	a.gravity += 0.1
