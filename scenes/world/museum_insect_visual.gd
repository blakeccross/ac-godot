class_name MuseumInsectVisual
extends Node3D

## Museum insect mesh. Pose flips come from `MuseumInsectActor.pose_index()`.

var actor: MuseumInsectActor = null

var _poses: Array[Node3D] = []
var _shown: int = -1
var _scale: float = 1.0
var _lift: float = 0.0


static func create(p_actor: MuseumInsectActor) -> MuseumInsectVisual:
	if p_actor == null or p_actor.bug == null:
		return null
	var node := MuseumInsectVisual.new()
	node.actor = p_actor
	node._build(p_actor.bug)
	node._scale = p_actor.render_scale()
	return node


func _build(bug: BugData) -> void:
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
	_lift = bug.model_lift * FieldCatalog.GX_TO_METERS
	if _poses.is_empty():
		var placeholder := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.08
		mesh.height = 0.16
		placeholder.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.55, 0.2)
		placeholder.material_override = mat
		add_child(placeholder)
		return
	_show(0)


func _process(delta: float) -> void:
	if actor == null:
		return
	actor.tick(delta)
	var origin := Vector3(actor.position.x, actor.position.y + actor.height - _lift, actor.position.z)
	var basis := Basis.from_euler(Vector3(actor.pitch, actor.yaw, 0.0)).scaled(Vector3.ONE * _scale)
	global_transform = Transform3D(basis, origin)
	if _poses.size() > 1:
		_show(actor.pose_index())


func _show(pose: int) -> void:
	if _poses.is_empty():
		return
	var want: int = clampi(pose, 0, _poses.size() - 1)
	if want == _shown:
		return
	_shown = want
	for i: int in _poses.size():
		_poses[i].visible = i == want
