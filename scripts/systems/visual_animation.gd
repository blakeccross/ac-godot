class_name VisualAnimation
extends RefCounted
## AnimationPlayer helpers: find, stop autoplay, reset skeleton rest, strip joint tracks.


static func find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = find_animation_player(child)
		if found != null:
			return found
	return null


static func stop_autoplay(node: Node) -> void:
	## Furniture cKF clips are open/close; rest is frame 1 (closed). Do not play.
	var anim: AnimationPlayer = find_animation_player(node)
	if anim == null:
		return
	anim.autoplay = ""
	anim.stop()
	anim.seek(0.0, true)


static func stop_autoplay_keep_rest(node: Node) -> void:
	## Outdoor trains bake a non-bind `joint_0` translation into every clip frame.
	## Seeking frame 0 would shove the car off the rails — stop and snap to bind.
	var anim: AnimationPlayer = find_animation_player(node)
	if anim != null:
		anim.autoplay = ""
		anim.stop()
	reset_skeleton_rest(node)


static func reset_skeleton_rest(node: Node) -> void:
	## Clear AnimationPlayer pose and snap every Skeleton3D back to bind.
	if node == null:
		return
	if node is Skeleton3D:
		(node as Skeleton3D).reset_bone_poses()
	for child in node.get_children():
		reset_skeleton_rest(child)


static func strip_named_joint_tracks(
	anim_player: AnimationPlayer,
	joint_name: String = "joint_0",
	clip_names: PackedStringArray = PackedStringArray(),
) -> void:
	## Drop position/rotation tracks on `joint_name` so door/wheel clips cannot move the root.
	## When `clip_names` is set, only those animations (exact or suffix match) are edited.
	if anim_player == null or joint_name.is_empty():
		return
	var needle := ":%s:" % joint_name
	var needle_end := ":%s" % joint_name
	for clip_name: String in anim_player.get_animation_list():
		if not clip_names.is_empty() and not _clip_name_matches(clip_name, clip_names):
			continue
		var animation: Animation = anim_player.get_animation(clip_name)
		if animation == null:
			continue
		for track_i: int in range(animation.get_track_count() - 1, -1, -1):
			var path := String(animation.track_get_path(track_i))
			if path.contains(needle) or path.ends_with(needle_end):
				animation.remove_track(track_i)


static func _clip_name_matches(clip_name: String, names: PackedStringArray) -> bool:
	for want: String in names:
		if want.is_empty():
			continue
		if clip_name == want or clip_name.ends_with("/" + want) or clip_name.ends_with(want):
			return true
	return false
