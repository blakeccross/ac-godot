class_name DoorCamera
extends RefCounted

## `CAMERA2_PROCESS_DOOR` helpers — look at the door stand at Camera2 distance 620.


static func begin(look_at: Vector3, tree: SceneTree = null) -> void:
	var cam: Node = _camera(tree)
	if cam != null and cam.has_method("begin_door"):
		cam.call("begin_door", look_at)


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
