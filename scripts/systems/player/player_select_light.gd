class_name PlayerSelectLight
extends RefCounted
## N·L shade for the K.K. opening (`G_LIGHTING` on `end_1`). The acre stays vertex-colored.


const SHADER := preload("res://shaders/player_select_ndotl.gdshader")


static func apply(root: Node) -> void:
	if root == null:
		return
	_apply_node(root)


static func _apply_node(node: Node) -> void:
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
			var lit := _from_standard(std)
			mesh_instance.set_surface_override_material(i, lit)
	for child: Node in node.get_children():
		_apply_node(child)


static func _from_standard(std: StandardMaterial3D) -> ShaderMaterial:
	var lit := ShaderMaterial.new()
	lit.shader = SHADER
	lit.resource_name = std.resource_name
	lit.set_shader_parameter("albedo_tex", std.albedo_texture)
	lit.set_shader_parameter("ambient_color", IntroKkStage.AMBIENT_COLOR)
	lit.set_shader_parameter("sun_color", IntroKkStage.SUN_COLOR)
	lit.set_shader_parameter("sun_direction", IntroKkStage.CHARACTER_SUN_DIR)
	var threshold := 0.0
	if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		threshold = std.alpha_scissor_threshold
	lit.set_shader_parameter("alpha_scissor_threshold", threshold)
	return lit
