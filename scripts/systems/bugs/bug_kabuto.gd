class_name BugKabuto
extends BugProgram

## `ac_ins_kabuto.c` — beetles (drone / dynastid / stag / jewel / longhorn / saw /
## mountain / giant). Clings to a tree trunk facing south, shuffles its legs
## (`aIKB_wait`), and on any scare flies straight up and away (`aIKB_avoid`, also
## the LET_ESCAPE proc).

enum { AVOID, LET_ESCAPE, WAIT }

## `angle_table` — ±175.78125° from north == ±4.21875° either side of due south.
const SWAY := deg_to_rad(4.21875)
## `init_posY` / `init_posZ` for [tree, cedar]: climb 35/30 GX, offset −2/+8 GX on Z.
const CLIMB_GX := [35.0, 30.0]
const OFFSET_Z_GX := [-2.0, 8.0]
const BALL_SCARE := 60.0
const NET_SCARE := 70.0
const SCOOP_SCARE := 30.0
const VIB_SCARE := 150.0
const MAX_PATIENCE := 90.0


func actor_init(a: BugActor, released: bool) -> void:
	match a.type:
		T_DRONE_BEETLE: a.item = 19
		T_DYNASTID_BEETLE: a.item = 20
		T_FLAT_STAG_BEETLE: a.item = 21
		T_JEWEL_BEETLE: a.item = 22
		T_LONGHORN_BEETLE: a.item = 23
		T_SAW_STAG_BEETLE: a.item = 29
		T_MOUNTAIN_BEETLE: a.item = 30
		T_GIANT_BEETLE: a.item = 31
	if not released:
		var cedar: bool = a.habitat == BugData.Habitat.TREE and _is_cedar(a)
		var it: int = 1 if cedar else 0
		## `GetBgY_OnlyCenter_FromWpos2(pos, -climb)` puts us `climb` GX up the trunk.
		a.pos.y = a.home.y + CLIMB_GX[it]
		a.pos.z += OFFSET_Z_GX[it]
		a.home = a.pos
		a.rot.x = PI * 0.5           ## `shape_info.rotation.x = 90°`
		a.rot.y = -BugActor.TREE_FACE_YAW
		a.angle_y = a.rot.y
		a.s32_work[3] = 0
		setup_action(a, WAIT)
	else:
		setup_action(a, LET_ESCAPE)


func _is_cedar(_a: BugActor) -> bool:
	## Cedar vs broadleaf changes the climb/offset only; without an FG probe assume
	## broadleaf (the common case). Wired in Phase 3.
	return false


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


# ---- setupAction ---------------------------------------------------

func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID, LET_ESCAPE:
			a.action_proc = _avoid
			_avoid_init(a)
		WAIT:
			a.action_proc = _wait
			_wait_init(a)


func _avoid_init(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 80
	a.gravity = 0.06
	a.max_velocity_y = 12.0
	a.speed = 4.0
	a.rot.x = 0.0
	if a._last_player_gx != Vector3.INF:
		var pyaw: float = a.f32_work[3]  ## stored player yaw (see _wait)
		a.rot.y = pyaw + a._rng.randf_range(-1.0, 1.0) * deg_to_rad(60.0)
	else:
		a.rot.y += PI
	a.angle_y = a.rot.y
	a.f_no_catch = true
	a.f_bit2 = true


func _wait_init(a: BugActor) -> void:
	a.rot.y = -BugActor.TREE_FACE_YAW
	a.angle_y = a.rot.y


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
	## Remember player yaw for the escape heading.
	if sense.has_player():
		a.f32_work[3] = BugProgram.angle_to(a.pos, sense.player_position / BugActor.GX_M)
	if _check_patience(a, sense):
		setup_action(a, AVOID)
		return
	## `aIKB_wait` leg-shuffle: chase ±4.2° a few times, hold 30f, pause 20-40f.
	if a.s32_work[0] == 0:
		var target: float = -BugActor.TREE_FACE_YAW + (SWAY if (a.s32_work[1] & 1) == 0 else -SWAY)
		a.rot.y = BugProgram.chase_angle(a.rot.y, target, 128 * S16)
		a.angle_y = a.rot.y
		if a.s32_work[2] == 0:
			if a.s32_work[1] == 0:
				a.s32_work[0] = int((10.0 + a._rng.randf() * 10.0) * 2.0)
				a.s32_work[1] = 3 + a._rng.randi_range(0, 1)
			else:
				a.s32_work[1] -= 1
			a.s32_work[2] = 30
		else:
			a.s32_work[2] -= 1
	else:
		a.s32_work[0] -= 1


func _avoid(a: BugActor, _sense: BugActor.Sense) -> void:
	a.anime0 += 0.5
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0
	a.gravity = minf(a.gravity * 1.1, 12.0)


func _check_patience(a: BugActor, sense: BugActor.Sense) -> bool:
	## tree shake / dig vibration / thrown ball / stopped net / dig scoop.
	if sense.player_action == BugActor.PlAct.SHAKE_TREE and sense.has_player():
		if BugProgram.dist_xz(a.pos, sense.player_position / BugActor.GX_M) < 200.0:
			a.patience = 100.0
	if sense.player_swung_tool and sense.has_player():
		var d: float = BugProgram.dist_xz(a.pos, sense.player_position / BugActor.GX_M)
		if d < VIB_SCARE:
			a.patience = 100.0
	if sense.net_swing_active and sense.net_swing_origin != Vector3.INF:
		if BugProgram.dist_xz(a.pos, sense.net_swing_origin / BugActor.GX_M) < NET_SCARE:
			a.patience = 100.0
	return a.patience > MAX_PATIENCE
