class_name VisualRoomPaint
extends RefCounted
## Interior wall/floor texturing: classify a room surface and paint the chosen style onto it.


static func _load_tex(path: String) -> Texture2D:
	if path.is_empty():
		return null
	return load(path) as Texture2D


static func paint_room_surfaces(node: Node, wall_id: StringName, floor_id: StringName) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var src: Material = mesh_instance.get_active_material(i)
			if (
				VisualWindowLight.is_window_spill_surface(mesh_instance, i, src)
				or VisualWindowLight.is_window_pane_surface(mesh_instance, i, src)
				or VisualWaterMaterials.water_kind(src) in ["river", "ocean", "splash", "beach_wet"]
			):
				continue
			var kind := _room_surface_kind(mesh_instance, i)
			if kind == &"":
				continue
			var page: int = style_page(_style_label(src))
			var path: String = (
				InteriorStyleCatalog.floor_texture_path(floor_id, page)
				if kind == &"floor"
				else InteriorStyleCatalog.wall_texture_path(wall_id, page)
			)
			var tile: Texture2D = _load_tex(path)
			## Bank swap only when a real wallpaper/carpet PNG resolves. Named tints
			## (`wall_default`) and empty ids must not strip baked shell albedos —
			## shops/tailor bake style-0 `player_room_*` into the GLB.
			if tile == null:
				continue
			var mat: Material = mesh_instance.get_surface_override_material(i)
			if mat == null:
				mat = mesh_instance.get_active_material(i)
			var std: StandardMaterial3D
			var src_mat: Material = src if src != null else mat
			if mat is StandardMaterial3D:
				std = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				std = StandardMaterial3D.new()
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			## Wrap-baked shells keep CLAMP UVs on an atlas; tile into that atlas size.
			std.texture_repeat = false
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			std.roughness = 1.0
			std.metallic = 0.0
			if VisualMaterials.is_vertex_shade_surface(mesh_instance, i, src_mat):
				VisualMaterials.apply_vertex_shade_material(std)
			else:
				std.vertex_color_use_as_albedo = false
			var target: Vector2i = VisualAtlas.albedo_size(std)
			## Floors use GX_MIRROR (corner tile → one room medallion). Walls REPEAT.
			## Bank pages are always 64². Do not infer period from a MIRROR atlas —
			## odd cells are flipped so a 64-period check fails and `VisualAtlas.infer_tile_size` picks 128,
			## stretching stone/wallpaper 2× across the shell.
			var mirror := kind == &"floor"
			std.albedo_texture = VisualAtlas.tile_to_atlas(tile, target, mirror, mirror, 64)
			## `Global_kankyo_set_room_prim`: TEXEL × SHADE × PRIM on indoor shells.
			std.albedo_color = VisualWindowLight.room_prim_color()
			std.set_meta("room_prim_surface", true)
			mesh_instance.set_surface_override_material(i, std)
	for child in node.get_children():
		paint_room_surfaces(child, wall_id, floor_id)


static func _style_label(mat: Material) -> String:
	## Mesh names like `room01` must not pick a wallpaper page.
	var bits: PackedStringArray = PackedStringArray()
	bits.append(VisualSurface.resource_label(mat))
	if mat is StandardMaterial3D:
		bits.append(VisualSurface.resource_label((mat as StandardMaterial3D).albedo_texture))
	return " ".join(bits)


static func style_page(label: String) -> int:
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


static func _room_surface_kind(mesh_instance: MeshInstance3D, surface: int) -> StringName:
	## Empty → leave the baked shell texture (window, exit trim, props).
	## Prefer the GLB material; runtime overrides drop the `rom_myhome_window_tex` name.
	var baked: Material = null
	if mesh_instance.mesh != null:
		baked = mesh_instance.mesh.surface_get_material(surface)
	var mat: Material = baked if baked != null else mesh_instance.get_active_material(surface)
	return classify_room_surface(VisualSurface.surface_label(mesh_instance, surface, mat))


static func classify_room_surface(label: String) -> StringName:
	## Only bank placeholders (`player_room_*` / carpet). Baked shells
	## (`rom_museum*_floor*`, `rom_tailor_wall*`, `room_floor`, …) keep their textures.
	## Parent mesh is `rom_myhome1_wall`; window/enter prims must not pick up that "wall".
	var lower := label.to_lower()
	if lower.contains("window") or lower.contains("enter"):
		return &""
	var shop_kind := _shop_fw_shell_kind(lower)
	if lower.contains("player_room_floor") or lower.contains("carpet"):
		return &"floor"
	if lower.contains("player_room_wall"):
		## Shop `*f` DLs sample floor segs 0x08–0x0B. Older converts bound wall over
		## 0x08/0x09, so those pages are named `player_room_wall` on the floor mesh.
		if shop_kind == &"floor":
			return &"floor"
		return &"wall"
	return &""


static func _shop_fw_shell_kind(label: String) -> StringName:
	## `rom_shop1f` / `rom_shop4_2w` — not `rom_shop1_fuku` or `rom_shop4_1`.
	var start: int = 0
	while true:
		var idx: int = label.find("rom_shop", start)
		if idx < 0:
			return &""
		var end: int = idx
		while end < label.length():
			var ch := label[end]
			if ch == " " or ch == "." or ch == "/":
				break
			end += 1
		var kind := _shop_fw_token_kind(label.substr(idx, end - idx))
		if kind != &"":
			return kind
		start = idx + 8
	return &""


static func _shop_fw_token_kind(token: String) -> StringName:
	if not token.begins_with("rom_shop"):
		return &""
	var suffix := token.substr(token.length() - 1)
	if suffix != "f" and suffix != "w":
		return &""
	var mid := token.substr(8, token.length() - 9)
	if mid.is_empty():
		return &""
	if not mid.is_valid_int() and not mid.replace("_", "").is_valid_int():
		return &""
	return &"floor" if suffix == "f" else &"wall"
