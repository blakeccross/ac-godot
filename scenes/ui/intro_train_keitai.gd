class_name IntroTrainKeitai
extends Node3D

## Phone prop on Rover's right hand (`aNPC_JOINT_HAND` / joint 20).
## Decomp: `aNPC_set_right_hand_item` copies the hand joint matrix into `T_Keitai`.

const CLIP_ON_SUFFIX := "keitai_on1"
const CLIP_OFF_SUFFIX := "keitai_off1"
const ATTACH_NAME := "KeitaiHand"

var _anim: AnimationPlayer


func _ready() -> void:
	_anim = GeneratedVisual.find_animation_player(self)
	if _anim != null:
		_anim.stop()
	visible = false
	call_deferred("bind_to_hand")


## Parent under Rover's HAND bone. Safe to call more than once.
func bind_to_hand() -> bool:
	if get_parent() is BoneAttachment3D:
		_normalize_local_pose()
		return true
	var rover: Node = _rover_host()
	if rover == null:
		return false
	var skeleton: Skeleton3D = HeldTool.find_skeleton(rover)
	if skeleton == null:
		return false
	var bone: String = _hand_bone_name(skeleton)
	if bone.is_empty():
		return false
	var attach: BoneAttachment3D = skeleton.get_node_or_null(ATTACH_NAME) as BoneAttachment3D
	if attach == null:
		attach = BoneAttachment3D.new()
		attach.name = ATTACH_NAME
		skeleton.add_child(attach)
	attach.bone_name = bone
	reparent(attach, false)
	_normalize_local_pose()
	return true


func play_on(speed_scale: float = 1.0) -> void:
	bind_to_hand()
	visible = true
	_play(CLIP_ON_SUFFIX, speed_scale)


func play_off(speed_scale: float = 1.0) -> void:
	bind_to_hand()
	visible = true
	_play(CLIP_OFF_SUFFIX, speed_scale)


func hide_phone() -> void:
	if _anim != null:
		_anim.stop()
	visible = false


func _rover_host() -> Node:
	var node: Node = get_parent()
	while node != null:
		if node is IntroTrainRoverAnim:
			return node
		if node.name == "Rover":
			return node
		node = node.get_parent()
	return null


func _hand_bone_name(skeleton: Skeleton3D) -> String:
	if skeleton.find_bone(HeldTool.HAND_BONE) != -1:
		return HeldTool.HAND_BONE
	if skeleton.get_bone_count() > 20:
		return skeleton.get_bone_name(20)
	return ""


func _normalize_local_pose() -> void:
	## Hand matrix already sits under Rover's actor-scaled visual — identity local,
	## and no second `actor_uniform_scale` on the phone pivot (`HeldTool` same rule).
	transform = Transform3D.IDENTITY
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis != null:
		vis.transform = Transform3D.IDENTITY


func _play(suffix: String, speed_scale: float) -> void:
	if _anim == null:
		_anim = GeneratedVisual.find_animation_player(self)
	if _anim == null:
		return
	var clip: String = _resolve_clip(suffix)
	if clip.is_empty():
		return
	var animation: Animation = _anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_NONE
	_anim.speed_scale = speed_scale
	_anim.play(clip)


func _resolve_clip(suffix: String) -> String:
	if _anim == null or suffix.is_empty():
		return ""
	if _anim.has_animation(suffix):
		return suffix
	for anim_name: String in _anim.get_animation_list():
		if anim_name.ends_with(suffix) or suffix in anim_name:
			return anim_name
	return ""
