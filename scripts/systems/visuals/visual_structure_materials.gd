class_name VisualStructureMaterials
extends RefCounted
## Material rules for structures and fixtures: fish tanks, kanban boards, museum art, player-select spot/shade.

const _TANK_GLASS := preload("res://shaders/tank_glass.gdshader")
const _TANK_CAUSTIC := preload("res://shaders/tank_caustic.gdshader")
const _TANK_WATER := preload("res://shaders/tank_water.gdshader")


static func is_single_sided_shell_visual(visual_id: StringName) -> bool:
	## `ac_mailbox`: `inside1_tex` is the exact same wall quad as `side1_tex`, authored
	## with reversed winding (verified against the ROM's own vertex data) — GX fakes
	## "visible from both sides" with two coincident single-sided polys, not blending.
	## The pipeline's blanket `doubleSided: true` (`glb.py::_material`, needed for most
	## structures) draws both at once here and z-fights; force single-sided back-cull so
	## only the poly actually facing the camera renders, matching the original GX result.
	return visual_id == &"obj_s_post" or visual_id == &"obj_w_post"


static func is_fish_tank_visual(visual_id: StringName) -> bool:
	## Small tanks + sea tank: OPA shell, TEX_EDGE frame, XLU glass/water.
	return visual_id == &"obj_suisou1" or visual_id == &"obj_museum5"


static func apply_fish_tank_surface(
	std: StandardMaterial3D, label: String = "", src: Material = null, visual_id: StringName = &""
) -> Material:
	## Wall quads are single-sided; default CULL_DISABLED draws both faces on the same
	## plane and flickers. Frame (MASK) writes depth; XLU depth-tests without writing
	## so front/evw can share the wall plane without a mesh-scale inset (that shrank water).
	std.cull_mode = BaseMaterial3D.CULL_BACK
	if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		std.alpha_scissor_threshold = maxf(std.alpha_scissor_threshold, 0.5)
		std.render_priority = 0
		return std
	if std.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
		return std
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.render_priority = 1
	var extras: Dictionary = VisualSurface.gltf_extras(src if src != null else std)
	var wrap := _wrap_tiles(extras)
	## `modelT`: highlight, then the water-surface tint, then the scrolling caustic.
	if "evw" in label:
		return _tank_glass(std, wrap, visual_id == &"obj_museum5")
	if "mizu" in label:
		return _tank_water(std)
	if "water1" in label or "water2" in label or "rgb_i4" in label or _is_tank_caustic(extras):
		return _tank_caustic(std)
	return std


static func _wrap_tiles(extras: Dictionary) -> Vector2:
	var raw: Variant = extras.get("wrap_tiles", null)
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	return Vector2.ONE


static func _tank_glass(std: StandardMaterial3D, wrap: Vector2, sea: bool) -> ShaderMaterial:
	## Small tanks are a faint blue; the sea tank is stronger. Tint (0, 30, 120).
	var mat := ShaderMaterial.new()
	mat.shader = _TANK_GLASS
	mat.set_shader_parameter("albedo_tex", std.albedo_texture)
	mat.set_shader_parameter("tint", Vector3(0.0, 30.0 / 255.0, 120.0 / 255.0))
	mat.set_shader_parameter("base_alpha", (60.0 if sea else 30.0) / 255.0)
	mat.set_shader_parameter("texture_alpha", (20.0 if sea else 10.0) / 256.0)
	mat.set_shader_parameter("wrap_tiles", wrap)
	mat.render_priority = 1
	mat.set_meta("tank_layer", &"evw")
	return mat


static func _tank_water(std: StandardMaterial3D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _TANK_WATER
	mat.set_shader_parameter("albedo_tex", std.albedo_texture)
	mat.render_priority = 2
	mat.set_meta("tank_layer", &"mizu")
	return mat


static func _is_tank_caustic(extras: Dictionary) -> bool:
	return str(extras.get("water_kind", "")) == "tank_caustic"


static func _tank_caustic(std: StandardMaterial3D) -> ShaderMaterial:
	## Tile 0 is the albedo. Tile 1 rides the glTF occlusion slot, same as rivers.
	var water1: Texture2D = std.albedo_texture
	var water2: Texture2D = std.ao_texture if std.ao_texture != null else std.emission_texture
	if water2 == null:
		water2 = water1
	var mat := ShaderMaterial.new()
	mat.shader = _TANK_CAUSTIC
	mat.set_shader_parameter("water1", water1)
	mat.set_shader_parameter("water2", water2)
	mat.render_priority = 3
	mat.set_meta("tank_layer", &"caustic")
	return mat


static func apply_structure_surface(std: StandardMaterial3D) -> void:
	## Keep CULL_DISABLED on OPAQUE walls — many facade normals face inward after
	## bind, so back-face cull hides the shell and leaves black window panes.
	if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		## Door/fence share the OPA facade plane (same as GC). Do not move verts —
		## `grow` biases depth along the normal so MASK wins the depth test without
		## a visible gap (GC used POLY_OPA + TEX_EDGE alpha-test + joint draw order).
		std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		std.alpha_scissor_threshold = maxf(std.alpha_scissor_threshold, 0.5)
		std.grow = true
		std.grow_amount = 0.002
		std.render_priority = 1
	elif std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
		std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		std.render_priority = 1


static func _is_kanban_visual(visual_id: StringName) -> bool:
	## Two-layer field signs only (`write_model` + frame). Dock `PORT_SIGN` uses attention.
	return visual_id in [&"SIGNBOARD", &"obj_s_kanban", &"obj_w_kanban"]


static func _is_museum_art_visual(visual_id: StringName) -> bool:
	var s := String(visual_id)
	return s.begins_with("obj_art")


static func is_museum_art_surface(
	_mesh_instance: MeshInstance3D, _surface: int, _mat: Material, visual_id: StringName
) -> bool:
	return _is_museum_art_visual(visual_id)


static func apply_museum_art_material(std: StandardMaterial3D) -> void:
	## `aMP_DrawOneArt` draws on POLY_OPA (`G_RM_AA_ZB_OPA_SURF2`). Alpha mode is pipeline-owned.
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY


static func is_kanban_paper_surface(
	mesh_instance: MeshInstance3D, surface: int, mat: Material, visual_id: StringName
) -> bool:
	if not _is_kanban_visual(visual_id):
		return false
	if not (mat is StandardMaterial3D):
		return false
	var label := VisualSurface.surface_label(mesh_instance, surface, mat)
	return (
		"my_original" in label
		or "hakushi" in label
		or (mat as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
		and "kanban_base" not in label
		and surface == 0
	)


static func is_kanban_frame_surface(
	mesh_instance: MeshInstance3D, surface: int, mat: Material, visual_id: StringName
) -> bool:
	if not _is_kanban_visual(visual_id):
		return false
	if not (mat is StandardMaterial3D):
		return false
	var label := VisualSurface.surface_label(mesh_instance, surface, mat)
	return "kanban_base" in label or surface == 1


static func apply_kanban_paper_material(std: StandardMaterial3D) -> void:
	## `write_model` draws first as a decal (`G_DECAL_LEQUAL`); do not win depth over the frame.
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.render_priority = 0


static func apply_kanban_frame_material(std: StandardMaterial3D) -> void:
	## `obj_sign_{s,w}_model` masks wood over the paper (`G_RM_AA_ZB_TEX_EDGE2`).
	std.render_priority = 1
	if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		std.alpha_scissor_threshold = maxf(std.alpha_scissor_threshold, 0.5)


static func is_player_select_spot_surface(
	mesh_instance: MeshInstance3D, surface: int, mat: Material
) -> bool:
	return "rom_open_spot" in VisualSurface.surface_label(mesh_instance, surface, mat).to_lower()


static func is_player_select_shade_surface(
	mesh_instance: MeshInstance3D, surface: int, mat: Material
) -> bool:
	return "rom_open_shade" in VisualSurface.surface_label(mesh_instance, surface, mat).to_lower()


static func apply_player_select_spot_material(std: StandardMaterial3D) -> void:
	## Fallback when the native grain/cone tiles are missing. The scrolling beam is
	## `player_select_spot.gdshader` (`PlayerSelectSpot`).
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.vertex_color_use_as_albedo = false
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	## Soft alpha on a floor quad. Linear-without-mips stair-steps the fade.
	std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	std.texture_repeat = false
	std.set_meta("player_select_spot", true)


static func apply_player_select_shade_material(std: StandardMaterial3D) -> void:
	## Shade curtain: black prim × I alpha. Wrap-baked like the spot.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.vertex_color_use_as_albedo = false
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	std.texture_repeat = false
	std.set_meta("player_select_shade", true)
