class_name VisualCloth
extends RefCounted
## Shirt / design / item albedo painting onto actor and furniture surfaces.


static func apply_item_albedo(host: Node, item_id: StringName) -> void:
	var path: String = FieldCatalog.item_albedo(item_id)
	if path.is_empty() or host == null:
		return
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return
	paint_albedo(host, tex)


static func apply_cloth(host: Node, cloth_index: int) -> void:
	## Mannequin shirt samples `anime_1_txt` (seg 8). Stand keeps baked CI textures.
	var path: String = FieldCatalog.cloth_albedo(cloth_index)
	if path.is_empty() or host == null:
		return
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return
	_paint_cloth(host, tex)


## Paint a custom original design (32x32, `DesignTexture.build`) onto a shirt /
## mannequin / umbrella mesh. Decomp binds the CI4 texture + preset palette to the
## `ANIME_1/2_TXT_SEG` slots (`ac_needlework_indoor.c`, `m_player_lib.c:1060`).
static func apply_design(host: Node, tex: Texture2D) -> void:
	if host == null or tex == null:
		return
	_paint_cloth(host, tex)


## Force `tex` as the albedo of every surface whose name/material contains one of
## `name_parts` (case-insensitive). Used for the umbrella-stand canopy, whose mesh
## has no cloth-labelled surface (`obj_shop_umbmy` isn't converted yet).
static func paint_surface_albedo(node: Node, tex: Texture2D, name_parts: PackedStringArray) -> void:
	if node == null or tex == null:
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
		for i in count:
			var label := VisualSurface.surface_label(mi, i, mi.get_active_material(i))
			var hit := false
			for part in name_parts:
				if label.contains(part.to_lower()):
					hit = true
					break
			if not hit:
				continue
			var std := StandardMaterial3D.new()
			std.albedo_texture = tex
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			std.roughness = 1.0
			## `ac_needlework_indoor.c` draws these with `G_LIGHTING` — the flat design
			## texture is modulated by the model's per-vertex shade, so the curved
			## stand/canopy picks up the room light unevenly ("shirt shadows").
			std.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			mi.set_surface_override_material(i, std)
	for child in node.get_children():
		paint_surface_albedo(child, tex, name_parts)


static func paint_albedo(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 1.0
		mat.metallic = 0.0
		mesh_instance.set_surface_override_material(0, mat)
	for child in node.get_children():
		paint_albedo(child, tex)


static func _paint_cloth(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var src: Material = mesh_instance.get_active_material(i)
			if not is_cloth_surface(mesh_instance, i, src):
				continue
			var std: StandardMaterial3D
			if src is StandardMaterial3D:
				std = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				std = StandardMaterial3D.new()
			var span: Vector2 = _surface_uv_max(mesh_instance.mesh, i)
			var tiles_u: int = _repeat_tiles(span.x)
			var tiles_v: int = _repeat_tiles(span.y)
			var atlas: Vector2i = VisualAtlas.albedo_size(std)
			## Wrap-baked player / villager shirts remap UVs to 0–1 on a packed atlas of
			## N×M copies of the 32² tile. Tile the (HD) bank shirt the same N×M so the
			## design repeats around the torso as on hardware; squashing one copy into
			## the native-size atlas stretched it and threw the HD detail away.
			## Mannequins keep U≤2 and tile by UV span below.
			if atlas.x > 0 and atlas.y > 0 and tiles_u <= 1 and tiles_v <= 1:
				var grid := _wrap_tile_grid(mesh_instance, i, src, atlas)
				std.albedo_texture = _tiled_albedo(tex, grid.x, grid.y)
				std.uv1_scale = Vector3.ONE
			else:
				std.albedo_texture = _tiled_albedo(tex, tiles_u, tiles_v)
				std.uv1_scale = Vector3(1.0 / float(tiles_u), 1.0 / float(tiles_v), 1.0)
			std.albedo_color = Color.WHITE
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			## Shirt DLs are wrapS=REPEAT / wrapT=CLAMP with U up to 2. Tile the PNG
			## and keep clamp — Godot has one texture_repeat flag for both axes.
			std.texture_repeat = false
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			std.roughness = 1.0
			std.metallic = 0.0
			## `_texture_z_light_fog_prim` draws the manekin / umbrella with `G_LIGHTING`
			## on and the design as a modulating texture — the flat pattern takes the
			## room light unevenly over the curved form (the "shirt shadows").
			std.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			std.vertex_color_use_as_albedo = false
			mesh_instance.set_surface_override_material(i, std)
	for child in node.get_children():
		_paint_cloth(child, tex)


static func _wrap_tile_grid(
	mesh_instance: MeshInstance3D, surface: int, active: Material, atlas: Vector2i
) -> Vector2i:
	## Tiles the pipeline baked into this surface's atlas: the `wrap_tiles` stamp when the
	## GLB has it, else the atlas split into square cells of its gcd (native tiles are
	## square, so 96×32 → 3×1, 96×64 → 3×2).
	if mesh_instance.mesh != null:
		var baked: Vector2i = FieldCatalog.wrap_tiles_from_extras(mesh_instance.mesh.surface_get_material(surface))
		if baked != Vector2i.ZERO:
			return baked
	var stamped: Vector2i = FieldCatalog.wrap_tiles_from_extras(active)
	if stamped != Vector2i.ZERO:
		return stamped
	var cell: int = _gcd(atlas.x, atlas.y)
	return Vector2i(maxi(atlas.x / cell, 1), maxi(atlas.y / cell, 1)) if cell > 0 else Vector2i.ONE


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t: int = a % b
		a = b
		b = t
	return absi(a)


static func is_cloth_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	var label := VisualSurface.surface_label(mesh_instance, surface, mat)
	## Villager ANIME_1 / `seg_08` is eyes (`aNPC_anime_tex_set`); cloth is ANIME_3 / `seg_0A`.
	if label.contains("seg_0a") or label.contains("anime_3"):
		return true
	## Mannequin shirt is `seg_08` / `anime_1` on `*manekin*` meshes only.
	if not label.contains("manekin"):
		return false
	if label.contains("seg_08") or label.contains("anime_1"):
		return true
	## Unbound shirt has no baked albedo; stand CI textures do.
	return mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture == null


static func _surface_uv_max(mesh: Mesh, surface: int) -> Vector2:
	if mesh == null:
		return Vector2.ONE
	var arrays: Array = mesh.surface_get_arrays(surface)
	if arrays.is_empty() or arrays[Mesh.ARRAY_TEX_UV] == null:
		return Vector2.ONE
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var span := Vector2.ZERO
	for uv: Vector2 in uvs:
		span.x = maxf(span.x, uv.x)
		span.y = maxf(span.y, uv.y)
	if span.x <= 0.0:
		span.x = 1.0
	if span.y <= 0.0:
		span.y = 1.0
	return span


static func _repeat_tiles(span: float) -> int:
	return maxi(ceili(span - 0.001), 1)


static func _tiled_albedo(tex: Texture2D, tiles_u: int, tiles_v: int) -> Texture2D:
	if tex == null or (tiles_u <= 1 and tiles_v <= 1):
		return tex
	var img: Image = tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	var out := Image.create(w * tiles_u, h * tiles_v, false, Image.FORMAT_RGBA8)
	for ty: int in tiles_v:
		for tx: int in tiles_u:
			out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(tx * w, ty * h))
	return ImageTexture.create_from_image(out)
