class_name BugChou
extends BugProgram

## `ac_ins_chou.c` — butterflies (common / yellow / tiger / purple).
## Actions: AVOID, LET_ESCAPE, FLY, LANDING, HOVER, REST.
##
## FLY loops a 20 GX square around a patrol point (`f32_work0/1`) about 30 GX over the
## ground (tiger 40, purple 50), bobbing: under that height it kicks `pos_speed.y` to 2–3,
## otherwise it sinks at up to 2. Every lap the patrol point may hop to a neighbouring
## unit (`flower_search`). A common / yellow / tiger butterfly flying over a white-pansy
## unit lands on it (LANDING → HOVER → REST → FLY). Tiger and purple panic at patience
## > 90 (AVOID: faster, higher, away from the player) until patience drops under 70. Any
## butterfly in the outer unit ring of an acre escapes and fades.

enum { AVOID, LET_ESCAPE, FLY, LANDING, HOVER, REST }

const PT_X := [10.0, 10.0, -10.0, -10.0]
const PT_Z := [10.0, -10.0, 10.0, -10.0]
const CHK_X := [-1.0, 1.0, 1.0, -1.0]
const CHK_Z := [-1.0, 1.0, -1.0, 1.0]
## `rest_wait_data` (`aICH_landing`) — settle offset + bg_height per `light_flag`.
const REST_WAIT := [
	Vector3(-11.0, -22.0, -4.0),
	Vector3(10.0, -22.0, -8.0),
	Vector3(2.0, -24.0, 14.0),
]
## `aICH_check_ball` / `_player_net` / `_player_scoop`: 3600 = 60².
const SCARE_DIST := 60.0
## `aICH_actor_init`: `GetBgY_OnlyCenter_FromWpos(pos, 30)` — born 30 GX under the ground
## (the BG check lifts it onto it and `jump_ctrl` sends it up).
const BIRTH_DEPTH := 30.0

## This frame's sense, for the `*_init` procs that query the field.
var _s: BugActor.Sense = null
var _unit_resolved: bool = false


func actor_init(a: BugActor, released: bool) -> void:
	a.bg_type = 2
	match a.type:
		T_COMMON_BUTTERFLY: a.item = 0
		T_YELLOW_BUTTERFLY: a.item = 1
		T_TIGER_BUTTERFLY: a.item = 2
		T_PURPLE_BUTTERFLY: a.item = 3
	if not released:
		## `aICH_check_live_condition` is a spawn-time cull (height gap / bad unit) the
		## scheduler already applied.
		a.pos.y = a.home.y - BIRTH_DEPTH
		a.home = a.pos
		var cell: Vector2i = BugProgram.unit_of(null, a.pos)
		a.s32_work[1] = cell.x
		a.s32_work[2] = cell.y
		setup_action(a, FLY)
	else:
		setup_action(a, LET_ESCAPE)


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


func on_release(a: BugActor) -> void:
	setup_action(a, LET_ESCAPE)


# ---- setupAction ------------------------------------------------------

func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID:
			a.action_proc = _avoid
			a.bg_height = 0.0
			a.target_speed = 3.0
			a.speed_step = 0.3
			a.speed = 2.0
		LET_ESCAPE:
			a.action_proc = _let_escape
			_let_escape_init(a)
		FLY:
			a.action_proc = _fly
			_fly_init(a, _s)
		LANDING:
			a.action_proc = _landing
			a.light_flag = a.game_frame % 3
			a.pos_speed.y = 0.0
		HOVER:
			a.action_proc = _hover
			a.target_speed = 0.0
			a.speed_step = 0.0
			a.speed = 0.0
			a.timer = 10
		REST:
			a.action_proc = _hover
			a.anime0 = 1.0
			a.timer = int(0.5 * (30.0 + a._rng.randf() * 60.0))


func _let_escape_init(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 0x50
	a.rot.x = 0.0
	a.bg_height = 0.0
	a.flag = 0
	a.home.y = a.pos.y
	a.speed = 1.5
	## `player->shape_info.rotation.y + 21845·(rand − 0.5)`: off the player's facing ±60°.
	if BugProgram.heading_from_player_facing(a, deg_to_rad(120.0)):
		a.rot.y = a.angle_y
	a.f_no_catch = true
	a.f_bit2 = true


func _fly_init(a: BugActor, sense: BugActor.Sense) -> void:
	a.bg_height = 0.0
	a.gravity = 0.3
	a.max_velocity_y = -2.0
	a.target_speed = 2.0
	a.speed_step = 0.2
	a.s32_work[0] = 0
	a.flag = 0  ## `s32_work3`: the lap corner latch (the unit lives in s32_work1/2)
	a.f32_work[0] = a.pos.x
	a.f32_work[1] = a.pos.z
	a.f32_work[2] = 0.0
	a.f32_work[3] = 120.0
	_flower_search(a, sense)


# ---- actor_move ------------------------------------------------------

func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	_s = sense
	if not _unit_resolved:
		## The spawn unit was taken before the field grid was known.
		_unit_resolved = true
		var cell: Vector2i = BugProgram.unit_of(sense, a.home)
		a.s32_work[1] = cell.x
		a.s32_work[2] = cell.y
	if a.caught:
		a.alpha0 = 255
		_anime(a)
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2:
		setup_action(a, LET_ESCAPE)
		return
	_check_block_edge(a, sense)
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


## `aICH_check_block_edge`: the outer ring of units of any acre (in-block index 0 or 15)
## is off limits — the butterfly escapes and fades.
func _check_block_edge(a: BugActor, sense: BugActor.Sense) -> void:
	if a.action == LET_ESCAPE:
		return
	var u: Vector2i = BugProgram.unit_in_block(BugProgram.unit_of(sense, a.pos))
	if u.x < 1 or u.x > 14 or u.y < 1 or u.y > 14:
		setup_action(a, LET_ESCAPE)


# ---- actions -------------------------------------------------------

func _fly(a: BugActor, sense: BugActor.Sense) -> void:
	_anime(a)
	_bg_wall_check(a, sense)
	var base: float = -30.0
	if a.type == T_TIGER_BUTTERFLY:
		base = -40.0
	elif a.type == T_PURPLE_BUTTERFLY:
		base = -50.0
	_jump_ctrl(a, sense, base)
	_loop_move_ctrl(a, sense)
	match a.type:
		T_TIGER_BUTTERFLY:
			if a.patience > 90.0:
				setup_action(a, AVOID)
				return
			_rest_check(a, sense)
		T_PURPLE_BUTTERFLY:
			if a.patience > 90.0:
				setup_action(a, AVOID)
		_:
			_rest_check(a, sense)


func _landing(a: BugActor, sense: BugActor.Sense) -> void:
	_anime(a)
	if _check_patience(a, sense):
		var next: int = FLY
		if a.type == T_TIGER_BUTTERFLY or a.type == T_PURPLE_BUTTERFLY:
			next = AVOID
		setup_action(a, next)
		return
	## Settle on a corner of the flower unit, a little under flight height.
	var target: Vector3 = BugProgram.unit_center(sense, Vector2i(a.s32_work[1], a.s32_work[2]))
	var off: Vector3 = REST_WAIT[a.light_flag]
	target.x += off.x
	target.z += off.z
	a.bg_height = off.y
	if a.type == T_COMMON_BUTTERFLY or a.type == T_YELLOW_BUTTERFLY:
		a.bg_height -= 3.0
	var ang: float = BugProgram.angle_to(a.pos, target)
	a.rot.y = BugProgram.chase_angle(a.rot.y, ang, 0x1000 * MLib.S16)
	a.angle_y = a.rot.y
	if is_zero_approx(a.target_speed) or (
		absf(a.pos.x - target.x) < 2.0 and absf(a.pos.z - target.z) < 2.0
	):
		setup_action(a, HOVER)


func _hover(a: BugActor, sense: BugActor.Sense) -> void:
	if a.action == HOVER:
		_anime(a)
	if _check_patience(a, sense):
		var next: int = FLY
		if a.type == T_TIGER_BUTTERFLY or a.type == T_PURPLE_BUTTERFLY:
			next = AVOID
		setup_action(a, next)
		return
	a.timer -= 1
	if a.timer <= 0:
		var next: int = REST
		if a.action == REST:
			next = FLY
		setup_action(a, next)


func _avoid(a: BugActor, sense: BugActor.Sense) -> void:
	_anime(a)
	var base: float = -60.0
	if a.type == T_TIGER_BUTTERFLY:
		base = -80.0
	elif a.type == T_PURPLE_BUTTERFLY:
		base = -100.0
	_jump_ctrl(a, sense, base)
	_avoid_move_ctrl(a, sense)
	if a.patience < 70.0:
		var cell: Vector2i = BugProgram.unit_of(sense, a.pos)
		a.s32_work[1] = cell.x
		a.s32_work[2] = cell.y
		setup_action(a, FLY)


func _let_escape(a: BugActor, _sense: BugActor.Sense) -> void:
	_chou_fuwafuwa(a)
	a.gravity += 0.1
	_anime(a)


# ---- helpers ------------------------------------------------------

func _anime(a: BugActor) -> void:
	a.anime0 += 0.2
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0


## `aICH_jump_ctrl`: under `ground − base` (water surface over water) kick up 2–3 GX/frame,
## then sink toward `max_velocity_y` at half the gravity.
func _jump_ctrl(a: BugActor, sense: BugActor.Sense, base: float) -> void:
	var h: float = BugProgram.water_y(a, sense)
	if h <= -1e8:
		h = _ground_y_gx(a, sense)
	if a.pos.y < h - base:
		a.pos_speed.y = 2.0 + a._rng.randf()
	a.pos_speed.y = BugProgram.chase_f(a.pos_speed.y, a.max_velocity_y, 0.5 * a.gravity)


func _ground_y_gx(a: BugActor, sense: BugActor.Sense) -> float:
	if sense != null and sense.ground.is_valid():
		return float(sense.ground.call(a.pos).get("ground_y", a.home.y))
	if sense != null and sense.bg.is_valid():
		var r: Dictionary = sense.bg.call(a.pos)
		if r.has("ground_y"):
			return float(r["ground_y"])
	return a.home.y


## `aICH_loop_move_ctrl`: steer round the four corners of a 20 GX square about the patrol
## point, tighter (0x800) inside 15 GX of the corner; every full lap, `flower_search`.
func _loop_move_ctrl(a: BugActor, sense: BugActor.Sense) -> void:
	var idx: int = a.s32_work[0]
	var x: float = a.pos.x - (a.f32_work[0] + PT_X[idx])
	var z: float = a.pos.z - (a.f32_work[1] + PT_Z[idx])
	var sq: float = sqrt(x * x + z * z)
	var ang: float = BugProgram.atans(-z, -x)
	var step: float = (0x800 if sq < 15.0 else 0x400) * MLib.S16
	a.rot.y = BugProgram.chase_angle(a.rot.y, ang, step)
	a.angle_y = a.rot.y
	if x * CHK_X[idx] < 0.0 or z * CHK_Z[idx] < 0.0:
		if a.flag == 0:
			a.flag = 1
			a.s32_work[0] += 1
			if a.s32_work[0] > 3:
				a.s32_work[0] = 0
				_flower_search(a, sense)
	else:
		a.flag = 0


## `aICH_flower_search`: over a grown flower, stay half the time; otherwise try a
## neighbouring unit. The purple butterfly never moves its patrol point.
func _flower_search(a: BugActor, sense: BugActor.Sense) -> void:
	if a.type == T_PURPLE_BUTTERFLY:
		return
	var here: Vector2i = BugProgram.unit_of(sense, a.pos)
	var on_flower: bool = (
		sense != null and sense.layout != null and BugBg.has_kind(sense.layout, here, &"flower")
	)
	if a._rng.randf() < 0.5 and on_flower:
		return
	_flower_search_sub(a, sense, 1)


## `aICH_flower_search_sub`: step the patrol unit ±1 (±2 on the retry) inside the acre's
## inner 14×14; with `type != 0` the unit must take an NPC (`mFI_CheckFGNpcOn`: empty,
## flower, grass, sapling, item) and sit less than 20 GX above the butterfly.
func _flower_search_sub(a: BugActor, sense: BugActor.Sense, type: int) -> bool:
	var home_cell := Vector2i(a.s32_work[1], a.s32_work[2])
	var home_in: Vector2i = BugProgram.unit_in_block(home_cell)
	var step: int = 2 if type == 2 else 1
	var dx: int = (a._rng.randi_range(0, 2) - 1) * step
	var dz: int = (a._rng.randi_range(0, 2) - 1) * step
	if home_in.x + dx < 1 or home_in.x + dx > 14:
		dx = 0
	if home_in.y + dz < 1 or home_in.y + dz > 14:
		dz = 0
	var cell: Vector2i = home_cell + Vector2i(dx, dz)
	var grid: WorldGrid = sense.grid if sense != null else null
	var layout: WorldData = sense.layout if sense != null else null
	if type != 0 and (layout == null or not BugBg.npc_on(grid, layout, cell)):
		return false
	var center: Vector3 = BugProgram.unit_center(sense, cell)
	center.y = BugProgram.center_y(sense, center, a.home.y)
	if center.y - a.pos.y < 20.0:
		a.s32_work[1] = cell.x
		a.s32_work[2] = cell.y
		a.f32_work[0] = center.x
		a.f32_work[1] = center.z
		return true
	if type != 2:
		return _flower_search_sub(a, sense, 2)
	return false


## `aICH_rest_check`: after a 240-frame cooldown (`f32_work3` 120 − 0.5/frame), land when
## the unit below is a white pansy (`FLOWER_PANSIES0`).
func _rest_check(a: BugActor, sense: BugActor.Sense) -> void:
	if is_zero_approx(a.f32_work[3]):
		if sense != null and sense.layout != null:
			if BugBg.is_pansy0(sense.layout, BugProgram.unit_of(sense, a.pos)):
				setup_action(a, LANDING)
	else:
		a.f32_work[3] = maxf(a.f32_work[3] - 0.5, 0.0)


func _chou_fuwafuwa(a: BugActor) -> void:
	var save_ang: float = 10.0 * sin(a.flag * MLib.S16)
	a.flag += 0x800
	var cur_ang: float = 10.0 * sin(a.flag * MLib.S16)
	a.pos_speed.y = a.gravity + (cur_ang - save_ang)


## `aICH_BGcheck`: a front wall retargets the patrol unit (tiger / purple anywhere, the
## others only onto open units), then waits 10 frames before trying again.
func _bg_wall_check(a: BugActor, sense: BugActor.Sense) -> void:
	if a.f32_work[2] <= 0.0 and BugProgram.wall_front(a, sense):
		var type: int = 0 if (a.type == T_TIGER_BUTTERFLY or a.type == T_PURPLE_BUTTERFLY) else 1
		if _flower_search_sub(a, sense, type):
			a.f32_work[2] = 10.0
	a.f32_work[2] = maxf(a.f32_work[2] - 1.0, 0.0)


## `aICH_avoid_player`: straight away from the player, swinging ±22.5° every 32 frames.
func _avoid_player(a: BugActor) -> void:
	if not a.has_player_info:
		return
	var away: float = wrapf(a.player_angle_y + PI, -PI, PI)
	away += (0x1000 * MLib.S16) * (1.0 if (a.game_frame >> 5) & 1 else -1.0)
	a.rot.y = BugProgram.chase_angle(a.rot.y, away, 0x600 * MLib.S16)
	a.angle_y = a.rot.y


## `aICH_avoid_move_ctrl`: inside the acre's inner ring dodge the player; on the ring
## head for the acre centre.
func _avoid_move_ctrl(a: BugActor, sense: BugActor.Sense) -> void:
	var u: Vector2i = BugProgram.unit_in_block(BugProgram.unit_of(sense, a.pos))
	if u.x >= 1 and u.x < 15 and u.y >= 1 and u.y < 15:
		_avoid_player(a)
		return
	var c: Vector2 = BugProgram.acre_center(a, sense)
	var ang: float = BugProgram.atans(c.y - a.pos.z, c.x - a.pos.x)
	a.rot.y = BugProgram.chase_angle(a.rot.y, ang, 0x600 * MLib.S16)
	a.angle_y = a.rot.y


## `aICH_check_patience`: a stopped net (not on this butterfly) or a dig within 60 GX
## maxes patience; scared at patience ≥ 90.
func _check_patience(a: BugActor, sense: BugActor.Sense) -> bool:
	if BugProgram.near_xz(a, BugProgram.net_stop_pos(sense), SCARE_DIST):
		a.patience = 100.0
	elif BugProgram.near_xz(a, BugProgram.scoop_pos(sense), SCARE_DIST):
		a.patience = 100.0
	return a.patience >= 90.0
