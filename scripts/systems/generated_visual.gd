class_name GeneratedVisual
extends RefCounted

## Loads a pipeline GLB onto a host and hides placeholder meshes.
## Missing files are expected until `python3 tools/build_assets.py` has been run.

## Facade window panes (`*_light_model`): opaque prim/env fill, black off / yellow on.
const _WINDOW_PANE_ON := Color(1.0, 1.0, 150.0 / 255.0, 1.0)
const _WINDOW_PANE_OFF := Color(0.0, 0.0, 0.0, 1.0)
## Ground spill: prim RGB, I4 × PRIM_LOD_FRAC (120/255) as alpha (`ac_house_draw` / `ac_shop_draw`).
const _WINDOW_SPILL_ON := Color(1.0, 1.0, 150.0 / 255.0, 120.0 / 255.0)
const _WINDOW_SPILL_OFF := Color(1.0, 1.0, 150.0 / 255.0, 0.0)
const _WINDOW_SPILL_SHADER := preload("res://shaders/window_ground_spill.gdshader")


static func detach(host: Node3D) -> void:
	if host == null:
		return
	var vis: Node = host.get_node_or_null("GeneratedVisual")
	if vis == null:
		for child in host.get_children():
			vis = child.get_node_or_null("GeneratedVisual")
			if vis != null:
				break
	if vis != null:
		vis.queue_free()


static func attach(host: Node3D, visual_id: StringName) -> Node3D:
	if host == null or visual_id == &"":
		return null
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual_id)
	if paths.is_empty():
		return null
	var pivot := Node3D.new()
	pivot.name = "GeneratedVisual"
	for path: String in paths:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		if inst is Node3D:
			pivot.add_child(inst)
		else:
			inst.queue_free()
	if pivot.get_child_count() == 0:
		pivot.free()
		return null
	_hide_placeholder_meshes(host)
	_stop_autoplay(pivot)
	host.add_child(pivot)
	_apply_materials(pivot, FieldCatalog.is_ground_decal(visual_id))
	_fit(pivot, visual_id)
	return pivot


## Load a pipeline GLB with preview materials, but no host, ground-fit, or extra scale.
## Held tools inherit actor GX scale from the player visual they parent under.
static func instantiate_raw(visual_id: StringName) -> Node3D:
	if visual_id == &"":
		return null
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual_id)
	if paths.is_empty():
		return null
	var pivot := Node3D.new()
	pivot.name = "HeldToolMesh"
	for path: String in paths:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		if inst is Node3D:
			pivot.add_child(inst)
		else:
			inst.queue_free()
	if pivot.get_child_count() == 0:
		pivot.free()
		return null
	_apply_materials(pivot)
	return pivot


static func apply_preview_materials(node: Node) -> void:
	_apply_materials(node)


static func refresh_window_lights(root: Node) -> void:
	## `mEnv_NPC_LIGHTS_*`: panes and ground spill 18:00–05:00.
	_set_window_lights(root, _window_lights_on())


static func attach_villager(host: Node3D, species: StringName) -> Node3D:
	## Species GLB (`squ_1`, `cat_1`, …) when the local pipeline has been run.
	if host == null or species == &"":
		return null
	var path: String = FieldCatalog.villager_path(species)
	if path.is_empty():
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	if not (inst is Node3D):
		inst.queue_free()
		return null
	var pivot := Node3D.new()
	pivot.name = "GeneratedVisual"
	pivot.add_child(inst)
	_hide_placeholder_meshes(host)
	_stop_autoplay(pivot)
	host.add_child(pivot)
	_apply_materials(pivot)
	_fit_actor(pivot)
	return pivot


static func find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = find_animation_player(child)
		if found != null:
			return found
	return null


static func apply_item_albedo(host: Node, item_id: StringName) -> void:
	var path: String = FieldCatalog.item_albedo(item_id)
	if path.is_empty() or host == null:
		return
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return
	_paint_albedo(host, tex)


static func apply_cloth(host: Node, cloth_index: int) -> void:
	## Mannequin shirt samples `anime_1_txt` (seg 8). Stand keeps baked CI textures.
	var path: String = FieldCatalog.cloth_albedo(cloth_index)
	if path.is_empty() or host == null:
		return
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return
	_paint_cloth(host, tex)


static func attach_interior(
	host: Node3D, shell_ids: PackedStringArray, wall_id: StringName, floor_id: StringName, target: AABB
) -> Node3D:
	if host == null or shell_ids.is_empty():
		return null
	var pivot := Node3D.new()
	pivot.name = "GeneratedVisual"
	for visual_id: String in shell_ids:
		var paths: PackedStringArray = FieldCatalog.mesh_paths(StringName(visual_id))
		for path: String in paths:
			var packed: PackedScene = load(path) as PackedScene
			if packed == null:
				continue
			var inst: Node = packed.instantiate()
			if inst is Node3D:
				pivot.add_child(inst)
			else:
				inst.queue_free()
	if pivot.get_child_count() == 0:
		pivot.free()
		return null
	_hide_placeholder_meshes(host)
	host.add_child(pivot)
	_apply_materials(pivot)
	_apply_room_textures(pivot, wall_id, floor_id)
	_fit_interior(pivot, target, StringName(shell_ids[0]))
	_disable_shadows(pivot)
	return pivot


static func _fit(pivot: Node3D, visual_id: StringName) -> void:
	if FieldCatalog.is_acre(visual_id):
		_fit_acre(pivot)
		return
	if FieldCatalog.is_ground_decal(visual_id):
		_fit_ground_decal(pivot)
		return
	_fit_actor(pivot, visual_id)


static func _fit_acre(pivot: Node3D) -> void:
	## Same scale and origin for every `grd_*` so neighbors share edges and the land datum.
	var s: float = FieldCatalog.acre_uniform_scale()
	pivot.scale = Vector3.ONE * s
	pivot.position = Vector3(0.0, FieldCatalog.acre_ground_y_offset(), 0.0)


static func _fit_actor(pivot: Node3D, visual_id: StringName = &"") -> void:
	## Same GX→meter factor as acres. Authored origin is actor world pos
	## (`m_actor.c` / `aMR_UnitNumber2Position`). Only micro-ground when feet
	## sit near Y=0 — do not AABB-snap deep spikes (piano pedals at −7650 vtx).
	## `aFTR_PROFILE.scale` is 0.1 for a few items (modern chair `int_ari_isu01`).
	var s: float = FieldCatalog.actor_uniform_scale_for(visual_id)
	pivot.scale = Vector3.ONE * s
	var aabb: AABB = _local_aabb(pivot)
	if aabb.size == Vector3.ZERO:
		return
	var min_y: float = aabb.position.y
	if min_y > -0.5 and min_y < 2.0:
		pivot.position.y = -min_y * s


static func _fit_ground_decal(pivot: Node3D) -> void:
	## Keep authored Y. AABB-snapping a coplanar fan onto the acre z-fights with grass.
	pivot.scale = Vector3.ONE * FieldCatalog.actor_uniform_scale()


static func _fit_interior(pivot: Node3D, target: AABB, visual_id: StringName) -> void:
	## `room01` verts are raw GX (max Z 320 = 8 units). Place at the field origin
	## with GX→meter scale so FG cells (1,1)–(6,6) sit on the floor. Do not AABB-fit.
	## `rom_*` stay at acre scale (40 GX = 2 m). Translate the floor min-corner onto
	## the walkable rect — do not scale to the AABB. Walls (door alcove, trim) are
	## larger than the carpet and would squash furniture off the FG grid.
	if not FieldCatalog.interior_uses_acre_verts(visual_id):
		var gx: float = FieldCatalog.interior_uniform_scale(visual_id)
		pivot.scale = Vector3.ONE * gx
		pivot.position = Vector3(
			target.position.x, FieldCatalog.interior_ground_y_offset(visual_id), target.position.z
		)
		return
	var s: float = FieldCatalog.acre_uniform_scale()
	pivot.scale = Vector3.ONE * s
	var aabb: AABB = _local_aabb_named(pivot, "floor")
	if aabb.size.x <= 0.001 or aabb.size.z <= 0.001:
		aabb = _local_aabb(pivot)
	if aabb.size.x <= 0.001 or aabb.size.z <= 0.001:
		pivot.position = Vector3(0.0, FieldCatalog.interior_ground_y_offset(visual_id), 0.0)
		return
	pivot.position = Vector3(
		target.position.x - aabb.position.x * s,
		-aabb.position.y * s,
		target.position.z - aabb.position.z * s
	)


static func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)


static func _apply_room_textures(node: Node, wall_id: StringName, floor_id: StringName) -> void:
	_paint_room_surfaces(node, wall_id, floor_id)


static func _load_tex(path: String) -> Texture2D:
	if path.is_empty():
		return null
	return load(path) as Texture2D


static func _paint_room_surfaces(node: Node, wall_id: StringName, floor_id: StringName) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var src: Material = mesh_instance.get_active_material(i)
			if _is_window_spill_surface(mesh_instance, i, src) or _is_window_pane_surface(mesh_instance, i, src):
				continue
			var kind := _room_surface_kind(mesh_instance, i)
			if kind == &"":
				continue
			var page: int = _style_page(_style_label(src))
			var path: String = (
				InteriorCatalog.floor_texture_path(floor_id, page)
				if kind == &"floor"
				else InteriorCatalog.wall_texture_path(wall_id, page)
			)
			var tile: Texture2D = _load_tex(path)
			var tint: Color = (
				InteriorCatalog.floor_color(floor_id) if kind == &"floor" else InteriorCatalog.wall_color(wall_id)
			)
			if tile == null and tint.a <= 0.0:
				continue
			var mat: Material = mesh_instance.get_surface_override_material(i)
			if mat == null:
				mat = mesh_instance.get_active_material(i)
			var std: StandardMaterial3D
			if mat is StandardMaterial3D:
				std = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				std = StandardMaterial3D.new()
			std.vertex_color_use_as_albedo = false
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			## Wrap-baked shells keep CLAMP UVs on an atlas; tile into that atlas size.
			std.texture_repeat = false
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			std.roughness = 1.0
			std.metallic = 0.0
			if tile != null:
				var target: Vector2i = _albedo_size(std)
				## Floors use GX_MIRROR (corner tile → one room medallion). Walls REPEAT.
				var mirror := kind == &"floor"
				std.albedo_texture = _tile_to_atlas(tile, target, mirror, mirror)
				std.albedo_color = Color.WHITE
			elif tint.a > 0.0:
				std.albedo_texture = null
				std.albedo_color = tint
			mesh_instance.set_surface_override_material(i, std)
	for child in node.get_children():
		_paint_room_surfaces(child, wall_id, floor_id)


static func _style_label(mat: Material) -> String:
	## Mesh names like `room01` must not pick a wallpaper page.
	var bits: PackedStringArray = PackedStringArray()
	bits.append(_resource_label(mat))
	if mat is StandardMaterial3D:
		bits.append(_resource_label((mat as StandardMaterial3D).albedo_texture))
	return " ".join(bits)


static func _style_page(label: String) -> int:
	## `player_room_wall_0_1` / `wall_15_1.png` → page 1. Ignore `wall_15` style index.
	var lower := label.to_lower()
	for needle: String in ["wall_", "floor_", "carpet_"]:
		var idx: int = lower.rfind(needle)
		if idx < 0:
			continue
		var rest := lower.substr(idx + needle.length())
		var tokens: PackedStringArray = rest.split("_")
		if tokens.size() < 2:
			continue
		var style_idx: int = _leading_int(tokens[0])
		var page: int = _leading_int(tokens[1])
		if style_idx >= 0 and page >= 0:
			return clampi(page, 0, 3)
	return 0


static func _leading_int(token: String) -> int:
	var digits := ""
	for i: int in range(token.length()):
		var ch := token.substr(i, 1)
		if ch < "0" or ch > "9":
			break
		digits += ch
	if digits.is_empty():
		return -1
	return digits.to_int()


static func _albedo_size(mat: StandardMaterial3D) -> Vector2i:
	if mat == null or mat.albedo_texture == null:
		return Vector2i.ZERO
	var tex: Texture2D = mat.albedo_texture
	return Vector2i(tex.get_width(), tex.get_height())


static func _texture_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null and not tex.resource_path.is_empty():
		img = Image.load_from_file(ProjectSettings.globalize_path(tex.resource_path))
	if img == null:
		return null
	if img.is_compressed():
		img = img.duplicate()
		if img.decompress() != OK:
			return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


static func _tile_to_atlas(
	tile: Texture2D, target: Vector2i, mirror_u: bool = false, mirror_v: bool = false
) -> Texture2D:
	## Pipeline wrap-bake expands a 64×N tile into an atlas and remaps UVs to 0–1.
	## Swapping a single tile without re-tiling makes wallpapers look glitchy.
	## Room floors are GX_MIRROR (odd cells flipped) so a corner tile becomes one medallion.
	if tile == null:
		return null
	if target.x <= 0 or target.y <= 0:
		return tile
	var src: Image = _texture_image(tile)
	if src == null:
		return tile
	var tw: int = src.get_width()
	var th: int = src.get_height()
	if tw <= 0 or th <= 0:
		return tile
	if tw == target.x and th == target.y and not mirror_u and not mirror_v:
		return tile
	var out := Image.create(target.x, target.y, false, Image.FORMAT_RGBA8)
	var tiles_u: int = maxi(1, int(ceili(float(target.x) / float(tw))))
	var tiles_v: int = maxi(1, int(ceili(float(target.y) / float(th))))
	for tj: int in tiles_v:
		for ti: int in tiles_u:
			var cell: Image = src
			var flip_u := mirror_u and (ti & 1) == 1
			var flip_v := mirror_v and (tj & 1) == 1
			if flip_u or flip_v:
				cell = src.duplicate()
				if flip_u:
					cell.flip_x()
				if flip_v:
					cell.flip_y()
			out.blit_rect(cell, Rect2i(0, 0, tw, th), Vector2i(ti * tw, tj * th))
	if out.get_width() != target.x or out.get_height() != target.y:
		out = out.get_region(Rect2i(0, 0, target.x, target.y))
	return ImageTexture.create_from_image(out)


static func _room_surface_kind(mesh_instance: MeshInstance3D, surface: int) -> StringName:
	## Empty → leave the baked shell texture (window, exit trim, props).
	var label := _surface_label(mesh_instance, surface, mesh_instance.get_active_material(surface)).to_lower()
	if label.contains("floor") or label.contains("carpet"):
		return &"floor"
	if label.contains("wall"):
		return &"wall"
	return &""


static func _hide_placeholder_meshes(host: Node) -> void:
	if host is MeshInstance3D:
		(host as MeshInstance3D).visible = false
	for child in host.get_children():
		if child.name == "GeneratedVisual" or child.name == "Stump":
			continue
		if child is CollisionShape3D or child is Area3D:
			continue
		_hide_placeholder_meshes(child)


static func _window_lights_on() -> bool:
	if Clock == null:
		return false
	return Clock.in_hour_window(18, 5)


static func _apply_materials(node: Node, as_decal: bool = false) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat == null:
				mat = StandardMaterial3D.new()
			if mat is StandardMaterial3D:
				var src := mat
				var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				std.vertex_color_use_as_albedo = false
				std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				std.texture_repeat = false
				std.cull_mode = BaseMaterial3D.CULL_DISABLED
				std.roughness = 1.0
				std.metallic = 0.0
				if _is_window_spill_surface(mesh_instance, i, src):
					mesh_instance.set_surface_override_material(i, _make_window_spill_material(std))
				elif _is_window_pane_surface(mesh_instance, i, src):
					_apply_window_pane_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif as_decal:
					std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
					std.render_priority = 1
					mesh_instance.set_surface_override_material(i, std)
				else:
					mesh_instance.set_surface_override_material(i, std)
		if as_decal:
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh_instance.sorting_offset = 1.0
	for child in node.get_children():
		_apply_materials(child, as_decal)


static func _surface_label(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> String:
	var bits: PackedStringArray = PackedStringArray()
	bits.append(_resource_label(mat))
	if mat is StandardMaterial3D:
		bits.append(_resource_label((mat as StandardMaterial3D).albedo_texture))
	if mesh_instance.mesh is ArrayMesh:
		bits.append((mesh_instance.mesh as ArrayMesh).surface_get_name(surface).to_lower())
	bits.append(String(mesh_instance.name).to_lower())
	return " ".join(bits)


static func _resource_label(res: Resource) -> String:
	if res == null:
		return ""
	return "%s %s" % [String(res.resource_name), res.resource_path.get_file()]


static func _stop_autoplay(node: Node) -> void:
	## Furniture cKF clips are open/close; rest is frame 1 (closed). Do not play.
	var anim: AnimationPlayer = find_animation_player(node)
	if anim == null:
		return
	anim.autoplay = ""
	anim.stop()
	anim.seek(0.0, true)


static func _is_window_spill_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	## Outdoor ground fan (`*_window_model` / `windowL_model`). Not indoor `room_window`.
	var n := _surface_label(mesh_instance, surface, mat).to_lower()
	if n.contains("light"):
		return false
	return (
		n.contains("window_model")
		or n.contains("windowl_model")
		or n.contains("windowr_model")
		or n.contains("windowt_model")
	)


static func _is_window_pane_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	## Opaque fill in the wall TEX_EDGE holes (`*_light_model`, museum `*_lightT_model`).
	var n := _surface_label(mesh_instance, surface, mat).to_lower()
	return n.contains("light_model") or n.contains("lightt_model")


static func _make_window_spill_material(std: StandardMaterial3D) -> ShaderMaterial:
	## Original: `G_RM_AA_ZB_XLU_DECAL2` on SHADOW_DISP. Lift 1 GX so it is not the grass plane.
	var sh := ShaderMaterial.new()
	sh.shader = _WINDOW_SPILL_SHADER
	sh.render_priority = 1
	var tex: Texture2D = std.albedo_texture
	if tex != null:
		var img: Image = tex.get_image()
		if img != null and img.detect_alpha() == Image.ALPHA_NONE:
			tex = _i4_as_alpha(tex)
	sh.set_shader_parameter("albedo_texture", tex)
	sh.set_shader_parameter("albedo", _WINDOW_SPILL_ON if _window_lights_on() else _WINDOW_SPILL_OFF)
	sh.set_shader_parameter("ground_lift", FieldCatalog.GX_TO_METERS)
	sh.set_meta("window_spill", true)
	return sh


static func _i4_as_alpha(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, c.r))
	return ImageTexture.create_from_image(img)


static func _apply_window_pane_material(std: StandardMaterial3D) -> void:
	## Original: combiner ignores the wall SETTIMG; RGB is PRIMITIVE/ENVIRONMENT, `G_RM_AA_ZB_OPA_SURF2`.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	std.albedo_texture = null
	std.set_meta("window_pane", true)
	std.albedo_color = _WINDOW_PANE_ON if _window_lights_on() else _WINDOW_PANE_OFF


static func _set_window_lights(node: Node, on: bool) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_surface_override_material(i)
			if mat is ShaderMaterial and (mat as ShaderMaterial).has_meta("window_spill"):
				(mat as ShaderMaterial).set_shader_parameter(
					"albedo", _WINDOW_SPILL_ON if on else _WINDOW_SPILL_OFF
				)
			elif mat is StandardMaterial3D and (mat as StandardMaterial3D).has_meta("window_pane"):
				(mat as StandardMaterial3D).albedo_color = _WINDOW_PANE_ON if on else _WINDOW_PANE_OFF
	for child in node.get_children():
		_set_window_lights(child, on)


static func _paint_albedo(node: Node, tex: Texture2D) -> void:
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
		_paint_albedo(child, tex)


static func _paint_cloth(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var src: Material = mesh_instance.get_active_material(i)
			if not _is_cloth_surface(mesh_instance, i, src):
				continue
			var std: StandardMaterial3D
			if src is StandardMaterial3D:
				std = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				std = StandardMaterial3D.new()
			var span: Vector2 = _surface_uv_max(mesh_instance.mesh, i)
			var tiles_u: int = _repeat_tiles(span.x)
			var tiles_v: int = _repeat_tiles(span.y)
			std.albedo_texture = _tiled_albedo(tex, tiles_u, tiles_v)
			std.albedo_color = Color.WHITE
			std.uv1_scale = Vector3(1.0 / float(tiles_u), 1.0 / float(tiles_v), 1.0)
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			## Shirt DLs are wrapS=REPEAT / wrapT=CLAMP with U up to 2. Tile the PNG
			## and keep clamp — Godot has one texture_repeat flag for both axes.
			std.texture_repeat = false
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			std.roughness = 1.0
			std.metallic = 0.0
			mesh_instance.set_surface_override_material(i, std)
	for child in node.get_children():
		_paint_cloth(child, tex)


static func _is_cloth_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	var label := _surface_label(mesh_instance, surface, mat)
	if label.contains("seg_08") or label.contains("anime_1"):
		return true
	## Unbound shirt has no baked albedo; stand CI textures do.
	if not label.contains("manekin"):
		return false
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


static func _local_aabb(node: Node) -> AABB:
	return _local_aabb_named(node, "")


static func _local_aabb_named(node: Node, needle: String) -> AABB:
	## Empty needle → every mesh. Otherwise only meshes under a matching name
	## (`rom_myhome2_floor`, …).
	return _local_aabb_named_inner(node, needle.to_lower(), needle.is_empty())


static func _local_aabb_named_inner(node: Node, needle: String, under_match: bool) -> AABB:
	var match := under_match or String(node.name).to_lower().contains(needle)
	var merged := AABB()
	var started := false
	if match and node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			merged = mi.transform * mi.mesh.get_aabb()
			started = true
	for child in node.get_children():
		var child_aabb := _local_aabb_named_inner(child, needle, match)
		if child_aabb.size == Vector3.ZERO:
			continue
		if child is Node3D:
			child_aabb = (child as Node3D).transform * child_aabb
		if started:
			merged = merged.merge(child_aabb)
		else:
			merged = child_aabb
			started = true
	return merged
