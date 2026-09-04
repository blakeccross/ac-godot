class_name NpcHeadLook
extends RefCounted

## Field head look-at (`aNPC_check_look_player` / `aNPC_search_eye_target`).
## Head only — body keeps walking. Blocked when sleepy.

## `player_distance_xz < 120` GX → 6 m (40 GX = 2 m).
const LOOK_DIST := 6.0
## ±67.5° forward cone vs body yaw.
const LOOK_FOV := deg_to_rad(67.5)
## Neck clamps while tracking.
const YAW_LIMIT := deg_to_rad(67.5)
const PITCH_LIMIT := deg_to_rad(33.75)
## `head.angle_add_y = 0x400` → 5.625°/frame @ 30 Hz; `angle_add_x = 0x200`.
const YAW_RATE := deg_to_rad(5.625) * 30.0
const PITCH_RATE := deg_to_rad(2.8125) * 30.0
const HEAD_BONE := "joint_21"

var _skeleton: Skeleton3D
var _actor: Node3D
var _head_idx: int = -1
var _yaw: float = 0.0
var _pitch: float = 0.0
var locked: bool = false


func bind(visual: Node3D, actor: Node3D = null) -> bool:
	_actor = actor if actor != null else visual
	_skeleton = null
	_head_idx = -1
	_yaw = 0.0
	_pitch = 0.0
	if visual == null:
		return false
	_skeleton = _find_skeleton(visual)
	if _skeleton == null:
		return false
	_head_idx = _skeleton.find_bone(HEAD_BONE)
	if _head_idx < 0 and _skeleton.get_bone_count() > 21:
		_head_idx = 21
	return _head_idx >= 0


func tick(delta: float, player: Node3D, body_yaw: float, sleepy: bool) -> void:
	if _skeleton == null or _head_idx < 0 or _actor == null:
		return
	var want_yaw := 0.0
	var want_pitch := 0.0
	if not locked and not sleepy and player != null and can_look(player, body_yaw):
		var eye: Vector3 = _eye_pos()
		var to: Vector3 = player.global_position - eye
		var horiz: float = Vector2(to.x, to.z).length()
		want_pitch = -atan2(to.y, horiz) if horiz > 0.001 else 0.0
		want_yaw = atan2(to.x, to.z) - body_yaw
		want_pitch = clampf(want_pitch, -PITCH_LIMIT, PITCH_LIMIT)
		want_yaw = clampf(want_yaw, -YAW_LIMIT, YAW_LIMIT)
	_pitch = _chase(_pitch, want_pitch, PITCH_RATE * delta)
	_yaw = _chase(_yaw, want_yaw, YAW_RATE * delta)
	## Draw override: `rot.x = head.angle_y`, `rot.y = head.angle_x`.
	_skeleton.set_bone_pose_rotation(_head_idx, Quaternion.from_euler(Vector3(_yaw, _pitch, 0.0)))


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


func _chase(current: float, want: float, max_step: float) -> float:
	var diff: float = angle_difference(current, want)
	return current + clampf(diff, -max_step, max_step)


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
