class_name PlayerSelectSpot
extends RefCounted
## Scrolling spotlight on the K.K. opening acre. Native grain + cone; the baked cone stays
## the fallback when those tiles have not been generated.


const SHADER := preload("res://shaders/player_select_spot.gdshader")
const GRAIN_PATH := "res://assets/generated/environment/player_select/rom_open_spot2.png"
const CONE_PATH := "res://assets/generated/environment/player_select/rom_open_spot.png"
## `gsDPSetEnvColor` (255, 255, 130). Prim is white.
const ENV_COLOR := Color(1.0, 1.0, 130.0 / 255.0)
## `gsDPSetPrimColor` lod level, stored in emu64 TEVREG0 alpha.
const LOD_FRAC := 150.0 / 255.0
## The sheet reads heavier here than in the 8-bit framebuffer blend. Scale it down.
const BEAM_OPACITY := 1.0


static func apply(root: Node) -> void:
	if root == null or not _tiles_ready():
		return
	_apply_node(root)


static func material_for(std: StandardMaterial3D) -> Material:
	if not _tiles_ready():
		VisualStructureMaterials.apply_player_select_spot_material(std)
		return std
	return _shader_material(std)


static func _tiles_ready() -> bool:
	return ResourceLoader.exists(GRAIN_PATH) and ResourceLoader.exists(CONE_PATH)


static func _apply_node(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count := 0
		if mesh_instance.mesh != null:
			surface_count = mesh_instance.mesh.get_surface_count()
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader == SHADER:
				continue
			if not (mat is StandardMaterial3D):
				continue
			if not VisualStructureMaterials.is_player_select_spot_surface(mesh_instance, i, mat):
				continue
			mesh_instance.set_surface_override_material(i, _shader_material(mat as StandardMaterial3D))
	for child: Node in node.get_children():
		_apply_node(child)


static func _shader_material(std: StandardMaterial3D) -> ShaderMaterial:
	var spot := ShaderMaterial.new()
	spot.shader = SHADER
	spot.resource_name = std.resource_name
	spot.set_shader_parameter("grain_tex", load(GRAIN_PATH))
	spot.set_shader_parameter("cone_tex", load(CONE_PATH))
	spot.set_shader_parameter("wrap_tiles", _wrap_tiles(std))
	spot.set_shader_parameter("game_fps", DecompTime.TICK_HZ)
	spot.set_shader_parameter("env_color", ENV_COLOR)
	spot.set_shader_parameter("lod_frac", LOD_FRAC)
	spot.set_shader_parameter("beam_opacity", BEAM_OPACITY)
	return spot


static func _wrap_tiles(mat: Material) -> Vector2:
	var raw: Variant = VisualSurface.gltf_extras(mat).get("wrap_tiles", null)
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2(2.0, 1.0)
