class_name PlayerHeadLook
extends RefCounted

## The player's `head_angle` (`Player_actor_draw_Before_head`): extra turns on the head
## joint after the animation — `RotateX(head_angle.x)` then `RotateY(head_angle.y)` in the
## joint's own frame (here: turn about the vertical, then tilt up). Only `release_creature` sets it: the player watches what they let go
## (`Player_actor_Look_Release_creature`).

## cKF joint 24, named after the head mesh it draws (`head_boy_model` / `head_girl_model`).
const HEAD_JOINT := 24
const HEAD_PREFIX := "head_"
## `Player_actor_add_calc_head_angle`: `add_calc_short_angle2(…, 1 − √0.5, 500, 0)`.
const CHASE := 0.29289322
const MAX_STEP := 500.0 * TAU / 65536.0
## Clamps against the body (`DEG2SHORT_ANGLE2(60)` / `(30)`).
const YAW_LIMIT := deg_to_rad(60.0)
const PITCH_LIMIT := deg_to_rad(30.0)
## Too close to bother (`dist_xz >= 18`).
const NEAR_GX := 18.0
## `actorx->eye.position`: about the player's eye height.
const EYE_GX := 33.0

## `head_angle.x` (follows the target's bearing) and `.y` (its elevation), radians.
var angle := Vector2.ZERO
## The body's facing the bearing is measured from.
var body_yaw: float = 0.0
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _idx: int = -1
## The animation's own head pose, and what was last written over it — a pose still equal to
## that at mix time was not touched by the animation this frame.
var _base := Quaternion.IDENTITY
var _written := Quaternion.IDENTITY


func bind(skeleton: Skeleton3D, anim: AnimationPlayer) -> void:
	unbind()
	_skeleton = skeleton
	_anim = anim
	_idx = -1
	if skeleton != null:
		for i: int in skeleton.get_bone_count():
			if skeleton.get_bone_name(i).begins_with(HEAD_PREFIX):
				_idx = i
				break
		if _idx < 0 and skeleton.get_bone_count() > HEAD_JOINT:
			_idx = HEAD_JOINT
	if _anim != null and _idx >= 0 and not _anim.mixer_applied.is_connected(_apply):
		_anim.mixer_applied.connect(_apply)


func unbind() -> void:
	if _skeleton != null and is_instance_valid(_skeleton) and _idx >= 0 and _written != Quaternion.IDENTITY:
		if _skeleton.get_bone_pose_rotation(_idx).is_equal_approx(_written):
			_skeleton.set_bone_pose_rotation(_idx, _base)
	if _anim != null and is_instance_valid(_anim) and _anim.mixer_applied.is_connected(_apply):
		_anim.mixer_applied.disconnect(_apply)
	_anim = null
	_skeleton = null
	_idx = -1


## The bearing and elevation to aim the head at, clamped, from the eye at `eye` with the
## body facing `body_yaw` (radians, forward = (sin, cos)). Zero when the target is close.
static func want(eye: Vector3, body_yaw: float, target: Vector3) -> Vector2:
	var d: Vector3 = target - eye
	var xz: float = Vector2(d.x, d.z).length()
	if xz < NEAR_GX * FieldCatalog.GX_TO_METERS:
		return Vector2.ZERO
	var yaw: float = wrapf(atan2(d.x, d.z) - body_yaw, -PI, PI)
	var pitch: float = atan2(d.y, xz)
	return Vector2(clampf(yaw, -YAW_LIMIT, YAW_LIMIT), clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT))


## One tick toward `target`.
func step(target: Vector2) -> void:
	angle.x = _calc(angle.x, target.x)
	angle.y = _calc(angle.y, target.y)


static func _calc(now: float, goal: float) -> float:
	var diff: float = angle_difference(now, goal) * CHASE
	return now + clampf(diff, -MAX_STEP, MAX_STEP)


func _apply() -> void:
	if _skeleton == null or _idx < 0:
		return
	var pose: Quaternion = _skeleton.get_bone_pose_rotation(_idx)
	if not pose.is_equal_approx(_written):
		_base = pose
	## The turn is made in world terms — about the vertical, then about the body's sideways
	## axis — and carried into the joint's parent frame, so it does not hang on how the
	## converted joint axes lie.
	var fwd := Vector3(sin(body_yaw), 0.0, cos(body_yaw))
	var world_turn := Basis(Vector3.UP, angle.x) * Basis(fwd.cross(Vector3.UP).normalized(), angle.y)
	var parent: int = _skeleton.get_bone_parent(_idx)
	var frame: Basis = _skeleton.global_transform.basis.orthonormalized()
	if parent >= 0:
		frame = (frame * _skeleton.get_bone_global_pose(parent).basis).orthonormalized()
	var local_turn: Basis = frame.inverse() * world_turn * frame
	_written = local_turn.get_rotation_quaternion() * _base
	_skeleton.set_bone_pose_rotation(_idx, _written)
