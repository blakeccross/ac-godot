class_name HeldTool
extends RefCounted

## Equipped field tool parented to the player HAND joint.
## Decomp: `Player_actor_Item_draw` loads `player->right_hand_mtx` from
## `Player_actor_draw_After_hand` on `mPlayer_JOINT_HAND` (joint 20), then draws
## axe / scoop Gfx or the net / rod cKF. Identity in that space — do not ground-fit.

const HAND_BONE := "joint_20"
const ATTACH_NAME := "HeldTool"


static func find_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found: Skeleton3D = find_skeleton(child)
		if found != null:
			return found
	return null


static func bind(skeleton: Skeleton3D, visual_id: StringName) -> Node3D:
	unbind(skeleton)
	if skeleton == null or visual_id == &"":
		return null
	var bone := _hand_bone_name(skeleton)
	if bone.is_empty():
		return null
	var visual: Node3D = GeneratedVisual.instantiate_raw(visual_id)
	if visual == null:
		return null
	## Drawn straight off `right_hand_mtx` (`Player_actor_Item_draw` → `gSPDisplayList(tol_axe_1_model)`),
	## no extra rotation: the player GLB binds on `wait1` with no `ckf_basis`, so the HAND bone's
	## global pose *is* the cKF hand matrix, and static tool verts keep their GX axes.
	var attach := BoneAttachment3D.new()
	attach.name = ATTACH_NAME
	skeleton.add_child(attach)
	attach.bone_name = bone
	attach.add_child(visual)
	attach.set_meta(&"visual_id", visual_id)
	var anim: AnimationPlayer = _find_animation_player(visual)
	if anim != null:
		anim.autoplay = ""
		anim.stop()
	return attach


static func unbind(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	var attach: Node = skeleton.get_node_or_null(ATTACH_NAME)
	if attach == null:
		return
	skeleton.remove_child(attach)
	attach.free()


## `player->item_scale` (`Player_actor_Item_draw`): the tool shrinks into / grows out of the
## hand during put-away / take-out. Scales the visual, not the `BoneAttachment3D`, which
## re-syncs its own transform to the bone every frame.
static func set_scale(skeleton: Skeleton3D, item_scale: float) -> void:
	if skeleton == null:
		return
	var attach: Node = skeleton.get_node_or_null(ATTACH_NAME)
	if attach == null or attach.get_child_count() == 0:
		return
	var visual := attach.get_child(0) as Node3D
	if visual == null:
		return
	visual.visible = item_scale > 0.001
	visual.scale = Vector3.ONE * maxf(item_scale, 0.001)


static func play(skeleton: Skeleton3D, clip_name: StringName, loop: bool = true) -> void:
	if skeleton == null or clip_name == &"":
		return
	var attach: Node = skeleton.get_node_or_null(ATTACH_NAME)
	if attach == null:
		return
	var anim: AnimationPlayer = _find_animation_player(attach)
	var clip := _resolve_clip(anim, String(clip_name))
	if clip.is_empty():
		anim = _borrow_clip(attach, clip_name)
		clip = _resolve_clip(anim, String(clip_name))
	if clip.is_empty():
		return
	var animation: Animation = anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	anim.play(clip, 0.08)


## Sibling tools share one clip (`tol_kaza2`…`8` turn on `tol_kaza1_wait`): copy it from the
## visual the clip is named after and point its tracks at this tool's joints.
static func _borrow_clip(attach: Node, clip_name: StringName) -> AnimationPlayer:
	var target := String(attach.get_meta(&"visual_id", &""))
	var source := String(clip_name).get_slice("_", 0) + "_" + String(clip_name).get_slice("_", 1)
	if target.is_empty() or source == target or attach.get_child_count() == 0:
		return null
	var donor: Node3D = GeneratedVisual.instantiate_raw(StringName(source))
	if donor == null:
		return null
	var donor_anim: AnimationPlayer = _find_animation_player(donor)
	var donor_clip := _resolve_clip(donor_anim, String(clip_name))
	if donor_clip.is_empty():
		donor.free()
		return null
	var animation: Animation = donor_anim.get_animation(donor_clip).duplicate(true)
	for t: int in animation.get_track_count():
		animation.track_set_path(t, NodePath(String(animation.track_get_path(t)).replace(source, target)))
	var visual: Node = attach.get_child(0)
	var anim: AnimationPlayer = _find_animation_player(visual)
	if anim == null:
		anim = AnimationPlayer.new()
		anim.name = "AnimationPlayer"
		## Same place in the tree as the donor's, so the relative track paths hold.
		var donor_parent: Node = donor_anim.get_parent()
		var host: Node = visual
		if donor_parent != donor:
			host = visual.get_node_or_null(NodePath(String(donor.get_path_to(donor_parent)).replace(source, target)))
			if host == null:
				host = visual
		host.add_child(anim)
		anim.root_node = donor_anim.root_node
	var lib: AnimationLibrary = anim.get_animation_library(&"") if anim.has_animation_library(&"") else null
	if lib == null:
		lib = AnimationLibrary.new()
		anim.add_animation_library(&"", lib)
	lib.add_animation(StringName(String(clip_name)), animation)
	donor.free()
	return anim


## The bound tool's own `AnimationPlayer` (a pinwheel's spin), or null.
static func animation_player(skeleton: Skeleton3D) -> AnimationPlayer:
	var attach: Node = skeleton.get_node_or_null(ATTACH_NAME) if skeleton != null else null
	return _find_animation_player(attach) if attach != null else null


static func _hand_bone_name(skeleton: Skeleton3D) -> String:
	if skeleton.find_bone(HAND_BONE) != -1:
		return HAND_BONE
	if skeleton.get_bone_count() > 20:
		return skeleton.get_bone_name(20)
	return ""


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


static func _resolve_clip(anim: AnimationPlayer, suffix: String) -> String:
	if anim == null or suffix.is_empty():
		return ""
	if anim.has_animation(suffix):
		return suffix
	for anim_name: String in anim.get_animation_list():
		if anim_name.ends_with(suffix) or suffix in anim_name:
			return anim_name
	return ""
