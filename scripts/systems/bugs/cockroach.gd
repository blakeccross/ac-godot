class_name Cockroach
extends BugBehavior

## `ac_ins_goki.c` — cockroach. Scurries a 30 GX box 25 GX up a flower (0.4 GX/frame,
## 90–300-frame runs, 90–180-frame rests), sways on a tree trunk (35 GX up, 30 on a
## cedar) like a beetle, or sits on a spoiled turnip. A shaken tree / axe hit in the acre
## within 150 GX (trunk only), a stopped net within 70 GX or a dig within 30 GX sends it
## flying off within ±67.5° of south; released ones leave off the player's facing ±60°.
## On a tree the net catch range is angular (`flag == 4`).

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
const NET_SCARE := 70.0
const SCOOP_SCARE := 30.0
const VIB_SCARE := 150.0

var _placed: bool = false
## Ticks left of a run on the flower (`s32_work2`) and of a sway on the trunk.
var _run_left: float = 0.0
var _sway_left: float = 0.0
## Where it is turning to (`s32_work0`, radians) and the trunk sways left (`s32_work1`).
var _target_yaw: float = 0.0
var _sways_left: int = 0


func actor_init(a: BugActor, released: bool) -> void:
	a.item = 28
	a.bg_range = 6.0
	if released:
		_placed = true
		setup_action(a, LET_ESCAPE)
		return
	match a.habitat:
		BugData.Habitat.TREE:
			BugBehavior.cling_to_trunk(a)
			a.rot.y = -BugActor.TREE_FACE_YAW
			a.rot.x = PI * 0.5
			a.flag = PLACE_TREE
			setup_action(a, WAIT_ON_TREE)
		BugData.Habitat.GROUND, BugData.Habitat.UNDERGROUND:
			## `5 + GetBgY_OnlyCenter_FromWpos2(pos, −2)`.
			_placed = true
			a.pos.y = a.home.y + 7.0
			a.home = a.pos
			a.rot.y = -BugActor.TREE_FACE_YAW
			a.rot.x = deg_to_rad(45.0)
			a.flag = PLACE_ITEM
			setup_action(a, WAIT_ON_ITEM)
		_:
			## `6 + GetBgY_OnlyCenter_FromWpos(pos, −19)`: on the flower head.
			_placed = true
			a.terrain_mode = BugActor.TerrainMode.GROUND
			a.pos.y = a.home.y + 25.0
			a.home = a.pos
			a.flag = PLACE_FLOWER
			setup_action(a, WAIT_ON_FLOWER)


func pose_index(a: BugActor) -> int:
	return int(a.anim_frame) & 1


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
			a.catchable = false
		LET_ESCAPE:
			a.action_proc = _avoid
			a.life_time = 0
			a.alpha_time = 80
			a.speed = 4.0
			a.max_velocity_y = 12.0
			a.gravity = 0.06
			a.rot.x = 0.0
			a.pos_speed.y = 0.0
			if BugBehavior.heading_from_player_facing(a, deg_to_rad(120.0)):
				a.rot.y = a.angle_y
			a.catchable = false
			a.escaping = true
		WAIT_ON_FLOWER:
			a.action_proc = _wait_on_flower
			a.speed = 0.0
			a.speed_step = 0.0
			a.target_speed = 0.0
		MOVE_ON_FLOWER:
			a.action_proc = _move_on_flower
			if _run_left <= 0.0:
				_run_left = 2.0 * (90.0 + a._rng.randf() * 210.0)
			a.target_speed = 0.4
			a.speed_step = 0.1
		WAIT_ON_TREE, WAIT_ON_ITEM:
			a.action_proc = _wait_on_tree
			a.timer = int(2.0 * (10.0 + a._rng.randf() * 10.0))
		MOVE_ON_TREE, MOVE_ON_ITEM:
			a.action_proc = _move_on_tree
			_target_yaw = deg_to_rad(175.78125)
			_sways_left = 3 + a._rng.randi_range(0, 1)
			_sway_left = 30.0


func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if not _placed:
		_placed = true
		BugBehavior.settle_on_cedar(a, sense)
	if a.caught:
		setup_action(a, LET_ESCAPE)
		return
	if a.f_scared and not a.escaping:
		setup_action(a, LET_ESCAPE)
		return
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


func _wait_on_flower(a: BugActor, sense: BugActor.Sense) -> void:
	if _check_patience(a, sense):
		setup_action(a, AVOID)
		return
	a.timer -= a.n
	if a.timer <= 0.0:
		setup_action(a, MOVE_ON_FLOWER)
	else:
		a.angle_y = BugBehavior.chase_angle(a.angle_y, _target_yaw, deg_to_rad(8.4375), a.n)
		a.rot.y = a.angle_y


func _move_on_flower(a: BugActor, sense: BugActor.Sense) -> void:
	if _check_patience(a, sense):
		setup_action(a, AVOID)
		return
	_run_left -= a.n
	if _run_left <= 0.0:
		_run_left = 0.0
		a.loop_sound = 0xA8  ## `NA_SE_GOKI_MOVE`
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
		_target_yaw = REF_ANGL[flag]
		a.timer = 10
		setup_action(a, WAIT_ON_FLOWER)
	else:
		a.angle_y = BugBehavior.chase_angle(a.angle_y, _target_yaw, deg_to_rad(8.4375), a.n)
		if BugBehavior.angle_reached(a.angle_y, _target_yaw):
			_target_yaw = a.angle_y + a._rng.randf_range(-1.0, 1.0) * deg_to_rad(90.0)
		a.rot.y = a.angle_y


func _wait_on_tree(a: BugActor, sense: BugActor.Sense) -> void:
	if _check_patience(a, sense):
		setup_action(a, AVOID)
		return
	a.timer -= a.n
	if a.timer <= 0.0:
		setup_action(a, a.action + 1)


func _move_on_tree(a: BugActor, sense: BugActor.Sense) -> void:
	if _check_patience(a, sense):
		setup_action(a, AVOID)
		return
	a.rot.y = BugBehavior.chase_angle(a.rot.y, _target_yaw, 128 * MathUtil.S16, a.n)
	_sway_left -= a.n
	if _sway_left <= 0.0:
		_sways_left -= 1
		if _sways_left <= 0:
			setup_action(a, a.action - 1)
		else:
			_target_yaw = -_target_yaw
			_sway_left += 30.0


func _avoid(a: BugActor, sense: BugActor.Sense) -> void:
	a.anim_frame = fmod(a.anim_frame + 0.5 * a.n, 2.0)
	a.gravity = minf(a.gravity * pow(1.1, a.n), 12.0)
	a.loop_sound = 0x26
	## `aIGK_avoid`: ground / wall collision switches on once it has flown off its home unit.
	if a.terrain_mode == BugActor.TerrainMode.NONE and BugBehavior.unit_of(sense, a.home) != BugBehavior.unit_of(sense, a.pos):
		a.terrain_mode = BugActor.TerrainMode.GROUND_WITH_ATTRIBUTES


## `aIGK_check_patience`: (on a trunk) shaken tree / axe hit in the acre within 150 GX
## → stopped net within 70 GX → dig within 30 GX; scared at 90.
func _check_patience(a: BugActor, sense: BugActor.Sense) -> bool:
	if a.flag == PLACE_TREE and (
		sense.tree_shaken_at(a.position)
		or (BugBehavior.vib_unit(a, sense) and a.player_distance_xz < VIB_SCARE)
	):
		a.patience = 100.0
	elif not a.caught and BugBehavior.near_xz(a, BugBehavior.net_stop_pos(sense), NET_SCARE):
		a.patience = 100.0
	elif BugBehavior.near_xz(a, BugBehavior.scoop_pos(sense), SCOOP_SCARE):
		a.patience = 100.0
	return a.patience >= 90.0
