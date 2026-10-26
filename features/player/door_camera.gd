class_name DoorCamera
extends RefCounted

## `CAMERA2_PROCESS_DOOR` helpers: frame the player's eye from 350 GX at 20.3°.


## `morph` for going in (`flags & 1`, 140 ticks); coming out snaps.
static func begin(center: Vector3, tree: SceneTree = null, morph: bool = true) -> void:
	var cam: Node = _camera(tree)
	if cam != null and cam.has_method("begin_door"):
		cam.call("begin_door", center, morph)


static func end(tree: SceneTree = null) -> void:
	var cam: Node = _camera(tree)
	if cam != null and cam.has_method("end_door"):
		cam.call("end_door")


static func _camera(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var cams: Array[Node] = tree.get_nodes_in_group("follow_camera")
	if not cams.is_empty():
		return cams[0]
	return tree.get_first_node_in_group("follow_camera")
