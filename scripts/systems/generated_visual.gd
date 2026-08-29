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


static func _fit(pivot: Node3D, visual_id: StringName) -> void:
	if FieldCatalog.is_acre(visual_id):
		_fit_acre(pivot)
		return
	if FieldCatalog.is_ground_decal(visual_id):
		_fit_ground_decal(pivot)
		return
	_fit_actor(pivot)


static func _fit_acre(pivot: Node3D) -> void:
	## Same scale and origin for every `grd_*` so neighbors share edges and the land datum.
	var s: float = FieldCatalog.acre_uniform_scale()
	pivot.scale = Vector3.ONE * s
	pivot.position = Vector3(0.0, FieldCatalog.acre_ground_y_offset(), 0.0)


static func _fit_actor(pivot: Node3D) -> void:
	## Same GX→meter factor as acres. Authored origin is actor world pos (`m_actor.c`).
	var s: float = FieldCatalog.actor_uniform_scale()
	pivot.scale = Vector3.ONE * s
	var aabb: AABB = _local_aabb(pivot)
	if aabb.size == Vector3.ZERO:
		return
	pivot.position.y = -aabb.position.y * s


static func _fit_ground_decal(pivot: Node3D) -> void:
	## Keep authored Y. AABB-snapping a coplanar fan onto the acre z-fights with grass.
	pivot.scale = Vector3.ONE * FieldCatalog.actor_uniform_scale()


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


static func _is_window_spill_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	## Ground fan (`*_window_model`, `*_window_tex`). Not facade panes (`*_light_model`).
	var n := _surface_label(mesh_instance, surface, mat).to_lower()
	if n.contains("light"):
		return false
	return n.contains("window")


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


static func _local_aabb(node: Node) -> AABB:
	var merged := AABB()
	var started := false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			merged = mi.transform * mi.mesh.get_aabb()
			started = true
	for child in node.get_children():
		var child_aabb := _local_aabb(child)
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
