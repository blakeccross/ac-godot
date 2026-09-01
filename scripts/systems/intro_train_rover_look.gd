class_name IntroTrainRoverLook
extends RefCounted

## Rover head look-at during train intro (`aNGD_set_camera_eyes` / `aNPC_set_head_angl`).

const HEAD_BONE := "joint_21" ## `aNPC_JOINT_HEAD_ROOT` — draw override index 21.
const CAM_EYES_XZ_GX := Vector2(100.0, 400.0)
const HEAD_YAW_CHASE := deg_to_rad(11.25)
const HEAD_PITCH_CHASE := deg_to_rad(5.625)
const HEAD_YAW_LIMIT := deg_to_rad(67.5)
const HEAD_PITCH_LIMIT := deg_to_rad(33.75)

var _skeleton: Skeleton3D
var _actor: Node3D
var _head_idx: int = -1
var _active: bool = false
var _head_yaw: float = 0.0
var _head_pitch: float = 0.0


func bind(root: Node3D) -> void:
	_actor = root
	_skeleton = HeldTool.find_skeleton(root)
	_head_idx = -1
	_head_yaw = 0.0
	_head_pitch = 0.0
	if _skeleton == null:
		return
	_head_idx = _skeleton.find_bone(HEAD_BONE)
	if _head_idx < 0 and _skeleton.get_bone_count() > 21:
		_head_idx = 21


func set_camera_eyes(active: bool) -> void:
	_active = active and _head_idx >= 0
	if not _active:
		_head_yaw = 0.0
		_head_pitch = 0.0


func tick(delta: float) -> void:
	if not _active or _skeleton == null or _head_idx < 0 or _actor == null:
		return
	var head_global: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_idx)
	var eye_m: Vector3 = head_global.origin
	var target_m: Vector3 = Vector3(
		CAM_EYES_XZ_GX.x, eye_m.y / FieldCatalog.GX_TO_METERS, CAM_EYES_XZ_GX.y
	) * FieldCatalog.GX_TO_METERS
	var body_yaw: float = _actor.global_rotation.y
	var to_target: Vector3 = target_m - eye_m
	var horiz: float = Vector2(to_target.x, to_target.z).length()
	var desired_pitch: float = -atan2(to_target.y, horiz) if horiz > 0.001 else 0.0
	var desired_yaw: float = atan2(to_target.x, to_target.z) - body_yaw
	desired_pitch = clampf(desired_pitch, -HEAD_PITCH_LIMIT, HEAD_PITCH_LIMIT)
	if absf(desired_yaw) > HEAD_YAW_LIMIT:
		desired_yaw = signf(desired_yaw) * HEAD_YAW_LIMIT
	var chase: float = delta * 30.0
	_head_pitch = lerp_angle(_head_pitch, desired_pitch, HEAD_PITCH_CHASE * chase)
	_head_yaw = lerp_angle(_head_yaw, desired_yaw, HEAD_YAW_CHASE * chase)
	## Decomp draw override: `rot.x = head.angle_y`, `rot.y = head.angle_x`.
	var head_rot := Quaternion.from_euler(Vector3(_head_yaw, _head_pitch, 0.0))
	_skeleton.set_bone_pose_rotation(_head_idx, head_rot)
