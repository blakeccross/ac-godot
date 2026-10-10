class_name BugActorVisual
extends Node3D

## Field insect model. Pose flips come from `BugActor.pose_index()` (`aINS _1E0`).

const PLACEHOLDER_COLOR := Color(0.85, 0.55, 0.2, 0.9)
## `ac_ant`: the swarm on food is its own patch (`act_antT_model`), not the insect model.
const SWARM_MODEL := "res://assets/generated/environment/act_ant.glb"
const SWARM_TEXTURE := "res://assets/generated/textures/rel/act_ant_tex.png"
const SWARM_SHADER := preload("res://shaders/ant_swarm.gdshader")

var bug_id: StringName = &""
## Drawn as the ant swarm (`BugActor.is_swarm`).
var swarm: bool = false

var _poses: Array[Node3D] = []
var _placeholder: MeshInstance3D = null
var _shown: int = -1
var _lift: float = 0.0
var _scale: float = 1.0
var _swarm_mat: ShaderMaterial = null
var _swarm_ticks: float = 0.0


static func create(bug: BugData, p_swarm: bool = false) -> BugActorVisual:
	var node := BugActorVisual.new()
	if p_swarm:
		node._build_swarm(bug)
	else:
		node._build(bug)
	return node


func _build_swarm(bug: BugData) -> void:
	_reset()
	swarm = true
	bug_id = bug.id if bug != null else &""
	_scale = FieldCatalog.actor_uniform_scale()
	var scene: PackedScene = load(SWARM_MODEL) as PackedScene if ResourceLoader.exists(SWARM_MODEL) else null
	if scene == null:
		_add_placeholder()
		return
	var visual: Node3D = scene.instantiate() as Node3D
	_swarm_mat = ShaderMaterial.new()
	_swarm_mat.shader = SWARM_SHADER
	if ResourceLoader.exists(SWARM_TEXTURE):
		_swarm_mat.set_shader_parameter(&"ants", load(SWARM_TEXTURE))
	_set_material(visual, _swarm_mat)
	add_child(visual)
	_poses.append(visual)
	_show(0)


func _set_material(node: Node, mat: Material) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = mat
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_set_material(child, mat)


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
	## `actor->drawn` — MINO / KERA / DANGO are hidden in the tree / ground until
	## the player shakes or digs.
	visible = actor.drawn and not actor.finished
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
	if _swarm_mat != null:
		## `act_ant_evw_anime` scrolls per tick; PRIM alpha carries the fade.
		_swarm_ticks = fmod(_swarm_ticks + _delta * DecompTime.TICK_HZ, 8192.0)
		_swarm_mat.set_shader_parameter(&"ticks", _swarm_ticks)
		_swarm_mat.set_shader_parameter(&"opacity", actor.alpha)
		return
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
	swarm = false
	_swarm_mat = null
