class_name VisualSeasons
extends RefCounted
## Season albedo swaps (grass, leaves, trunks, wet sand) for non-acre visuals. Field acres are baked scenes and use `Acre.apply_season`.


static func apply(node: Node) -> void:
	## Replace grass/earth/leaf/trunk albedos from `environment/seasons/{s,f,w}/`.
	## Acre GLBs bake wrap into the PNG; re-tile the season tile to the current atlas size.
	if node == null:
		return
	_apply_node(node)


static func _apply_node(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat == null:
				continue
			if mat is ShaderMaterial:
				if _apply_wet_sand(mesh_instance, i, mat as ShaderMaterial):
					continue
				## River/ocean/splash shaders keep their own scrolling samplers.
				continue
			var role := FieldCatalog.season_role_for_surface(mesh_instance, i, mat)
			if role.is_empty():
				continue
			var path := FieldCatalog.season_texture_path(role)
			if path.is_empty():
				continue
			var season_tex: Texture2D = load(path) as Texture2D
			if season_tex == null:
				continue
			var std: StandardMaterial3D
			if mat is StandardMaterial3D:
				std = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				std = StandardMaterial3D.new()
			var target: Vector2i = VisualAtlas.albedo_size(std)
			var clamp_v := FieldCatalog.season_tile_clamp_v(role)
			## Wrap-bake cell size from the atlas period (32 native / 128 capped ACHD).
			## Season HD into a stale native 512² atlas must resize to 32 — using the
			## 128 season sheet as the cell yields 4×4 tiles and 4× oversized grass.
			var cell := 0
			if target != Vector2i.ZERO and std.albedo_texture != null:
				cell = VisualAtlas.infer_tile_size(std.albedo_texture, 0)
			std.albedo_texture = (
				VisualAtlas.tile_to_atlas(season_tex, target, false, clamp_v, cell)
				if target != Vector2i.ZERO
				else season_tex
			)
			std.albedo_color = Color.WHITE
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.texture_repeat = false
			if mat is StandardMaterial3D:
				var src_std := mat as StandardMaterial3D
				std.transparency = src_std.transparency
				std.alpha_scissor_threshold = src_std.alpha_scissor_threshold
				std.alpha_antialiasing_mode = src_std.alpha_antialiasing_mode
				std.cull_mode = src_std.cull_mode
			mesh_instance.set_surface_override_material(i, std)
	for child in node.get_children():
		_apply_node(child)


static func _apply_wet_sand(
	mesh_instance: MeshInstance3D, surface: int, mat: ShaderMaterial
) -> bool:
	## Shore wet-sand band (`beach1` I4). Ocean-bed `beachB` stays on the blue underdraw.
	if not mat.has_meta("beach_wet"):
		return false
	var role := FieldCatalog.season_role_for_surface(mesh_instance, surface, mat)
	if role != "beach_wet":
		return false
	var path := FieldCatalog.season_texture_path(role)
	if path.is_empty():
		return false
	var season_tex: Texture2D = load(path) as Texture2D
	if season_tex == null:
		return false
	var sh := mat.duplicate() as ShaderMaterial
	var current: Variant = sh.get_shader_parameter("albedo_texture")
	var target := Vector2i.ZERO
	if current is Texture2D:
		var cur_tex := current as Texture2D
		target = Vector2i(cur_tex.get_width(), cur_tex.get_height())
	var tiled: Texture2D = (
		VisualAtlas.tile_to_atlas(season_tex, target, false, true) if target != Vector2i.ZERO else season_tex
	)
	sh.set_shader_parameter("albedo_texture", tiled)
	mesh_instance.set_surface_override_material(surface, sh)
	return true
