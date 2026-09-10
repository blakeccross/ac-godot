class_name BugGoki
extends BugProgram

## `ac_ins_goki.c` — cockroach. Scurries on a flower (box wander, like the ladybug),
## on a tree trunk (leg-shuffle sway, like the beetle), or on a dropped spoiled
## turnip. Any scare → flies straight up and away. On a tree the net catch range is
## angular (`flag == 4`).

enum {
	AVOID, LET_ESCAPE, WAIT_ON_FLOWER, MOVE_ON_FLOWER,
	WAIT_ON_TREE, MOVE_ON_TREE, WAIT_ON_ITEM, MOVE_ON_ITEM,
}

const PLACE_TREE := 4
const PLACE_FLOWER := 5
const PLACE_ITEM := 6

const REF_ANGL := [
	0.0, deg_to_rad(90.0), deg_to_rad(-90.0), 0.0,
	0.0, deg_to_rad(45.0), deg_to_rad(-45.0), 0.0,
	deg_to_rad(180.0), deg_to_rad(135.0), deg_to_rad(-135.0), deg_to_rad(180.0),
	deg_to_rad(90.0), deg_to_rad(90.0), deg_to_rad(-90.0), 0.0,
]
const SWAY := deg_to_rad(4.21875)


func actor_init(a: BugActor, released: bool) -> void:
	a.item = 28
	a.bg_range = 6.0
	if released:
		setup_action(a, LET_ESCAPE)
		return
	match a.habitat:
		BugData.Habitat.TREE:
			a.pos.y = a.home.y + 35.0
			a.pos.z += -2.0
			a.home = a.pos
			a.rot.y = -BugActor.TREE_FACE_YAW
			a.rot.x = PI * 0.5
			a.flag = PLACE_TREE
			setup_action(a, WAIT_ON_TREE)
		BugData.Habitat.GROUND, BugData.Habitat.UNDERGROUND:
			a.pos.y = a.home.y + 5.0
			a.home = a.pos
			a.rot.y = -BugActor.TREE_FACE_YAW
			a.rot.x = deg_to_rad(45.0)
			a.flag = PLACE_ITEM
			setup_action(a, WAIT_ON_ITEM)
		_:
			a.pos.y = a.home.y + 6.0
			a.home = a.pos
			a.flag = PLACE_FLOWER
			setup_action(a, WAIT_ON_FLOWER)


func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


func on_release(a: BugActor) -> void:
	setup_action(a, LET_ESCAPE)


func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	match action:
		AVOID:
			a.action_proc = _avoid
			a.life_time = 0
			a.alpha_time = 80
			a.speed = 4.0
			a.max_velocity_y = 12.0
			a.gravity = 0.06
			a.rot.x = 0.0
			a.pos_speed.y = 0.0
			var r: float = a._rng.randf()
			a.rot.y = r * deg_to_rad(90.0) - deg_to_rad(45.0) + deg_to_rad(22.5) * (1.0 if r >= 0.5 else -1.0)
			a.angle_y = a.rot.y
			a.f_no_catch = true
		LET_ESCAPE:
			a.action_proc = _avoid
			a.life_time = 0
			a.alpha_time = 80
			a.speed = 4.0
			a.max_velocity_y = 12.0
			a.gravity = 0.06
			a.rot.x = 0.0
			a.pos_speed.y = 0.0
			if a._last_player_gx != Vector3.INF:
				a.rot.y = BugProgram.angle_to(a._last_player_gx, a.pos) + a._rng.randf_range(-1.0, 1.0) * deg_to_rad(90.0)
				a.angle_y = a.rot.y
			a.f_no_catch = true
			a.f_bit2 = true
		WAIT_ON_FLOWER:
			a.action_proc = _wait_on_flower
			a.speed = 0.0
			a.speed_step = 0.0
			a.target_speed = 0.0
		MOVE_ON_FLOWER:
			a.action_proc = _move_on_flower
			if a.s32_work[2] == 0:
				a.s32_work[2] = int(2.0 * (90.0 + a._rng.randf() * 210.0))
			a.target_speed = 0.4
			a.speed_step = 0.1
		WAIT_ON_TREE, WAIT_ON_ITEM:
			a.action_proc = _wait_on_tree
			a.timer = int(2.0 * (10.0 + a._rng.randf() * 10.0))
		MOVE_ON_TREE, MOVE_ON_ITEM:
			a.action_proc = _move_on_tree
			a.s32_work[0] = int(deg_to_rad(175.78125) / S16)
			a.s32_work[1] = 3 + a._rng.randi_range(0, 1)
			a.s32_work[2] = 30


func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if a.caught:
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.f_bit2:
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _wait_on_flower(a: BugActor, sense: BugActor.Sense) -> void:
	if _check_patience(a, sense):
		setup_action(a, AVOID)
		return
	a.timer -= 1
	if a.timer <= 0:
		setup_action(a, MOVE_ON_FLOWER)
	else:
		a.angle_y = BugProgram.chase_angle(a.angle_y, a.s32_work[0] * S16, deg_to_rad(8.4375))
		a.rot.y = a.angle_y


func _move_on_flower(a: BugActor, sense: BugActor.Sense) -> void:
	if _check_patience(a, sense):
		setup_action(a, AVOID)
		return
	a.s32_work[2] -= 1
	if a.s32_work[2] <= 0:
		a.timer = int(2.0 * (90.0 + a._rng.randf() * 90.0))
		setup_action(a, WAIT_ON_FLOWER)
		return
	var dx: float = a.pos.x - a.home.x
	var dz: float = a.pos.z - a.home.z
	var flag: int = 0
	if absf(dx) >= 15.0:
		a.pos.x = a.home.x + (-14.0 if dx < 0.0 else 14.0)
		flag = 1 if dx < 0.0 else 2
	if absf(dz) >= 15.0:
		a.pos.z = a.home.z + (-14.0 if dz < 0.0 else 14.0)
		flag |= 4 if dz < 0.0 else 8
	if flag != 0:
		a.s32_work[0] = int(REF_ANGL[flag] / S16)
		a.timer = 10
		setup_action(a, WAIT_ON_FLOWER)
	else:
		var done: bool = is_equal_approx(a.angle_y, a.s32_work[0] * S16)
		a.angle_y = BugProgram.chase_angle(a.angle_y, a.s32_work[0] * S16, deg_to_rad(8.4375))
		if done:
			a.s32_work[0] = int((a.angle_y + a._rng.randf_range(-1.0, 1.0) * deg_to_rad(90.0)) / S16)
		a.rot.y = a.angle_y


func _wait_on_tree(a: BugActor, sense: BugActor.Sense) -> void:
	if _check_patience(a, sense):
		setup_action(a, AVOID)
		return
	a.timer -= 1
	if a.timer <= 0:
		setup_action(a, a.action + 1)


func _move_on_tree(a: BugActor, sense: BugActor.Sense) -> void:
	if _check_patience(a, sense):
		setup_action(a, AVOID)
		return
	a.rot.y = BugProgram.chase_angle(a.rot.y, a.s32_work[0] * S16, 128 * S16)
	a.s32_work[2] -= 1
	if a.s32_work[2] <= 0:
		a.s32_work[1] -= 1
		if a.s32_work[1] <= 0:
			setup_action(a, a.action - 1)
		else:
			a.s32_work[0] = -a.s32_work[0]
			a.s32_work[2] = 30


func _avoid(a: BugActor, _sense: BugActor.Sense) -> void:
	a.anime0 += 0.5
	if a.anime0 >= 2.0:
		a.anime0 -= 2.0
	a.gravity = minf(a.gravity * 1.1, 12.0)


func _check_patience(a: BugActor, sense: BugActor.Sense) -> bool:
	if a.flag == PLACE_TREE and sense.player_action == BugActor.PlAct.SHAKE_TREE and sense.has_player():
		if BugProgram.dist_xz(a.pos, sense.player_position / BugActor.GX_M) < 150.0:
			a.patience = 100.0
	if sense.net_swing_active and sense.net_swing_origin != Vector3.INF:
		if BugProgram.dist_xz(a.pos, sense.net_swing_origin / BugActor.GX_M) < 70.0:
			a.patience = 100.0
	if sense.player_swung_tool and sense.has_player():
		if BugProgram.dist_xz(a.pos, sense.player_position / BugActor.GX_M) < 60.0:
			a.patience = 100.0
	return a.patience >= 90.0
