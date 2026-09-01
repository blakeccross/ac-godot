class_name BugActorVisual
extends Node3D

## Field insect model. Pose flips come from `BugActor.pose_index()` (`aINS _1E0`).

const PLACEHOLDER_COLOR := Color(0.85, 0.55, 0.2, 0.9)

var bug_id: StringName = &""

var _poses: Array[Node3D] = []
var _placeholder: MeshInstance3D = null
var _shown: int = -1
var _lift: float = 0.0
var _scale: float = 1.0


static func create(bug: BugData) -> BugActorVisual:
	var node := BugActorVisual.new()
	node._build(bug)
	return node


func _build(bug: BugData) -> void:
	_reset()
	if bug == null:
		_add_placeholder()
		return
	bug_id = bug.id
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
	## Same draw scale as fish / every field actor (`aINS_make_insect` → 0.01).
	_scale = FieldCatalog.actor_uniform_scale()
	if _poses.is_empty():
		_add_placeholder()
		return
	_lift = bug.model_lift * FieldCatalog.GX_TO_METERS
	_show(0)


func sync(actor: BugActor, _delta: float) -> void:
	visible = not actor.finished
	if not visible:
		return
	## `aINS_actor_draw_sub`: translate, RotateX/Y/Z, then `Matrix_scale(0.01)`. Same
	## `FieldCatalog.actor_uniform_scale()` fish/held catch use — write basis+scale in one
	## world transform so pitch-90 tree sits do not collapse through Euler gimbal lock.
	var origin := Vector3(
		actor.position.x, actor.position.y + actor.height - _lift, actor.position.z
	)
	var basis := (
		Basis.from_euler(Vector3(0.0, 0.0, actor.roll))
		* Basis.from_euler(Vector3(0.0, actor.yaw, 0.0))
		* Basis.from_euler(Vector3(actor.pitch, 0.0, 0.0))
	)
	global_transform = Transform3D(basis.scaled(Vector3.ONE * _scale), origin)
	_apply_alpha(actor.alpha)
	if _poses.size() <= 1:
		if _shown != 0:
			_show(0)
		return
	_show(actor.pose_index())


func _apply_alpha(amount: float) -> void:
	var fade: float = clampf(1.0 - amount, 0.0, 1.0)
	for node: Node in get_children():
		_set_transparency(node, fade)


func _set_transparency(node: Node, fade: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = fade
	for child: Node in node.get_children():
		_set_transparency(child, fade)


func _show(pose: int) -> void:
	if _poses.is_empty():
		if _placeholder != null:
			_placeholder.visible = true
		return
	var want: int = clampi(pose, 0, _poses.size() - 1)
	if want == _shown:
		return
	_shown = want
	for i: int in _poses.size():
		_poses[i].visible = i == want


func _add_placeholder() -> void:
	_placeholder = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.14
	_placeholder.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLACEHOLDER_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_placeholder.material_override = mat
	_placeholder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_placeholder)


func _reset() -> void:
	for child in get_children():
		child.queue_free()
	_poses.clear()
	_placeholder = null
	_shown = -1
	bug_id = &""
