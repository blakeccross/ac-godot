extends Node3D

## FG waterfall (`obj_fallS` / `obj_fallSE`). Visual-only; sits on the river cliff sheet.
##
## `ac_fallS_draw.c_inc` also draws `obj_fall*_rainbowT_model` while `Game.rainbow` is
## showing: at its opacity, turned about the waterfall's origin so the arc's +Z face
## points at the camera (`Math3DVectorProduct2Vec` + `Matrix_RotateVector`), with the
## model's own axes (the actor's rotation is not applied to it).

@export var visual_id: StringName = &"obj_fallS"

const RAINBOW_SHADER := preload("res://shaders/fall_rainbow.gdshader")
const RAINBOW_COLOR := "res://assets/generated/effects/obj_fall_rainbow_color.png"
const RAINBOW_MASK := "res://assets/generated/effects/obj_fall_rainbow_mask.png"

var _rainbow: MeshInstance3D = null
var _rainbow_local := Transform3D.IDENTITY
var _rainbow_mat: ShaderMaterial = null


func _ready() -> void:
	GeneratedVisual.attach(self, visual_id)
	_build_rainbow()


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)
	_build_rainbow()


## Lift the rainbow surface (left invisible by `VisualMaterials`) into its own instance.
func _build_rainbow() -> void:
	if _rainbow != null:
		_rainbow.queue_free()
		_rainbow = null
	var found := _find_rainbow(self)
	if found.is_empty():
		set_process(false)
		return
	var mi: MeshInstance3D = found["mesh"]
	var surface: int = found["surface"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(surface))
	_rainbow_mat = ShaderMaterial.new()
	_rainbow_mat.shader = RAINBOW_SHADER
	for pair: Array in [["color_tex", RAINBOW_COLOR], ["mask_tex", RAINBOW_MASK]]:
		if ResourceLoader.exists(str(pair[1])):
			_rainbow_mat.set_shader_parameter(str(pair[0]), load(str(pair[1])))
	mesh.surface_set_material(0, _rainbow_mat)
	_rainbow = MeshInstance3D.new()
	_rainbow.name = "Rainbow"
	_rainbow.mesh = mesh
	_rainbow.top_level = true
	_rainbow.visible = false
	add_child(_rainbow)
	## The mesh's placement under this node, minus this node's own rotation.
	_rainbow_local = global_transform.affine_inverse() * mi.global_transform
	_rainbow_local = Transform3D(Basis.from_scale(global_transform.basis.get_scale()), Vector3.ZERO) * _rainbow_local
	set_process(true)


static func _find_rainbow(node: Node) -> Dictionary:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i: int in mi.mesh.get_surface_count():
				var mat := mi.get_surface_override_material(i)
				if mat != null and mat.has_meta("fall_rainbow"):
					return {"mesh": mi, "surface": i}
	for child: Node in node.get_children():
		var hit := _find_rainbow(child)
		if not hit.is_empty():
			return hit
	return {}


func _process(_delta: float) -> void:
	if _rainbow == null or Game == null or Game.rainbow == null:
		return
	var opacity: float = Game.rainbow.opacity
	_rainbow.visible = opacity > 0.0
	if not _rainbow.visible:
		return
	_rainbow_mat.set_shader_parameter("opacity", minf(opacity * 256.0 / 255.0, 1.0))
	var cam := get_viewport().get_camera_3d()
	var turn := Basis.IDENTITY
	if cam != null:
		var bboard: Vector3 = cam.global_basis.z
		var axis: Vector3 = Vector3.BACK.cross(bboard)
		if axis.length() >= 0.0000001:
			turn = Basis(axis.normalized(), acos(clampf(Vector3.BACK.dot(bboard), -1.0, 1.0)))
	_rainbow.global_transform = Transform3D(turn, global_position) * _rainbow_local
