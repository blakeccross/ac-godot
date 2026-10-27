class_name FieldLit
extends RefCounted

## Swap shaded `StandardMaterial3D` surfaces for `field_lit.gdshader`.
## Unshaded vertex-colour shells stay as they are.


const SHADER := preload("res://shaders/field_lit.gdshader")
const OPAQUE_SHADER := preload("res://shaders/field_lit_opaque.gdshader")


static func apply(root: Node) -> void:
	if root == null:
		return
	_apply_node(root, false)


## Solid shells (the wishing well). Cutout leaves still scissor; everything else stays
## in the opaque pass so the trunk cannot draw over the player.
static func apply_solid(root: Node) -> void:
	if root == null:
		return
	_apply_node(root, true)


static func _apply_node(node: Node, solid: bool) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count := 0
		if mesh_instance.mesh != null:
			surface_count = mesh_instance.mesh.get_surface_count()
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_active_material(i)
			if not (mat is StandardMaterial3D):
				continue
			var std := mat as StandardMaterial3D
			if std.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				continue
			mesh_instance.set_surface_override_material(i, from_standard(std, solid))
	for child: Node in node.get_children():
		_apply_node(child, solid)


static func from_standard(std: StandardMaterial3D, solid: bool = false) -> ShaderMaterial:
	var lit := ShaderMaterial.new()
	var cutout := std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	lit.shader = OPAQUE_SHADER if solid and not cutout else SHADER
	lit.resource_name = std.resource_name
	lit.set_shader_parameter("albedo_tex", std.albedo_texture)
	if lit.shader == SHADER:
		var threshold := 0.0
		if cutout:
			threshold = std.alpha_scissor_threshold
		lit.set_shader_parameter("alpha_scissor_threshold", threshold)
	return lit
