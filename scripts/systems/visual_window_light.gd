class_name VisualWindowLight
extends RefCounted
## House/shop window panes, ground spill and room-prim fills: lit at night, dark by day.

## Loads a pipeline GLB onto a host and hides placeholder meshes.
## Missing files are expected until `python3 tools/build_assets.py` has been run.
## Facade window panes (`*_light_model`): opaque prim/env fill, black off / yellow on.
const _WINDOW_PANE_ON := Color(1.0, 1.0, 150.0 / 255.0, 1.0)
const _WINDOW_PANE_OFF := Color(0.0, 0.0, 0.0, 1.0)
## Ground spill: prim RGB, I4 × PRIM_LOD_FRAC (120/255) as alpha (`ac_house_draw` / `ac_shop_draw`).
## Composited in 8-bit sRGB by `window_ground_spill.gdshader` (not Godot linear blend_mix).
const _WINDOW_SPILL_ON := Color(1.0, 1.0, 150.0 / 255.0, 120.0 / 255.0)
const _WINDOW_SPILL_OFF := Color(1.0, 1.0, 150.0 / 255.0, 0.0)
const _WINDOW_SPILL_SHADER := preload("res://shaders/window_ground_spill.gdshader")


static func refresh_window_lights(root: Node) -> void:
	## `mEnv_NPC_LIGHTS_*`: panes and ground spill 18:00–05:00, unless a building
	## host on the way down has its own `*_ctrl_light` rule.
	_set_window_lights(root, _window_lights_on())


## A building host's own `*_ctrl_light`, or null when `node` isn't one (the caller's
## state carries on). Hosts are the field `Building` / `House` / `Shop` nodes.
static func host_lights_on(node: Node) -> Variant:
	if node == null or not ("visual_id" in node and "occupant_id" in node):
		return null
	var night := _window_lights_on()
	var vis := StringName(node.get("visual_id"))
	if HostCollision.is_police(vis) or HostCollision.is_post_office(vis):
		return night  ## `aPBOX_ctrl_light` / `aPOFF_ctrl_light`
	if HostCollision.is_museum(vis):
		return Clock != null and Clock.in_hour_window(18, 6)  ## `aMsm_ctrl_light`
	var entry := StringName(node.get("occupant_id"))
	var room_id: StringName = InteriorCatalog.resolve_entry(entry) if entry != &"" else &""
	var room: Room = InteriorCatalog.room_template(room_id) if room_id != &"" else null
	if room == null:
		return night
	match room.kind:
		Room.Kind.SHOP:
			if Game == null or Game.shops == null:
				return night
			## `aSHOP_ctrl_light`: the Cranny lights at night while open; Nook 'n' Go and
			## up (`aCNV` / `aSPR` / `aDPT`) whenever they're open.
			var open: bool = Game.shops.nook_is_open()
			return open if Game.shops.nook_level() >= 1 else open and night
		Room.Kind.NEEDLEWORK:
			return night and InteriorCatalog.is_open_now(room)  ## `aNW_ctrl_light`
		Room.Kind.NPC:
			return night and VillagerHome.lights_on(entry)  ## `aHUS_ctrl_light`
	return night


static func refresh_room_prim(root: Node, color: Color = Color.WHITE) -> void:
	## `Global_kankyo_set_room_prim` — indoor outdoor-view quads use room prim RGB.
	if root == null:
		return
	if color.a <= 0.0:
		color = room_prim_color()
	_set_room_prim_fills(root, color)


static func _window_lights_on() -> bool:
	if Clock == null:
		return false
	return Clock.in_hour_window(18, 5)


static func is_window_spill_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	## Prefer glTF extras from pipeline (XLU decal); legacy name match for older GLBs.
	if bool(VisualSurface.gltf_extras(mat).get("ground_spill", false)):
		return true
	var n := VisualSurface.surface_label(mesh_instance, surface, mat).to_lower()
	if n.contains("light"):
		return false
	return (
		n.contains("window_model")
		or n.contains("windowl_model")
		or n.contains("windowr_model")
		or n.contains("windowt_model")
	)


static func is_window_pane_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	## Opaque prim fill in wall TEX_EDGE holes. Outdoor-view uses bright unlit prim.
	var n := VisualSurface.surface_label(mesh_instance, surface, mat).to_lower()
	if n.contains("light_model") or n.contains("lightt_model"):
		return true
	if bool(VisualSurface.gltf_extras(mat).get("unlit_fill", false)):
		if mat is StandardMaterial3D:
			var c: Color = (mat as StandardMaterial3D).albedo_color
			## Outdoor sky fill is near-white; facade panes are black.
			return c.r + c.g + c.b < 1.5
		return true
	return false


static func is_room_prim_fill_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	## Indoor `rom_*` outdoor-view quads (`G_CC_PRIMITIVE` after window MASK).
	## Bright unlit_fill — not facade night panes.
	if not bool(VisualSurface.gltf_extras(mat).get("unlit_fill", false)):
		return false
	if is_window_pane_surface(mesh_instance, surface, mat):
		return false
	return true


static func make_window_spill_material(std: StandardMaterial3D) -> ShaderMaterial:
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


## An XLU `G_IM_FMT_I` texture as coverage in alpha (the PNG may carry it as grey).
static func coverage_texture(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img != null and img.detect_alpha() == Image.ALPHA_NONE:
		return _i4_as_alpha(tex)
	return tex


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


static func apply_window_pane_material(std: StandardMaterial3D) -> void:
	## Original: combiner ignores the wall SETTIMG; RGB is PRIMITIVE/ENVIRONMENT, `G_RM_AA_ZB_OPA_SURF2`.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	## Single-sided: CULL_DISABLED draws rear-window backfaces as wall-sized black slabs
	## when viewed from the porch.
	std.cull_mode = BaseMaterial3D.CULL_BACK
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	## Draw before facade OPA/MASK so door wood and walls win any residual overlap.
	std.render_priority = -1
	std.albedo_texture = null
	std.vertex_color_use_as_albedo = false
	std.set_meta("window_pane", true)
	std.albedo_color = _WINDOW_PANE_ON if _window_lights_on() else _WINDOW_PANE_OFF


static func apply_room_prim_fill_material(std: StandardMaterial3D) -> void:
	## `Global_kankyo_set_room_prim` fills indoor window holes with room prim RGB.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.cull_mode = BaseMaterial3D.CULL_BACK
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	std.render_priority = -1
	std.albedo_texture = null
	std.vertex_color_use_as_albedo = false
	std.set_meta("room_prim_fill", true)
	std.albedo_color = room_prim_color()


static func room_prim_color() -> Color:
	## Fine-weather `room_color` from `l_mEnv_kcolor_fine_data` (no electric-point blend yet).
	var clock: Node = Engine.get_main_loop().root.get_node_or_null("/root/Clock")
	if clock != null and clock.has_method("outdoor_light"):
		var pal: Dictionary = clock.call("outdoor_light") as Dictionary
		if pal.has("room"):
			return pal["room"] as Color
	return Color8(200, 240, 240)


static func mark_shell_room_prim(node: Node) -> void:
	## Window frames / enter trim share TEXEL×SHADE×PRIM; tag for room-prim refresh.
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_surface_override_material(i)
			if mat == null:
				mat = mesh_instance.get_active_material(i)
			if mat == null:
				continue
			if is_window_pane_surface(mesh_instance, i, mat) or is_room_prim_fill_surface(
				mesh_instance, i, mat
			):
				continue
			if not VisualMaterials.is_vertex_shade_surface(mesh_instance, i, mat):
				continue
			var std: StandardMaterial3D
			if mat is StandardMaterial3D:
				std = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				continue
			std.set_meta("room_prim_surface", true)
			mesh_instance.set_surface_override_material(i, std)
	for child in node.get_children():
		mark_shell_room_prim(child)


static func _set_room_prim_fills(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_surface_override_material(i)
			if mat is StandardMaterial3D:
				var std := mat as StandardMaterial3D
				if std.has_meta("room_prim_fill") or std.has_meta("room_prim_surface"):
					std.albedo_color = color
	for child in node.get_children():
		_set_room_prim_fills(child, color)


static func _set_window_lights(node: Node, on: bool) -> void:
	var own: Variant = host_lights_on(node)
	if own != null:
		on = bool(own)
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
