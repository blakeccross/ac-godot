class_name BugBatta
extends BugProgram

## `ac_ins_batta.c` — locusts (long / migratory) and crickets (field / grasshopper /
## bell / pine). Ground hoppers: pick a heading roughly back over the shoulder whose
## landing spot (53 GX, migratory 218) is dry and within 40 GX of their height, ease
## round to it, wait 2·(120 + game_frame % 240) frames, then hop (locusts outside the
## first 20 frames of each 200-frame window, crickets only inside it). A stopped net or
## a dig within 70 GX sends them hopping away from the player every 8 frames until
## patience drops under 85; outside 240 GX of the acre centre they hop back toward it.
## Released ones start 40 GX over the player and leap off the player's facing ±60°.
##
## Ground height / water come from `sense.bg`; with none, flat ground at the spawn
## plane and no water.

enum { AVOID, LET_ESCAPE, CHANGE_DIRECTION, WAIT, JUMP, DROWN }

## `range[]` (`aIBT_chg_direction`) — turn spread per attempt, s16.
const TURN_RANGE := [
	4096.0, 4096.0, 8192.0, 8192.0, 8192.0, 12288.0, 12288.0, 12288.0,
	12288.0, 12288.0, 16384.0, 16384.0, 16384.0, 16384.0, 16384.0, 16384.0,
]
## `aIBT_chk_active_range`: 240 GX from acre centre (57600 = 240²).
const ACTIVE_RANGE_SQ := 57600.0

## The field the acre centre is measured on (the latest frame's sense).
var _range_sense: BugActor.Sense = null


func actor_init(a: BugActor, released: bool) -> void:
	a.gravity = 0.2
	a.max_velocity_y = -20.0
	a.bg_type = 2
	a.f_bit4 = false
	match a.type:
		T_LONG_LOCUST: a.item = 13
		T_MIGRATORY_LOCUST: a.item = 14
		T_CRICKET: a.item = 15
		T_GRASSHOPPER: a.item = 16
		T_BELL_CRICKET: a.item = 17
		T_PINE_CRICKET: a.item = 18
	if not released:
		setup_action(a, CHANGE_DIRECTION)
	else:
		if a.has_player_info:
			a.pos.y = a.player_pos.y + 40.0
		setup_action(a, LET_ESCAPE)


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


func on_release(a: BugActor) -> void:
	setup_action(a, LET_ESCAPE)


# ---- setupAction --------------------------------------------------

func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID:
			a.action_proc = _avoid
			_avoid_init(a)
		LET_ESCAPE:
			a.action_proc = _let_escape
			_let_escape_init(a)
		CHANGE_DIRECTION:
			a.action_proc = _chg_direction
			a.s32_work[0] = 0
			a.anime0 = 0.0
			a.speed = 0.0
		WAIT:
			a.action_proc = _wait
			_wait_init(a)
		JUMP:
			a.action_proc = _jump
			a.pos_speed.y = 4.0
			a.speed = 5.5
			a.gravity = 0.7
		DROWN:
			a.action_proc = _noop
			a.f_destruct = true
			a.finished = true


func _noop(_a: BugActor, _s: BugActor.Sense) -> void:
	pass


func _avoid_init(a: BugActor) -> void:
	a.gravity = 0.2
	a.timer = 0
	## Away from the player ±45°.
	if a.has_player_info:
		a.angle_y = wrapf(
			a.player_angle_y + PI + a._rng.randf_range(-1.0, 1.0) * (8192.0 * MLib.S16), -PI, PI
		)
		a.rot.y = a.angle_y


func _let_escape_init(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 80
	a.gravity = 0.2
	a.timer = 0
	a.speed = 5.0
	a.pos_speed.y = 3.0
	## Off the player's facing (`shape_info.rotation.y + 21845·(rand − 0.5)`), not toward them.
	if BugProgram.heading_from_player_facing(a, 21845.0 * MLib.S16):
		a.rot.y = a.angle_y
	a.f_no_catch = true
	a.f_bit2 = true


func _wait_init(a: BugActor) -> void:
	if not _in_active_range(a):
		a.timer = 60
	else:
		a.timer = int(2.0 * (120.0 + float(a.game_frame % 240)))


# ---- actions ----------------------------------------------------

func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if a.caught:
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2:
		setup_action(a, LET_ESCAPE)
		return
	_range_sense = sense
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _chg_direction(a: BugActor, sense: BugActor.Sense) -> void:
	var back: Array = _range_angle(a)
	if not bool(back[0]):
		a.angle_y = float(back[1])
		setup_action(a, WAIT)
		return
	var idx: int = clampi(a.s32_work[0], 0, TURN_RANGE.size() - 1)
	var ang: float = a.rot.y + PI + TURN_RANGE[idx] * MLib.S16 * a._rng.randf_range(-1.0, 1.0)
	var mod: float = 218.0 if a.type == T_MIGRATORY_LOCUST else 53.0
	var probe: Vector3 = a.pos + Vector3(sin(ang) * mod, 0.0, cos(ang) * mod)
	var ok: bool = true
	var water: bool = false
	if sense != null and sense.bg.is_valid():
		var r: Dictionary = sense.bg.call(probe)
		var bg_y: float = float(r.get("ground_y", a.home.y))
		water = bool(r.get("water", false))  ## `mCoBG_CheckWaterAttribute(attr)`
		ok = absf(a.pos.y - bg_y) < 40.0
	if ok and not water:
		a.angle_y = ang
		setup_action(a, WAIT)
	else:
		a.s32_work[0] += 1
		if a.s32_work[0] > 15:
			setup_action(a, WAIT)


func _wait(a: BugActor, sense: BugActor.Sense) -> void:
	if _in_water(a, sense):
		setup_action(a, DROWN)
		return
	if _check_patience(a, sense):
		setup_action(a, AVOID)
		return
	## Ease shape yaw toward the target heading:
	## `add_calc_short_angle2(rot.y, angle.y, CALC_EASE(0.5), 0x2000, 0)` (not frame-scaled).
	a.rot.y = MLib.short_angle2(a.rot.y, a.angle_y, MLib.HALF_FRACTION, 0x2000 * MLib.S16)
	if a.type == T_BELL_CRICKET and _on_ground(a, sense) and a.patience < 20.0:
		a.anime0 += 1.0
		if a.anime0 >= 2.0:
			a.anime0 -= 2.0
	if a.timer > 0:
		a.timer -= 1
		return
	## `play->game_frame % 200`: every hopper shares the play clock — locusts jump unless the
	## timer runs out in the first 20 frames of a 200-frame window, crickets only then.
	var action: int = CHANGE_DIRECTION
	var window: int = sense.game_frame % 200 if sense != null else a._rng.randi_range(0, 199)
	if not _in_active_range(a):
		action = JUMP
	elif a.type == T_LONG_LOCUST or a.type == T_MIGRATORY_LOCUST:
		if window > 20:
			action = JUMP
	elif window < 20:
		action = JUMP
	setup_action(a, action)


func _jump(a: BugActor, sense: BugActor.Sense) -> void:
	if _on_ground(a, sense):
		setup_action(a, CHANGE_DIRECTION)


func _avoid(a: BugActor, sense: BugActor.Sense) -> void:
	a.anime0 += (1.0 if a.type == T_BELL_CRICKET else 0.3)
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0
	if _in_water(a, sense):
		setup_action(a, DROWN)
		return
	if a.caught or not _on_ground(a, sense):
		return
	if a.timer > 0:
		a.timer -= 1
		a.speed = 0.0
		return
	a.timer = 8
	if a.patience < 85.0:
		a.timer = int(2.0 * (5.0 + a._rng.randf() * 10.0))
		setup_action(a, CHANGE_DIRECTION)
		return
	## Away from the player inside the active range; outside it, back toward the acre centre
	## (`aIBT_chk_active_range` writes that angle).
	var home: Array = _range_angle(a)
	var ang: float = float(home[1])
	if bool(home[0]):
		ang = a.rot.y
		if a.has_player_info:
			ang = a.player_angle_y + PI
	_jump_angle(a, sense, ang)
	_set_avoid_jump_spd(a, sense)


func _let_escape(a: BugActor, sense: BugActor.Sense) -> void:
	a.anime0 += (1.0 if a.type == T_BELL_CRICKET else 0.3)
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0
	if _in_water(a, sense):
		setup_action(a, DROWN)
		return
	if not _on_ground(a, sense):
		return
	if a.timer > 0:
		a.timer -= 1
		a.speed = 0.0
		return
	a.timer = 8
	_jump_angle(a, sense, a.angle_y)
	_set_avoid_jump_spd(a, sense)


## `aIBT_chk_avoid_jump_angle`: a front wall turns the hop ±90° off the current heading.
func _jump_angle(a: BugActor, sense: BugActor.Sense, ang: float) -> void:
	if BugProgram.wall_front(a, sense):
		ang = a.angle_y + (PI * 0.5 if a._rng.randi_range(0, 1) == 1 else -PI * 0.5)
	a.angle_y = wrapf(ang, -PI, PI)
	a.rot.y = a.angle_y


func _set_avoid_jump_spd(a: BugActor, sense: BugActor.Sense = null) -> void:
	if a.type == T_MIGRATORY_LOCUST:
		a.speed = 7.5
		a.pos_speed.y = 9.0
		a.gravity = 0.6
		return
	## Hopping north (`|rot.y| > 0x4000`) up a rising slope adds `3·sin(angle.x)` so the arc
	## clears the ground instead of diving into it.
	var lift: float = 3.0
	if absf(wrapf(a.rot.y, -PI, PI)) > PI * 0.5 and sense != null and sense.grid != null:
		var rise: float = BugBg.rise_ahead(sense.grid, sense.layout, a.pos, a.rot.y)
		if rise > 0.0:
			lift += 3.0 * rise
	a.speed = 5.0
	a.pos_speed.y = lift
	a.gravity = 0.3


# ---- helpers ---------------------------------------------------

## `aIBT_chk_active_range`: within 240 GX of the acre centre. Out of range the original
## leaves its `angle` out-parameter unwritten (stack garbage); the port heads back to
## the centre instead.
func _range_angle(a: BugActor) -> Array:
	var c: Vector2 = BugProgram.acre_center(a, _range_sense)
	var dx: float = c.x - a.pos.x
	var dz: float = c.y - a.pos.z
	if dx * dx + dz * dz >= ACTIVE_RANGE_SQ:
		return [false, BugProgram.atans(dz, dx)]
	return [true, 0.0]


func _in_active_range(a: BugActor) -> bool:
	return bool(_range_angle(a)[0])


func _ground_y(a: BugActor, sense: BugActor.Sense) -> float:
	if sense != null and sense.bg.is_valid():
		return float(sense.bg.call(a.pos).get("ground_y", a.home.y))
	return a.home.y


func _on_ground(a: BugActor, sense: BugActor.Sense) -> bool:
	## `bg_collision_check.result.on_ground` from this frame's `aINS_BGcheck`.
	if sense != null and sense.ground.is_valid():
		return a.bg_on_ground
	## No BG sampler (unit tests): clamp to the flat plane ourselves.
	var g: float = _ground_y(a, sense)
	if a.pos.y <= g + 0.001:
		a.pos.y = g
		if a.pos_speed.y < 0.0:
			a.pos_speed.y = 0.0
		return true
	return false


func _in_water(a: BugActor, sense: BugActor.Sense) -> bool:
	if sense != null and sense.ground.is_valid():
		return a.bg_in_water
	if sense != null and sense.bg.is_valid():
		return bool(sense.bg.call(a.pos).get("in_water", false))
	return false


## `aIBT_check_patience`: a stopped net (not the one holding it) or a dig within 70 GX.
func _check_patience(a: BugActor, sense: BugActor.Sense) -> bool:
	if not a.caught and BugProgram.near_xz(a, BugProgram.net_stop_pos(sense), 70.0):
		a.patience = 100.0
	elif BugProgram.near_xz(a, BugProgram.scoop_pos(sense), 70.0):
		a.patience = 100.0
	return a.patience >= 90.0
