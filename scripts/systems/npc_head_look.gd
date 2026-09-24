class_name NpcHeadLook
extends RefCounted

## Field head look-at (`aNPC_check_look_player` / `aNPC_search_eye_target`).
## Head only — body keeps walking. A sleepy villager's head is not updated at all.

## `player_distance_xz < 120` GX → 6 m (40 GX = 2 m).
const LOOK_DIST := 6.0
## ±67.5° forward cone vs body yaw.
const LOOK_FOV := deg_to_rad(67.5)
## Neck clamps while tracking. Pitch only clamps looking up (`angleX < -33.75°`).
const YAW_LIMIT := deg_to_rad(67.5)
const PITCH_LIMIT := deg_to_rad(33.75)
## `head.angle_add_y = 0x400`, `angle_add_x = 0x200` through `chase_angle` (frame-scaled): × 30 per second.
const YAW_RATE := deg_to_rad(5.625) * 30.0
const PITCH_RATE := deg_to_rad(2.8125) * 30.0
const HEAD_BONE := "joint_21"
## `Actor_world_to_eye(player, 33.0f)`: the target is the player's eye, not their feet.
const PLAYER_EYE := 33.0 * FieldCatalog.GX_TO_METERS

var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _actor: Node3D
var _head_idx: int = -1
## `head.angle_y` / `head.angle_x` — written to joint rot.x / rot.y each draw.
var _yaw: float = 0.0
var _pitch: float = 0.0
## The animation's own head rotation (`joint_angle`): what the head chases back to
## when nothing is targeted, and the rot.z the draw override leaves alone.
var _neutral: Vector3 = Vector3.ZERO
## The rotation last written to the bone — a pose that still equals it at mix time was
## not touched by the animation, so it says nothing about the animation's own head.
var _written: Quaternion = Quaternion.IDENTITY
## `head.lock_flag` — skips `aNPC_look_target`, so the head falls back to neutral.
var locked: bool = false


func bind(visual: Node3D, actor: Node3D = null) -> bool:
	_unbind_player()
	_actor = actor if actor != null else visual
	_skeleton = null
	_head_idx = -1
	_yaw = 0.0
	_pitch = 0.0
	_neutral = Vector3.ZERO
	_written = Quaternion.IDENTITY
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
		_neutral = _written.get_euler()
		_player = _find_player(visual)
		if _player != null:
			## The draw override lands after the animation, like `aNPC_set_head_angl`.
			_player.mixer_applied.connect(_apply)
	return _head_idx >= 0


## `forced`: talk asks for the head at priority 4 (`aNPC_look_target`), which skips
## both the distance and the cone gate.
func tick(
	delta: float, player: Node3D, body_yaw: float, sleepy: bool, forced: bool = false
) -> void:
	if _skeleton == null or _head_idx < 0 or _actor == null:
		return
	## `aNPC_check_condition_search_eye`: sleepy → head angles are left where they are.
	if sleepy:
		_apply_now()
		return
	var want_yaw: float = _neutral.x
	var want_pitch: float = _neutral.y
	if not locked and player != null and (forced or can_look(player, body_yaw)):
		var eye: Vector3 = _eye_pos()
		var to: Vector3 = _node_pos(player) + Vector3(0.0, PLAYER_EYE, 0.0) - eye
		var horiz: float = Vector2(to.x, to.z).length()
		want_pitch = -atan2(to.y, horiz) if horiz > 0.001 else 0.0
		want_pitch = maxf(want_pitch, -PITCH_LIMIT)
		var flat: Vector3 = _node_pos(player) - _node_pos(_actor)
		want_yaw = angle_difference(body_yaw, atan2(flat.x, flat.z))
		want_yaw = clampf(want_yaw, -YAW_LIMIT, YAW_LIMIT)
	_pitch = _chase(_pitch, want_pitch, PITCH_RATE * delta)
	_yaw = _chase(_yaw, want_yaw, YAW_RATE * delta)
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


func _chase(current: float, want: float, max_step: float) -> float:
	var diff: float = angle_difference(current, want)
	return current + clampf(diff, -max_step, max_step)


func _apply_now() -> void:
	## Without an AnimationPlayer nothing else rewrites the pose, so write it directly.
	if _player == null:
		_apply()


## `aNPC_set_head_angl`: `rot.x = head.angle_y`, `rot.y = head.angle_x`; rot.z stays the
## animation's. Right after the mix, a head pose that differs from what was written last
## is the animation's own (`joint_angle`) — the neutral the head chases back to.
func _apply() -> void:
	if _skeleton == null or _head_idx < 0:
		return
	var mixed: Quaternion = _skeleton.get_bone_pose_rotation(_head_idx)
	if not mixed.is_equal_approx(_written):
		_neutral = mixed.get_euler()
	_written = Quaternion.from_euler(Vector3(_yaw, _pitch, _neutral.z))
	_skeleton.set_bone_pose_rotation(_head_idx, _written)


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
