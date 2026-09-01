class_name StructureDoor
extends RefCounted

## Outdoor structure door clips (`ac_house` / `ac_my_house` / `ac_shop`) plus the
## player OPEN1 step-in (`mPlayer_INDEX_DOOR`) and GO_OUT emerge
## (`mPlayer_INDEX_OUTDOOR`). Enter starts door + OPEN1 together; the field swap
## waits on the structure clip. Exit warps outdoors then plays leave + GO_OUT.

## cKF plays these at speed 0.5 on a 60 Hz move tick (= 30 anim fps). Pipeline
## samples at 30 fps, so Godot speed 1.0 matches the original duration (~1.67 s).

## `AnimationMove_ct_base` fixed_counter 9 at −0.5 / frame → ~0.3 s blend to door.
const APPROACH_SEC := 9.0 / 30.0
## Demo `size_adj` floor when house_info.size is 0 (`aMHS_set_demo_info`).
const APPROACH_GX := 20.0
## `cKF_ba_r_ply_1_go_out_s1` frame count (demo outdoor start).
const LEAVE_SEC := 31.0 / 30.0
## How far past the door stand the emerge walk finishes.
const LEAVE_GX := 40.0
## `cKF_ba_r_ply_1_into_s1` frame count (indoor door / exit walk).
const INTO_SEC := 49.0 / 30.0
## Indoor exit walks this far south past the door cell center.
const INTO_GX := 30.0


static func play_enter(host: Node) -> void:
	var root: Node3D = _structure_root(host)
	var player: Node = _find_player(host)
	if root != null and player != null and player.has_method("begin_door_enter"):
		var target: Vector3 = approach_position(root)
		var yaw: float = enter_yaw(root, player.global_position)
		player.call("begin_door_enter", target, yaw)
	await _play(host, true)
	if player != null and is_instance_valid(player) and player.has_method("end_door_enter"):
		player.call("end_door_enter")


static func play_emerge(host: Node) -> void:
	## Outdoor start after indoor leave: structure leave clip + player GO_OUT.
	var root: Node3D = _structure_root(host)
	var player: Node = _find_player(host)
	if root != null and player != null and player.has_method("begin_door_leave"):
		var stand: Vector3 = approach_position(root)
		var out_yaw: float = leave_yaw(root, stand)
		var out_dir := Vector3(sin(out_yaw), 0.0, cos(out_yaw))
		var target: Vector3 = stand + out_dir * (LEAVE_GX * FieldCatalog.GX_TO_METERS)
		target.y = stand.y
		player.call("begin_door_leave", stand, target, out_yaw)
	await _play(host, false)
	if player != null and is_instance_valid(player) and player.has_method("end_door_leave"):
		player.call("end_door_leave")


static func play_leave(host: Node) -> void:
	await _play(host, false)


static func find_near(from: Node, pos: Vector3, max_dist: float = 8.0) -> Node3D:
	## Closest outdoor house/shop with a GeneratedVisual (door cKF host).
	if from == null or from.get_tree() == null:
		return null
	var best: Node3D = null
	var best_d: float = max_dist * max_dist
	for n: Node in from.get_tree().get_nodes_in_group("interactable"):
		if not (n is Node3D):
			continue
		var root: Node3D = _structure_root(n)
		if root == null or root.get_node_or_null("GeneratedVisual") == null:
			continue
		if not _is_door_structure(root):
			continue
		var d: float = pos.distance_squared_to(root.global_position)
		if d < best_d:
			best_d = d
			best = root
	return best


static func approach_position(root: Node3D) -> Vector3:
	## Demo walks the player to `actor + size_adj * direct` (`wait_door_start`).
	## Use the door sensor, then step toward the building by ~20 GX.
	if root == null:
		return Vector3.ZERO
	var door: Vector3 = _door_sensor_world(root)
	var into: Vector3 = root.global_position - door
	into.y = 0.0
	if into.length_squared() < 0.0001:
		into = -root.global_transform.basis.z
		into.y = 0.0
	if into.length_squared() < 0.0001:
		into = Vector3(0.0, 0.0, -1.0)
	into = into.normalized()
	var target: Vector3 = door + into * (APPROACH_GX * FieldCatalog.GX_TO_METERS)
	target.y = door.y
	return target


static func enter_yaw(root: Node3D, from: Vector3) -> float:
	## Face into the doorway (toward the structure).
	if root == null:
		return 0.0
	var to: Vector3 = root.global_position - from
	to.y = 0.0
	if to.length_squared() < 0.0001:
		to = -root.global_transform.basis.z
		to.y = 0.0
	if to.length_squared() < 0.0001:
		return 0.0
	return atan2(to.x, to.z)


static func leave_yaw(root: Node3D, from: Vector3) -> float:
	## Face out of the doorway (away from the structure).
	return fposmod(enter_yaw(root, from) + PI, TAU)


static func _play(host: Node, entering: bool) -> void:
	var root: Node3D = _structure_root(host)
	if root == null:
		return
	var anim: AnimationPlayer = GeneratedVisual.find_animation_player(root)
	if anim == null:
		return
	var visual_id: StringName = _visual_id(root)
	var clip: String = enter_clip(anim, visual_id) if entering else leave_clip(anim, visual_id)
	if clip.is_empty():
		return
	anim.play(clip)
	if anim.current_animation_length <= 0.0:
		return
	await anim.animation_finished


static func enter_clip(anim: AnimationPlayer, visual_id: StringName) -> String:
	## Villager houses use `*_out` for player enter (`aHUS_REQUEST_PLAYER_ENTER`).
	## Player house and shop use the base door clip (`aMHS` / `aSHOP`).
	if anim == null:
		return ""
	for base: String in _candidate_bases(visual_id, anim):
		var out_name: String = "%s_out" % base
		if _is_villager_house(base) and _has_clip(anim, out_name):
			return _resolve(anim, out_name)
		if _has_clip(anim, base):
			return _resolve(anim, base)
		if _has_clip(anim, out_name):
			return _resolve(anim, out_name)
	return ""


static func leave_clip(anim: AnimationPlayer, visual_id: StringName) -> String:
	## Leave / emerge uses the opposite table from enter.
	if anim == null:
		return ""
	for base: String in _candidate_bases(visual_id, anim):
		var out_name: String = "%s_out" % base
		if _is_villager_house(base):
			if _has_clip(anim, base):
				return _resolve(anim, base)
			if _has_clip(anim, out_name):
				return _resolve(anim, out_name)
			continue
		if _has_clip(anim, out_name):
			return _resolve(anim, out_name)
		if _has_clip(anim, base):
			return _resolve(anim, base)
	return ""


static func _structure_root(host: Node) -> Node3D:
	if host == null:
		return null
	if host is Node3D and host.get_node_or_null("GeneratedVisual") != null:
		return host as Node3D
	var parent: Node = host.get_parent()
	if parent is Node3D and parent.get_node_or_null("GeneratedVisual") != null:
		return parent as Node3D
	return host as Node3D


static func _is_door_structure(root: Node) -> bool:
	var vid: String = String(_visual_id(root))
	if vid.is_empty():
		return false
	return vid.contains("house") or vid.contains("myhome") or vid.contains("shop")


static func _find_player(host: Node) -> Node:
	if host == null or host.get_tree() == null:
		return null
	return host.get_tree().get_first_node_in_group("player")


static func _door_sensor_world(root: Node3D) -> Vector3:
	for name: String in ["InteractVolume", "Door"]:
		var node: Node = root.get_node_or_null(name)
		if node is Node3D:
			return (node as Node3D).global_position
		if name == "Door" and node != null:
			var nested: Node = node.get_node_or_null("InteractVolume")
			if nested is Node3D:
				return (nested as Node3D).global_position
	return root.global_position


static func _visual_id(root: Node) -> StringName:
	if root != null and "visual_id" in root:
		return root.get("visual_id") as StringName
	return &""


static func _candidate_bases(visual_id: StringName, anim: AnimationPlayer) -> PackedStringArray:
	## Prefer the authored id, then the season remapped mesh (`obj_s_*` → `obj_w_*`).
	var out: PackedStringArray = PackedStringArray()
	var id: String = String(visual_id)
	if not id.is_empty():
		_append_unique(out, id)
		if id.length() > 6 and id.begins_with("obj_") and id[4] == "_":
			var remapped: String = "obj_%s_%s" % [FieldCatalog.season_letter(), id.substr(6)]
			_append_unique(out, remapped)
		## Also accept whatever season letter the loaded AnimationPlayer actually has.
		for name: String in anim.get_animation_list():
			var leaf: String = name.get_file() if "/" in name else name
			if leaf.ends_with("_out"):
				leaf = leaf.substr(0, leaf.length() - 4)
			if leaf.begins_with("obj_") and leaf.length() > 6 and leaf.substr(6) == id.substr(6):
				_append_unique(out, leaf)
		return out
	for name: String in anim.get_animation_list():
		var leaf: String = name.get_file() if "/" in name else name
		if leaf.ends_with("_out"):
			leaf = leaf.substr(0, leaf.length() - 4)
		if leaf.begins_with("obj_"):
			_append_unique(out, leaf)
	return out


static func _append_unique(out: PackedStringArray, value: String) -> void:
	if value.is_empty():
		return
	for existing: String in out:
		if existing == value:
			return
	out.append(value)


static func _is_villager_house(base: String) -> bool:
	## `obj_s_house1` … not `obj_s_myhome1` / `obj_s_house_i`.
	var leaf: String = base.get_file() if "/" in base else base
	return leaf.contains("_house") and not leaf.contains("myhome") and not leaf.ends_with("_house_i")


static func _has_clip(anim: AnimationPlayer, suffix: String) -> bool:
	return not _resolve(anim, suffix).is_empty()


static func _resolve(anim: AnimationPlayer, suffix: String) -> String:
	if anim.has_animation(suffix):
		return suffix
	for anim_name: String in anim.get_animation_list():
		if anim_name == suffix or anim_name.ends_with("/" + suffix) or anim_name.ends_with(suffix):
			return anim_name
	return ""
