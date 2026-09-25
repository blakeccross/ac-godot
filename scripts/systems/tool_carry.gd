class_name ToolCarry
extends RefCounted

## How the player carries the item in hand (`Player_actor_SetupItem_Base3` → anim1 with
## `mPlib_Get_BasicPartTableIndex_fromAnimeIndex`). While standing, walking, running or dashing
## the body plays its own clip (anim0) and the joints the part table names take the item's
## carry clip (anim1: `AXE1`, `NET1`, `SAO1`, `SCOOP1`, `UMBRELLA1`) instead — the
## `BOY_part_data` overlay. Both clips run on their own clocks at the same frame speed.

## `BOY_part_data` rows, as cKF joint indices (bone order == joint order in the player GLB).
## AXE: both arms (`LARM_BASE` … `HAND`); NET: the right arm (`RARM_BASE` … `HAND`).
const PART_JOINTS := {
	ToolData.CarryPart.AXE: [14, 15, 16, 17, 18, 19, 20],
	ToolData.CarryPart.NET: [17, 18, 19, 20],
}
## Body clips the overlay rides on (`mPlayer_INDEX_WAIT` / `WALK` / `RUN` / `DASH`). Every other
## state plays one clip on both keyframes with `mPlayer_PART_TABLE_NORMAL`.
const LOCOMOTION_CLIPS: Array[String] = ["ply_1_wait1", "ply_1_walk1", "ply_1_run1", "ply_1_dash1"]

var clip: Animation
## bone index → rotation track index in `clip`.
var tracks: Dictionary = {}
## Part-table joints the clip has no track for: the GLB writer drops tracks that never leave
## the rest pose, so anim1's value there is the bone's rest rotation.
var rest: Dictionary = {}
var time: float = 0.0


## Null when the tool has no carry clip or the player GLB lacks it.
static func build(anim: AnimationPlayer, skeleton: Skeleton3D, tool: ToolData) -> ToolCarry:
	if anim == null or skeleton == null or tool == null or tool.hold_anim == &"":
		return null
	var joints: Array = PART_JOINTS.get(tool.carry_part, [])
	if joints.is_empty():
		return null
	var clip_name: String = ""
	for n: String in anim.get_animation_list():
		if n.ends_with(String(tool.hold_anim)):
			clip_name = n
			break
	if clip_name == "":
		return null
	var carry := ToolCarry.new()
	carry.clip = anim.get_animation(clip_name)
	var wanted: Dictionary = {}
	for joint: int in joints:
		if joint < skeleton.get_bone_count():
			wanted[skeleton.get_bone_name(joint)] = joint
	for i: int in carry.clip.get_track_count():
		if carry.clip.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var bone: String = String(carry.clip.track_get_path(i).get_concatenated_subnames())
		if wanted.has(bone):
			carry.tracks[wanted[bone]] = i
	if carry.tracks.is_empty():
		return null
	for joint: int in wanted.values():
		if not carry.tracks.has(joint):
			carry.rest[joint] = skeleton.get_bone_rest(joint).basis.get_rotation_quaternion()
	return carry


## True while `playing` is a locomotion clip — the only states that layer anim1.
static func rides_on(playing: String) -> bool:
	for leaf: String in LOCOMOTION_CLIPS:
		if playing.ends_with(leaf):
			return true
	return false


func advance(delta: float) -> void:
	var length: float = clip.length if clip != null else 0.0
	time = fmod(time + delta, length) if length > 0.0 else 0.0


## Write the carry clip's rotations for this frame onto the part table's joints.
func apply(skeleton: Skeleton3D) -> void:
	for bone: int in tracks:
		skeleton.set_bone_pose_rotation(bone, clip.rotation_track_interpolate(tracks[bone], time))
	for bone: int in rest:
		skeleton.set_bone_pose_rotation(bone, rest[bone])
