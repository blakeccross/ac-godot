class_name TalkCamera
extends RefCounted

## `CAMERA2_PROCESS_TALK` helpers (`m_camera2.c`). Finds the active `FollowCamera`.
## Call `begin(player, npc)` — decomp `Camera2_request_main_talk` speaker = player.

const BASE_DIST_GX := 290.0
const DIST_SCALE := 1.46
## Talk defaults -164.114° + ~8° bump → inv pitch ≈ 23.8° (`Camera2_PolaPosCalc`).
const PITCH_INV_DEG := 23.8
const EYE_HEIGHT_M := 1.15
## `Camera2_Talk_GetAngleY` max nudge (deg) when the pair is mostly N/S.
const YAW_TWEAK_DEG := 15.0
## `Player_actor_Movement_Talk` turn (`add_calc_short_angle2`, once per ~60 Hz frame).
const TURN_HZ := 60.0
const TURN_FRACTION := 0.292893 ## 1 - sqrt(0.5)
const TURN_MAX_STEP := TAU * 2500.0 / 65536.0 ## ~13.73°
const TURN_MIN_STEP := TAU * 50.0 / 65536.0 ## ~0.275°


static func begin(speaker: Node3D, listener: Node3D, tree: SceneTree = null) -> void:
	var cam: Node = _camera(tree)
	if cam != null and cam.has_method("begin_talk"):
		cam.call("begin_talk", speaker, listener)
	## `mDemo` TYPE_TALK defaults `turn = TRUE` → player faces the NPC.
	if speaker != null and speaker.has_method("begin_talk_face"):
		speaker.call("begin_talk_face", listener)


static func end(tree: SceneTree = null) -> void:
	var cam: Node = _camera(tree)
	if cam != null and cam.has_method("end_talk"):
		cam.call("end_talk")
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group("player"):
		if node.has_method("end_talk_face"):
			node.call("end_talk_face")


## Yaw so `from` looks at `toward` on XZ (`player_angle_y + 180°` for the player).
static func face_yaw_toward(from: Vector3, toward: Vector3) -> float:
	var delta := Vector3(toward.x - from.x, 0.0, toward.z - from.z)
	if delta.length_squared() < 0.0001:
		return 0.0
	return atan2(delta.x, delta.z)


static func eye_of(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	if node.has_method("camera_look_position"):
		return node.call("camera_look_position") as Vector3
	return node.global_position + Vector3(0.0, EYE_HEIGHT_M, 0.0)


static func frame(speaker: Node3D, listener: Node3D) -> Dictionary:
	## Returns `{ "center", "eye", "distance", "yaw_tweak_deg" }` in world meters.
	var s_eye: Vector3 = eye_of(speaker)
	var l_eye: Vector3 = eye_of(listener)
	var between_m: float = s_eye.distance_to(l_eye)
	var between_gx: float = between_m / FieldCatalog.GX_TO_METERS
	## `y_adjust = 17 - (-60 / dist)` → lower the look target slightly.
	var y_adj: float = (17.0 + 60.0 / maxf(between_gx, 1.0)) * FieldCatalog.GX_TO_METERS
	var center: Vector3 = (s_eye + l_eye) * 0.5
	center.y -= y_adj
	var dist: float = (BASE_DIST_GX + between_gx * DIST_SCALE) * FieldCatalog.GX_TO_METERS
	## GetAngleY uses world (feet) positions, not eyes.
	var s_pos: Vector3 = speaker.global_position if speaker != null else s_eye
	var l_pos: Vector3 = listener.global_position if listener != null else l_eye
	var yaw_tweak: float = yaw_tweak_deg(s_pos, l_pos)
	## Talk goal dir Y is -180°; `PolaPosCalc` adds 180° → inv yaw starts at 0 + tweak.
	var inv_yaw: float = deg_to_rad(yaw_tweak)
	var inv_pitch: float = deg_to_rad(PITCH_INV_DEG)
	var eye: Vector3 = center
	eye.y += dist * sin(inv_pitch)
	var dist_xz: float = dist * cos(inv_pitch)
	eye.x += dist_xz * sin(inv_yaw)
	eye.z += dist_xz * cos(inv_yaw)
	return {
		"center": center,
		"eye": eye,
		"distance": dist,
		"yaw_tweak_deg": yaw_tweak,
	}


## `Camera2_Talk_GetAngleY` — ±15° on goal dir Y when speaker→listener is mostly N/S.
## East-of-north vs west-of-north (or the south equivalents) flip the sign.
static func yaw_tweak_deg(speaker_pos: Vector3, listener_pos: Vector3) -> float:
	var delta := Vector3(listener_pos.x - speaker_pos.x, 0.0, listener_pos.z - speaker_pos.z)
	if delta.length_squared() < 0.0001:
		return 0.0
	var angle_y: float = atan2(delta.x, delta.z)
	var deg: float = rad_to_deg(angle_y)
	## E/W band: no nudge (camera stays on world-south).
	if (deg > 45.0 and deg < 135.0) or (deg < -45.0 and deg > -135.0):
		return 0.0
	var add: float = cos(2.0 * angle_y) * YAW_TWEAK_DEG
	if cos(angle_y) * sin(angle_y) >= 0.0:
		return -add
	return add


static func _camera(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var cams: Array[Node] = tree.get_nodes_in_group("follow_camera")
	if not cams.is_empty():
		return cams[0]
	return tree.get_first_node_in_group("follow_camera")
