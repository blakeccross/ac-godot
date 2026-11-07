class_name VisualFlameMaterial
extends RefCounted

## The fireplace flame (`water_kind` `flame`, stamped from the combiner: colour `(PRIM - ENV) * I0 + ENV`,
## alpha `I1 * PRIM_LOD_FRAC` over two scrolling I4 tiles). Tile 0 is the albedo; tile 1 rides the
## occlusion slot as the rivers' does. PRIM, ENV and the LOD fraction come from the display list.

const SHADER := preload("res://shaders/furniture_flame.gdshader")


static func make(std: StandardMaterial3D, src: Material) -> ShaderMaterial:
	var extras: Dictionary = VisualSurface.gltf_extras(src)
	var tile0: Texture2D = std.albedo_texture
	var tile1: Texture2D = std.ao_texture if std.ao_texture != null else tile0
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("tile0", tile0)
	mat.set_shader_parameter("tile1", tile1)
	var prim: Array = extras.get("beach_prim", [255, 255, 255, 255]) as Array
	var env: Array = extras.get("flame_env", [255, 255, 255, 255]) as Array
	mat.set_shader_parameter("prim_color", Color8(int(prim[0]), int(prim[1]), int(prim[2])))
	mat.set_shader_parameter("env_color", Color8(int(env[0]), int(env[1]), int(env[2])))
	mat.set_shader_parameter("lod_frac", float(extras.get("flame_lod", 255)) / 255.0)
	## Over the body it stands in front of.
	mat.render_priority = 2
	return mat
