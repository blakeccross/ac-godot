class_name NpcHeadLook
extends RefCounted

## Field head look-at (`ac_npc_head.c_inc`: `aNPC_look_target` → `aNPC_search_eye_target`,
## run from `aNPC_set_head_angl` as joint 21 is drawn). Head only — the body keeps walking.
##
## Each frame: pick a target (talk partner at priority 4, else the player when close and in
## front), then — unless the villager is sleepy — chase the head toward it, measured against
## the neck's *current world rotation* (`Matrix_to_rotate_new` of the parent joint's matrix,
## so the animation's own lean and sway are compensated), or back to the animation's own
## head angles when there is no target. The result replaces the head joint's rot.x / rot.y;
## rot.z stays the animation's.

## `player_distance_xz < 120` GX → 6 m (40 GX = 2 m).
const LOOK_DIST := 6.0
## ±67.5° forward cone vs body yaw (`aNPC_check_look_player`).
const LOOK_FOV := deg_to_rad(67.5)
## `aNPC_search_eye_target_sub` clamps: yaw ±67.5°, pitch only below −33.75° (looking down).
const YAW_LIMIT := deg_to_rad(67.5)
const PITCH_LIMIT := deg_to_rad(33.75)
## `head.angle_add_y = 0x400`, `angle_add_x = 0x200` through `chase_angle` (frame-scaled): × 30 per second.
const YAW_RATE := deg_to_rad(5.625) * DecompTime.FRAME_HZ
const PITCH_RATE := deg_to_rad(2.8125) * DecompTime.FRAME_HZ
## `aNPC_act_react_tool_init_proc`: 0xC00 / 0x600 while reacting to a tool hit.
const YAW_RATE_FAST := YAW_RATE * 3.0
const PITCH_RATE_FAST := PITCH_RATE * 3.0
const HEAD_BONE := "joint_21"
## `Actor_world_to_eye(player, 33.0f)`: the target is the player's eye, not their feet.
const PLAYER_EYE := 33.0 * FieldCatalog.GX_TO_METERS
## `aNPC_set_head_request` priorities: player in view 1, talk partner 4.
const PRIO_LOOK := 1
const PRIO_TALK := 4

var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _actor: Node3D
var _head_idx: int = -1
## `head.angle_y` / `head.angle_x` — written to joint rot.x / rot.y each draw.
var _yaw: float = 0.0
var _pitch: float = 0.0
## The animation's own head rotation (`joint_angle`, cKF ZYX Euler): what the head chases
## back to when nothing is targeted, and the rot.z the draw override leaves alone.
var _neutral: Vector3 = Vector3.ZERO
## The rotation last written to the bone — a pose that still equals it at mix time was
## not touched by the animation, so it says nothing about the animation's own head.
var _written: Quaternion = Quaternion.IDENTITY
## This frame's head request (`request.head_target`) and whether the feel is sleepy.
var _target: Node3D = null
var _sleepy: bool = false
## Time since the head was last updated (ticks and mixes need not line up one to one).
var _pending: float = 0.0
## `head.lock_flag` — skips `aNPC_look_target`, so the head falls back to neutral.
var locked: bool = false
## `head.angle_add_*` raised to 0x600 / 0xC00 (tool reaction).
var fast: bool = false


func bind(visual: Node3D, actor: Node3D = null) -> bool:
	_unbind_player()
	_actor = actor if actor != null else visual
	_skeleton = null
	_head_idx = -1
	_yaw = 0.0
	_pitch = 0.0
	_neutral = Vector3.ZERO
	_written = Quaternion.IDENTITY
	_target = null
	_pending = 0.0
	if visual == null:
		return false
	_skeleton = _find_skeleton(visual)
	if _skeleton == null:
		return false
	_head_idx = _skeleton.find_bone(HEAD_BONE)
	if _head_idx < 0 and _skeleton.get_bone_count() > 21:
		_head_idx = 21
	if _head_idx >= 0:
		_written = _skeleton.get_bone_pose_rotation(_head_idx)
		_neutral = _written.get_euler(EULER_ORDER_ZYX)
		_player = _find_player(visual)
		if _player != null:
			## The draw override lands after the animation, like `aNPC_set_head_angl`.
			_player.mixer_applied.connect(_apply)
	return _head_idx >= 0


## `aNPC_look_target` + `aNPC_check_condition_search_eye`.
## `forced`: the villager is talking to the player — a priority-4 request that skips the
## distance / cone gates and `skip_look`. `skip_look`: `aNPC_COND_DEMO_SKIP_HEAD_LOOKAT`
## (asleep in bed, walking in the door), which drops the priority-1 player request so the
## head eases back to the animation. `sleepy`: the sleepy feel freezes the head where it is.
func tick(
	delta: float,
	player: Node3D,
	body_yaw: float,
	sleepy: bool,
	forced: bool = false,
	skip_look: bool = false
) -> void:
	if _skeleton == null or _head_idx < 0 or _actor == null:
		return
	_sleepy = sleepy
	_target = null
	if not locked and player != null:
		if forced or (not skip_look and can_look(player, body_yaw)):
			_target = player
	_pending += delta
	_apply_now()


func can_look(player: Node3D, body_yaw: float) -> bool:
	## `aNPC_check_look_player` gates only — sleepy/lock applied by caller.
	if player == null or _actor == null:
		return false
	var delta: Vector3 = _node_pos(player) - _node_pos(_actor)
	delta.y = 0.0
	if delta.length() >= LOOK_DIST:
		return false
	if delta.length_squared() < 0.0001:
		return true
	var to_player: float = atan2(delta.x, delta.z)
	return absf(angle_difference(body_yaw, to_player)) < LOOK_FOV


func reset() -> void:
	_yaw = 0.0
	_pitch = 0.0
	if _skeleton != null and _head_idx >= 0:
		_skeleton.set_bone_pose_rotation(_head_idx, Quaternion.IDENTITY)


## `aNPC_search_eye_target_sub` for an actor target: the angles the head wants, relative to
## `world_rot` (the neck's world rotation). Pitch is from the villager's eye to the target's
## eye, positive looking up; yaw is from the villager's feet to the target's, both in the
## decomp's frame (Godot's world axes are the GX ones).
static func target_angles(
	eye: Vector3, root: Vector3, target_eye: Vector3, target_root: Vector3, world_rot: Vector3
) -> Vector2:
	var dxz: float = Vector2(target_eye.x - eye.x, target_eye.z - eye.z).length()
	## `-search_position_angleX(eye, target_eye)`: atan2(eye.y − target.y, dxz), negated.
	var angle_x: float = -atan2(eye.y - target_eye.y, dxz) + world_rot.x
	var angle_y: float = wrapf(atan2(target_root.x - root.x, target_root.z - root.z) - world_rot.y, -PI, PI)
	angle_x = maxf(angle_x, -PITCH_LIMIT)
	angle_y = clampf(angle_y, -YAW_LIMIT, YAW_LIMIT)
	return Vector2(angle_x, angle_y)


func _chase(current: float, want: float, max_step: float) -> float:
	var diff: float = angle_difference(current, want)
	return current + clampf(diff, -max_step, max_step)


func _apply_now() -> void:
	## Without an AnimationPlayer nothing else rewrites the pose, so write it directly.
	if _player == null:
		_apply()


## `aNPC_set_head_angl`: runs after the animation, so the neck's world rotation and the
## head's own animated angles are this frame's. `rot.x = head.angle_y`, `rot.y =
## head.angle_x`; rot.z stays the animation's. A head pose that differs from what was
## written last is the animation's own (`joint_angle`) — the neutral the head chases to.
func _apply() -> void:
	if _skeleton == null or _head_idx < 0:
		return
	var mixed: Quaternion = _skeleton.get_bone_pose_rotation(_head_idx)
	if not mixed.is_equal_approx(_written):
		_neutral = mixed.get_euler(EULER_ORDER_ZYX)
	var step: float = _pending
	_pending = 0.0
	if not _sleepy:
		var want_pitch: float = _neutral.y
		var want_yaw: float = _neutral.x
		if _target != null and is_instance_valid(_target):
			var want: Vector2 = target_angles(
				_eye_pos(),
				_node_pos(_actor),
				_node_pos(_target) + Vector3(0.0, PLAYER_EYE, 0.0),
				_node_pos(_target),
				_neck_world_rot()
			)
			want_pitch = want.x
			want_yaw = want.y
		_pitch = _chase(_pitch, want_pitch, (PITCH_RATE_FAST if fast else PITCH_RATE) * step)
		_yaw = _chase(_yaw, want_yaw, (YAW_RATE_FAST if fast else YAW_RATE) * step)
	_written = Basis.from_euler(Vector3(_yaw, _pitch, _neutral.z), EULER_ORDER_ZYX).get_rotation_quaternion()
	_skeleton.set_bone_pose_rotation(_head_idx, _written)


## `Matrix_to_rotate_new(get_Matrix_now())` at joint 21: the parent joint's world rotation
## as (x, y, z) of Ry·Rx·Rz.
func _neck_world_rot() -> Vector3:
	var parent: int = _skeleton.get_bone_parent(_head_idx)
	var basis: Basis = _skeleton.global_transform.basis
	if parent >= 0:
		basis = basis * _skeleton.get_bone_global_pose(parent).basis
	return basis.orthonormalized().get_euler(EULER_ORDER_YXZ)


func _unbind_player() -> void:
	if _player != null and is_instance_valid(_player) and _player.mixer_applied.is_connected(_apply):
		_player.mixer_applied.disconnect(_apply)
	_player = null


func _node_pos(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position


func _eye_pos() -> Vector3:
	if _skeleton != null and _head_idx >= 0:
		return (_skeleton.global_transform * _skeleton.get_bone_global_pose(_head_idx)).origin
	return _actor.global_position + Vector3(0.0, 1.2, 0.0)


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child: Node in root.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child: Node in root.get_children():
		var found: AnimationPlayer = _find_player(child)
		if found != null:
			return found
	return null
