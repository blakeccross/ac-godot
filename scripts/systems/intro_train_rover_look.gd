class_name IntroTrainRoverLook
extends RefCounted

## Rover head look-at during train intro (`aNGD_set_camera_eyes`).

const HEAD_BONE := "joint_24"
const CAM_EYES_GX := Vector3(100.0, 52.0, 400.0)
const PLAYER_GX := Vector3(120.0, 0.0, 340.0)
const HEAD_YAW_CHASE := deg_to_rad(11.25)
const HEAD_YAW_LIMIT := deg_to_rad(67.5)

var _skeleton: Skeleton3D
var _head_idx: int = -1
var _active: bool = false
var _head_yaw: float = 0.0


func bind(root: Node3D) -> void:
	_skeleton = HeldTool.find_skeleton(root)
	_head_idx = -1
	_head_yaw = 0.0
	if _skeleton == null:
		return
	_head_idx = _skeleton.find_bone(HEAD_BONE)
	if _head_idx < 0 and _skeleton.get_bone_count() > 24:
		_head_idx = 24


func set_camera_eyes(active: bool) -> void:
	_active = active and _head_idx >= 0
	if not _active:
		_head_yaw = 0.0


func tick(delta: float) -> void:
	if not _active or _skeleton == null or _head_idx < 0:
		return
	var target_m: Vector3 = IntroTrainStage.gx_to_meters(CAM_EYES_GX)
	var head_global: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_idx)
	var to_cam: Vector3 = target_m - head_global.origin
	to_cam.y = 0.0
	if to_cam.length_squared() < 0.001:
		return
	var parent_idx: int = _skeleton.get_bone_parent(_head_idx)
	var parent_global: Transform3D = _skeleton.global_transform
	if parent_idx >= 0:
		parent_global = _skeleton.global_transform * _skeleton.get_bone_global_pose(parent_idx)
	var local_dir: Vector3 = parent_global.basis.inverse() * to_cam.normalized()
	var desired_yaw: float = atan2(local_dir.x, local_dir.z)
	desired_yaw = clampf(desired_yaw, -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)
	_head_yaw = lerp_angle(_head_yaw, desired_yaw, HEAD_YAW_CHASE * delta * 30.0)
	var anim_rot: Quaternion = _skeleton.get_bone_pose_rotation(_head_idx)
	var twist := Quaternion(Vector3.UP, _head_yaw)
	_skeleton.set_bone_pose_rotation(_head_idx, anim_rot * twist)


static func talk_yaw_toward_player(from_gx: Vector3) -> float:
	var to: Vector3 = PLAYER_GX - from_gx
	to.y = 0.0
	if to.length_squared() < 0.001:
		return 0.0
	return atan2(to.x, to.z)
