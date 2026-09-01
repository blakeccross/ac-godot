class_name HeldBug
extends Node3D

## Caught bug held up on the show-off pose. Mirrors `HeldFish` for insects.

const FLAP_HZ := BugData.POSE_FLAP_HZ

var _poses: Array[Node3D] = []
var _pattern: Array[int] = []
var _shown: int = -1
var _tick: float = 0.0
var _index: int = 0
var _scale: float = 1.0
var _lift: float = 0.0


static func create(bug: BugData) -> HeldBug:
	if bug == null or bug.model_base.is_empty():
		return null
	var node := HeldBug.new()
	node.name = "HeldBug"
	if not node._load(bug):
		node.free()
		return null
	return node


func _load(bug: BugData) -> bool:
	for pose: StringName in [&"a", &"b"]:
		var path: String = bug.model_pose(pose)
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			continue
		var visual: Node3D = scene.instantiate() as Node3D
		if visual == null:
			continue
		GeneratedVisual.apply_preview_materials(visual)
		visual.visible = false
		add_child(visual)
		_poses.append(visual)
	if _poses.is_empty():
		return false
	_pattern = BugData.pose_pattern(bug.model_flap)
	_lift = bug.model_lift * FieldCatalog.GX_TO_METERS
	_scale = FieldCatalog.actor_uniform_scale()
	position = Vector3(0.0, -_lift, 0.0)
	scale = Vector3.ONE * _scale
	_show(0)
	return true


func _ready() -> void:
	var hand: Node3D = get_parent_node_3d()
	var rig: float = hand.global_transform.basis.get_scale().y if hand != null else 1.0
	if rig > 0.0:
		scale = Vector3.ONE * (_scale / rig)
	_billboard()


func _process(delta: float) -> void:
	_billboard()
	if _pattern.size() <= 1:
		return
	_tick += delta
	var step: float = 1.0 / FLAP_HZ
	while _tick >= step:
		_tick -= step
		_index = (_index + 1) % _pattern.size()
		_show(_pattern[_index])


func shown_pose() -> int:
	return _shown


func _show(pose: int) -> void:
	var want: int = clampi(pose, 0, _poses.size() - 1)
	if want == _shown:
		return
	_shown = want
	for i: int in _poses.size():
		_poses[i].visible = i == want


func _billboard() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	var hand: Node3D = get_parent_node_3d()
	var origin: Vector3 = (
		hand.global_position - Vector3(0.0, _lift, 0.0) if hand != null else global_position
	)
	var to_camera: Vector3 = camera.global_position - origin
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.000001:
		return
	var yaw: float = atan2(to_camera.x, to_camera.z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * _scale), origin)
