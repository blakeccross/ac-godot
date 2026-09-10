class_name BugBatta
extends BugProgram

## `ac_ins_batta.c` — locusts (long / migratory) and crickets (field / grasshopper /
## bell / pine). Ground hoppers: wait on the ground turning to face the player, hop
## to reposition, and on a scare hop away in a burst. Locusts hop far and often;
## crickets mostly sit and chirp.
##
## Ground height / water / wall come from `sense.bg`; with none, flat ground at the
## spawn plane and no water.

enum { AVOID, LET_ESCAPE, CHANGE_DIRECTION, WAIT, JUMP, DROWN }

## `range[]` (`aIBT_chg_direction`) — turn spread per attempt, s16.
const TURN_RANGE := [
	4096.0, 4096.0, 8192.0, 8192.0, 8192.0, 12288.0, 12288.0, 12288.0,
	12288.0, 12288.0, 16384.0, 16384.0, 16384.0, 16384.0, 16384.0, 16384.0,
]
## `aIBT_chk_active_range`: 240 GX from acre centre (57600 = 240²).
const ACTIVE_RANGE_SQ := 57600.0


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
		## Acre centre in world GX (`BkNum2WposXZ + 320`).
		a.f32_work[2] = a.home.x
		a.f32_work[3] = a.home.z
		setup_action(a, CHANGE_DIRECTION)
	else:
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
	if a._last_player_gx != Vector3.INF:
		var to: float = BugProgram.atans(
			a._last_player_gx.z - a.pos.z, a._last_player_gx.x - a.pos.x
		)
		a.angle_y = to + PI + a._rng.randf_range(-1.0, 1.0) * (8192.0 * S16)
		a.rot.y = a.angle_y


func _let_escape_init(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 80
	a.gravity = 0.2
	a.timer = 0
	a.speed = 5.0
	a.pos_speed.y = 3.0
	if a.f32_work[1] != 0.0 or a._last_player_gx != Vector3.INF:
		a.angle_y = a.f32_work[1] + a._rng.randf_range(-1.0, 1.0) * (21845.0 * 0.5 * S16)
		a.rot.y = a.angle_y
	a.f_no_catch = true
	a.f_bit2 = true


func _wait_init(a: BugActor) -> void:
	if not _in_active_range(a):
		a.timer = 60
	else:
		a.timer = int(2.0 * (120.0 + a._rng.randi_range(0, 239)))


# ---- actions ----------------------------------------------------

func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if a.caught:
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2:
		setup_action(a, LET_ESCAPE)
		return
	if sense.has_player():
		a.f32_work[1] = BugProgram.angle_to(a.pos, sense.player_position / BugActor.GX_M)
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _chg_direction(a: BugActor, sense: BugActor.Sense) -> void:
	var back: Array = _range_angle(a)
	if not bool(back[0]):
		a.angle_y = float(back[1])
		setup_action(a, WAIT)
		return
	var idx: int = clampi(a.s32_work[0], 0, TURN_RANGE.size() - 1)
	var ang: float = a.rot.y + PI + TURN_RANGE[idx] * S16 * a._rng.randf_range(-1.0, 1.0)
	var mod: float = 218.0 if a.type == T_MIGRATORY_LOCUST else 53.0
	var probe: Vector3 = a.pos + Vector3(sin(ang) * mod, 0.0, cos(ang) * mod)
	var ok: bool = true
	var water: bool = false
	if sense != null and sense.bg.is_valid():
		var r: Dictionary = sense.bg.call(probe)
		var bg_y: float = float(r.get("ground_y", a.home.y))
		water = bool(r.get("water", false))
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
	## Ease shape yaw toward the target heading.
	a.rot.y = BugProgram.chase_angle(a.rot.y, a.angle_y, 0x1000 * S16)
	if a.type == T_BELL_CRICKET and _on_ground(a, sense) and a.patience < 20.0:
		a.anime0 += 1.0
		if a.anime0 >= 2.0:
			a.anime0 -= 2.0
	a.timer -= 1
	if a.timer > 0:
		return
	var action: int = CHANGE_DIRECTION
	if not _in_active_range(a):
		action = JUMP
	elif a.type == T_LONG_LOCUST or a.type == T_MIGRATORY_LOCUST:
		if a._rng.randi_range(0, 199) > 20:
			action = JUMP
	elif a._rng.randi_range(0, 199) < 20:
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
	var ang: float = a.rot.y
	if _in_active_range(a) and sense.has_player():
		ang = BugProgram.angle_to(a.pos, sense.player_position / BugActor.GX_M) + PI
	## `chk_avoid_jump_angle`: wall hit → flip ±90°.
	if sense != null and sense.bg.is_valid() and bool(sense.bg.call(a.pos).get("hit_wall_front", false)):
		ang = a.angle_y + (PI * 0.5 if a._rng.randi_range(0, 1) == 1 else -PI * 0.5)
	a.angle_y = ang
	a.rot.y = ang
	_set_avoid_jump_spd(a)


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
	a.rot.y = a.angle_y
	_set_avoid_jump_spd(a)


func _set_avoid_jump_spd(a: BugActor) -> void:
	if a.type == T_MIGRATORY_LOCUST:
		a.speed = 7.5
		a.pos_speed.y = 9.0
		a.gravity = 0.6
	else:
		a.speed = 5.0
		a.pos_speed.y = 3.0
		a.gravity = 0.3


# ---- helpers ---------------------------------------------------

func _range_angle(a: BugActor) -> Array:
	var dx: float = a.f32_work[2] - a.pos.x
	var dz: float = a.f32_work[3] - a.pos.z
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
	## Also clamps — without `bg_collision_check` nothing else stops the arc.
	var g: float = _ground_y(a, sense)
	if a.pos.y <= g + 0.001:
		a.pos.y = g
		if a.pos_speed.y < 0.0:
			a.pos_speed.y = 0.0
		return true
	return false


func _in_water(a: BugActor, sense: BugActor.Sense) -> bool:
	if sense != null and sense.bg.is_valid():
		return bool(sense.bg.call(a.pos).get("in_water", false))
	return false


func _check_patience(a: BugActor, sense: BugActor.Sense) -> bool:
	if sense.net_swing_active and sense.net_swing_origin != Vector3.INF:
		if BugProgram.dist_xz(a.pos, sense.net_swing_origin / BugActor.GX_M) < 70.0:
			a.patience = 100.0
	if sense.player_swung_tool and sense.has_player():
		if BugProgram.dist_xz(a.pos, sense.player_position / BugActor.GX_M) < 70.0:
			a.patience = 100.0
	return a.patience >= 90.0
