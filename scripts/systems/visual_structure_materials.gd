class_name VisualStructureMaterials
extends RefCounted
## Material rules for structures and fixtures: light shafts, fish tanks, kanban boards, museum art, player-select spot/shade.


static func is_light_shaft_visual(visual_id: StringName) -> bool:
	## Museum skylight god-rays (`obj_museum1_shine` / `obj_museum4_shine`).
	var s := String(visual_id)
	return s.begins_with("obj_museum") and s.ends_with("_shine")


## Soft translucent light cone: unshaded, additive-ish MIX, no depth write, daylight-gated.
static func apply_light_shaft_surface(std: StandardMaterial3D) -> void:
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.cull_mode = BaseMaterial3D.CULL_DISABLED
	std.render_priority = 2
	std.vertex_color_use_as_albedo = false
	std.emission_enabled = true
	std.emission = Color(1.0, 0.96, 0.86)
	std.emission_energy_multiplier = 0.6
	var day: float = _daylight_fraction()
	std.albedo_color = Color(1.0, 0.97, 0.88, lerp(0.05, 0.32, day))


## 0 at night, ~1 at midday — from the clock's outdoor light term when available.
static func _daylight_fraction() -> float:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var clock: Node = (loop as SceneTree).root.get_node_or_null("Clock")
		if clock != null and clock.has_method("time_of_day"):
			match int(clock.call("time_of_day")):
				2:
					return 1.0 # DAY
				1, 3:
					return 0.5 # DAWN / DUSK
				_:
					return 0.12 # NIGHT
	return 0.6


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


static func apply_fish_tank_surface(std: StandardMaterial3D, label: String = "") -> void:
	## Wall quads are single-sided; default CULL_DISABLED draws both faces on the same
	## plane and flickers. Frame (MASK) writes depth; XLU depth-tests without writing
	## so front/evw can share the wall plane without a mesh-scale inset (that shrank water).
	std.cull_mode = BaseMaterial3D.CULL_BACK
	if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		std.alpha_scissor_threshold = maxf(std.alpha_scissor_threshold, 0.5)
		std.render_priority = 0
	elif std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
		std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		std.render_priority = 1
		## `evw` / `water1` / `water2` are the animated shimmer + caustics layers.
		## On GC they draw at ~12% (`SetPrimColor` a=30) with TEXTURE_GEN reflection
		## and a dual-scroll; the static bake keeps the raw texture alpha, so the
		## diagonal I4/CI4 pattern reads as a hard hatch over the glass. Force them
		## back to a faint blue wash — the shimmer is a GC-only runtime effect.
		if "evw" in label or "water1" in label or "water2" in label or "rgb_i4" in label:
			std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			std.albedo_color = Color(0.36, 0.62, 0.85, 0.12)
			std.albedo_texture = null
			std.render_priority = 2


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
	## Baked yellow cone XLU (`grd_player_select_modelT`). GC uses RDP combine + EVW
	## scroll on spot2 — not a programmable shader; keep the imported bake.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.vertex_color_use_as_albedo = false
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	std.texture_repeat = false
	std.set_meta("player_select_spot", true)


static func apply_player_select_shade_material(std: StandardMaterial3D) -> void:
	## Shade curtain: black prim × I alpha. Wrap-baked like the spot.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.vertex_color_use_as_albedo = false
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	std.texture_repeat = false
	std.set_meta("player_select_shade", true)
