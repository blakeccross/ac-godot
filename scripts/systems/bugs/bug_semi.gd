class_name BugSemi
extends BugProgram

## `ac_ins_semi.c` — cicadas (robust / walker / evening / brown) and the bee.
## Sits on a tree trunk facing south; cicadas cry on a timer with a tiny X jiggle;
## any scare → fly straight up and away (`aISM_avoid`, also LET_ESCAPE).

enum { AVOID, LET_ESCAPE, WAIT }

const CLIMB_GX := [35.0, 30.0]
const OFFSET_Z_GX := [-2.0, 8.0]
const NET_SCARE := 70.0
const SCOOP_SCARE := 30.0
const AXE_SCARE := 150.0
const CRY_TIMER := 60


func actor_init(a: BugActor, released: bool) -> void:
	match a.type:
		T_ROBUST_CICADA: a.item = 4
		T_WALKER_CICADA: a.item = 5
		T_EVENING_CICADA: a.item = 6
		T_BROWN_CICADA: a.item = 7
		T_BEE: a.item = 8
	if not released:
		var it: int = 1 if (a.habitat == BugData.Habitat.TREE and _is_cedar(a)) else 0
		a.pos.y = a.home.y + CLIMB_GX[it]
		a.pos.z += OFFSET_Z_GX[it]
		a.home = a.pos
		a.rot.x = PI * 0.5
		setup_action(a, WAIT)
	else:
		setup_action(a, LET_ESCAPE)


func _is_cedar(_a: BugActor) -> bool:
	return false


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


# ---- setupAction ---------------------------------------------------

func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID:
			a.action_proc = _avoid
			_avoid_init(a)
		LET_ESCAPE:
			a.action_proc = _avoid
			_avoid_init(a)
			a.f_bit2 = true
		WAIT:
			a.action_proc = _wait
			a.rot.y = BugActor.TREE_FACE_YAW
			a.angle_y = a.rot.y


func _avoid_init(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 80
	a.speed = 4.0
	a.max_velocity_y = 12.0
	a.gravity = 0.06
	a.rot.x = 0.0
	if a.action == AVOID:
		## Random forward spread ±(0..67.5°) off south.
		var r: float = a._rng.randf()
		var base: float = deg_to_rad(22.5) * (1.0 if r >= 0.5 else -1.0)
		a.rot.y = (r * deg_to_rad(90.0) - deg_to_rad(45.0)) + base
	elif a.f32_work[3] != 0.0 or a._last_player_gx != Vector3.INF:
		a.rot.y = a.f32_work[3] + a._rng.randf_range(-1.0, 1.0) * deg_to_rad(120.0)
	a.angle_y = a.rot.y
	a.f_no_catch = true


# ---- actions -----------------------------------------------------

func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if a.caught:
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2:
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _wait(a: BugActor, sense: BugActor.Sense) -> void:
	if sense.has_player():
		a.f32_work[3] = sense.player_position.y  ## dummy to mark "seen player"
		a.f32_work[3] = BugProgram.angle_to(a.pos, sense.player_position / BugActor.GX_M)
	if _check_patience(a, sense):
		setup_action(a, AVOID)
		return
	if a.type == T_BEE or a.s32_work[0] != 0:
		return
	## Cicada cry cadence + a sub-GX X twitch.
	if a.patience < 50.0:
		a.timer -= 1
		if a.timer < 0:
			a.timer = 0
			a.pos.x = a.home.x + a._rng.randf() * 0.4
	else:
		a.timer = CRY_TIMER


func _avoid(a: BugActor, _sense: BugActor.Sense) -> void:
	a.anime0 += 0.5
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0
	a.gravity = minf(a.gravity * 1.1, 12.0)


func _check_patience(a: BugActor, sense: BugActor.Sense) -> bool:
	if sense.player_action == BugActor.PlAct.SHAKE_TREE and sense.has_player():
		if BugProgram.dist_xz(a.pos, sense.player_position / BugActor.GX_M) < 200.0:
			a.patience = 100.0
	if sense.player_swung_tool and sense.has_player():
		if BugProgram.dist_xz(a.pos, sense.player_position / BugActor.GX_M) < AXE_SCARE:
			a.patience = 100.0
	if sense.net_swing_active and sense.net_swing_origin != Vector3.INF:
		if BugProgram.dist_xz(a.pos, sense.net_swing_origin / BugActor.GX_M) < NET_SCARE:
			a.patience = 100.0
	return a.patience > 90.0
