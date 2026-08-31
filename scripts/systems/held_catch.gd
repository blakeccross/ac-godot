class_name HeldCatch
extends RefCounted

## Attaches the caught fish to the player's left hand for the show-off pose.
##
## Faithful, not a flourish: `aGTT_comeback` copies the hooked fish onto `uki->uki_pos`
## every frame, and `aUKI_catch` / `aUKI_get` set `uki_pos = uki->left_hand_pos` while the
## bobber actor itself sits at `right_hand_pos`. So through `GET_T1` and `GET_T2` the player
## holds the rod in one hand and the fish in the other, and `aGYO_DRAW_TYPE_FISH` swaps the
## shadow quad for the real `act_f*` model. `HeldFish` does the drawing.
##
## `HeldTool` already owns `mPlayer_JOINT_HAND` (joint 20) for the rod and the skeleton has
## no second hand joint, so the catch hangs off `mPlayer_JOINT_LARM2` (joint 16), the left
## forearm tip, which is the nearest thing to `left_hand_pos` the rig gives us.

const ARM_BONE := "joint_16"
const ARM_BONE_INDEX := 16
const ATTACH_NAME := "HeldCatch"
const HAND_NAME := "HandPoint"

## `mPlayer_JOINT_RARM2` and the right hand joint past it. The left arm chain stops at the
## elbow, so the length of the right arm's own hand segment stands in for the missing one.
const RARM2_INDEX := 19
const RHAND_INDEX := 20


static func bind(skeleton: Skeleton3D, fish: FishData) -> Node3D:
	unbind(skeleton)
	if skeleton == null or fish == null:
		return null
	var bone := _arm_bone_name(skeleton)
	if bone.is_empty():
		return null
	var visual: HeldFish = HeldFish.create(fish)
	if visual == null:
		return null
	var attach := BoneAttachment3D.new()
	attach.name = ATTACH_NAME
	skeleton.add_child(attach)
	attach.bone_name = bone
	## `Player_actor_draw_After_Larm2` does not hold the catch at the joint: it runs
	## `Matrix_Position_VecX(1100.0f)` off the Larm2 matrix and calls *that* `left_hand_pos`.
	## The joint is the elbow -- the left chain has no hand joint, which is why the original
	## computes one -- so binding to it puts the forearm and fist inside the fish.
	var hand := Node3D.new()
	hand.name = HAND_NAME
	hand.position = _hand_offset(skeleton)
	attach.add_child(hand)
	hand.add_child(visual)
	return attach


## The missing hand joint, in Larm2's own space: one hand segment further along the arm.
## Measured off the rig rather than transcribing 1100, whose units are the original's
## model space and do not survive the pipeline.
static func _hand_offset(skeleton: Skeleton3D) -> Vector3:
	var elbow: int = ARM_BONE_INDEX
	var shoulder: int = skeleton.get_bone_parent(elbow)
	if shoulder < 0 or skeleton.get_bone_count() <= RHAND_INDEX:
		return Vector3.ZERO
	var pose: Transform3D = skeleton.get_bone_global_pose(elbow)
	## Direction the arm already points, carried into the joint's own frame. Rigid bones, so
	## this holds for every pose even though it is read once.
	var along: Vector3 = pose.origin - skeleton.get_bone_global_pose(shoulder).origin
	if along.length_squared() < 0.000001:
		return Vector3.ZERO
	var reach: float = (
		skeleton.get_bone_global_pose(RHAND_INDEX).origin
		- skeleton.get_bone_global_pose(RARM2_INDEX).origin
	).length()
	return pose.basis.inverse() * (along.normalized() * reach)


static func unbind(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	var attach: Node = skeleton.get_node_or_null(ATTACH_NAME)
	if attach == null:
		return
	skeleton.remove_child(attach)
	attach.free()


static func is_held(skeleton: Skeleton3D) -> bool:
	return skeleton != null and skeleton.get_node_or_null(ATTACH_NAME) != null


static func held_fish(skeleton: Skeleton3D) -> HeldFish:
	if skeleton == null:
		return null
	var attach: Node = skeleton.get_node_or_null(ATTACH_NAME)
	if attach == null:
		return null
	return attach.find_child("HeldFish", true, false) as HeldFish


static func _arm_bone_name(skeleton: Skeleton3D) -> String:
	if skeleton.find_bone(ARM_BONE) != -1:
		return ARM_BONE
	if skeleton.get_bone_count() > ARM_BONE_INDEX:
		return skeleton.get_bone_name(ARM_BONE_INDEX)
	return ""
