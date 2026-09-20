class_name VisualMaterials
extends RefCounted
## Per-surface material pass for imported GLBs: hardening, vertex shade, and dispatch to the specialised material classes.


static func apply(node: Node, as_decal: bool = false, visual_id: StringName = &"") -> void:
	_apply_node(node, as_decal, VisualWaterMaterials.tree_has_splash_water(node), visual_id)


static func _apply_node(node: Node, as_decal: bool, mouth_river: bool, visual_id: StringName) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat == null:
				mat = StandardMaterial3D.new()
			if mat is StandardMaterial3D:
				var src := mat
				var kind: String = VisualWaterMaterials.water_kind(src)
				var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				std.texture_repeat = false
				std.cull_mode = BaseMaterial3D.CULL_DISABLED
				std.roughness = 1.0
				std.metallic = 0.0
				## glTF BLEND often imports as depth-prepass; that writes depth and
				## makes house XLU/window spill punch black holes through the door.
				if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
					std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				if is_vertex_shade_surface(mesh_instance, i, src):
					apply_vertex_shade_material(std)
				else:
					std.vertex_color_use_as_albedo = false
				if VisualWindowLight.is_window_spill_surface(mesh_instance, i, src):
					mesh_instance.set_surface_override_material(i, VisualWindowLight.make_window_spill_material(std))
				elif VisualWindowLight.is_window_pane_surface(mesh_instance, i, src):
					VisualWindowLight.apply_window_pane_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif VisualWindowLight.is_room_prim_fill_surface(mesh_instance, i, src):
					VisualWindowLight.apply_room_prim_fill_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif kind == "splash":
					mesh_instance.set_surface_override_material(i, VisualWaterMaterials.make_splash_water_material(std))
				elif kind == "river":
					mesh_instance.set_surface_override_material(
						i, VisualWaterMaterials.make_river_water_material(std, mouth_river)
					)
				elif kind == "ocean":
					mesh_instance.set_surface_override_material(
						i, VisualWaterMaterials.make_ocean_water_material(std, src)
					)
				elif kind == "waterfall":
					mesh_instance.set_surface_override_material(
						i, VisualWaterMaterials.make_waterfall_water_material(std, src, i)
					)
				elif VisualWaterMaterials.is_fall_rainbow_surface(mesh_instance, i, src):
					mesh_instance.set_surface_override_material(i, VisualWaterMaterials.make_fall_rainbow_material())
				elif kind == "beach_wet":
					mesh_instance.set_surface_override_material(
						i, VisualWaterMaterials.make_beach_wet_material(std, src)
					)
				elif VisualStructureMaterials.is_player_select_spot_surface(mesh_instance, i, src):
					VisualStructureMaterials.apply_player_select_spot_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif VisualStructureMaterials.is_player_select_shade_surface(mesh_instance, i, src):
					VisualStructureMaterials.apply_player_select_shade_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif VisualStructureMaterials.is_kanban_paper_surface(mesh_instance, i, src, visual_id):
					VisualStructureMaterials.apply_kanban_paper_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif VisualStructureMaterials.is_kanban_frame_surface(mesh_instance, i, src, visual_id):
					VisualStructureMaterials.apply_kanban_frame_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif VisualStructureMaterials.is_museum_art_surface(mesh_instance, i, src, visual_id):
					VisualStructureMaterials.apply_museum_art_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif VisualStructureMaterials.is_light_shaft_visual(visual_id):
					VisualStructureMaterials.apply_light_shaft_surface(std)
					mesh_instance.set_surface_override_material(i, std)
				elif VisualStructureMaterials.is_fish_tank_visual(visual_id):
					VisualStructureMaterials.apply_fish_tank_surface(std, VisualSurface.surface_label(mesh_instance, i, src))
					mesh_instance.set_surface_override_material(i, std)
				elif VisualStructureMaterials.is_single_sided_shell_visual(visual_id):
					std.cull_mode = BaseMaterial3D.CULL_BACK
					mesh_instance.set_surface_override_material(i, std)
				elif HostCollision.uses_structure_offset(visual_id):
					VisualStructureMaterials.apply_structure_surface(std)
					mesh_instance.set_surface_override_material(i, std)
				elif as_decal:
					std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
					std.render_priority = 1
					mesh_instance.set_surface_override_material(i, std)
				else:
					## ACHD soft TEX_EDGE often imports as BLEND (no depth write). River /
					## ocean screen-composite shaders draw later at render_priority 1 and
					## paint over face/ear cutouts (Maple cub `seg_08`/`seg_09`, etc.).
					## Intentional XLU already branched above — harden leftover cutouts.
					harden_imported_cutout(std)
					var field_role := FieldCatalog.season_role_for_surface(mesh_instance, i, src)
					if not field_role.is_empty():
						std.set_meta("field_role", field_role)
					mesh_instance.set_surface_override_material(i, std)
		if as_decal:
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh_instance.sorting_offset = 1.0
	for child in node.get_children():
		_apply_node(child, as_decal, mouth_river, visual_id)


static func harden_imported_cutout(std: StandardMaterial3D) -> void:
	## Match structure TEX_EDGE: scissor + depth write so transparent water cannot
	## overdraw ears/faces whose soft BLEND fringe left holes in the depth buffer.
	if std.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
		return
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	std.alpha_scissor_threshold = maxf(std.alpha_scissor_threshold, 0.5)
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY


static func _surface_has_vertex_colors(mesh_instance: MeshInstance3D, surface: int) -> bool:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null or surface < 0 or surface >= mesh.get_surface_count():
		return false
	var arrays: Array = mesh.surface_get_arrays(surface)
	if arrays.is_empty():
		return false
	return arrays[Mesh.ARRAY_COLOR] != null


static func is_vertex_shade_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	## Indoor shells: TEXEL0 × SHADE with G_LIGHTING off (ceiling AO in Vtx.cn[]).
	if bool(VisualSurface.gltf_extras(mat).get("vertex_shade", false)):
		return true
	return _surface_has_vertex_colors(mesh_instance, surface)


static func apply_vertex_shade_material(std: StandardMaterial3D) -> void:
	std.vertex_color_use_as_albedo = true
	## Original BG DLs skip LightsN; keep the baked shade band free of Godot lights.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
