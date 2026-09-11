class_name GeneratedVisual
extends RefCounted

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
const _RIVER_WATER_SHADER := preload("res://shaders/river_water.gdshader")
const _SPLASH_WATER_SHADER := preload("res://shaders/splash_water.gdshader")
const _OCEAN_WATER_SHADER := preload("res://shaders/ocean_water.gdshader")
const _WATERFALL_WATER_SHADER := preload("res://shaders/waterfall_water.gdshader")
const _BEACH_WET_SHADER := preload("res://shaders/beach_wet.gdshader")
## DL prims: wet-sand beachA (206,189,148); ocean-bed beachB (32,48,144).
const _BEACH_PRIM_SAND := Color(206.0 / 255.0, 189.0 / 255.0, 148.0 / 255.0)
const _BEACH_PRIM_BED := Color(32.0 / 255.0, 48.0 / 255.0, 144.0 / 255.0)
## Inland river env (0,100,255); mouth acres use (0,60,255) when sprash is present.
const _RIVER_ENV_INLAND := Color(0.0, 100.0 / 255.0, 1.0, 1.0)
const _RIVER_ENV_MOUTH := Color(0.0, 60.0 / 255.0, 1.0, 1.0)


static func refresh(host: Node3D, visual_id: StringName) -> Node3D:
	## Detach and re-attach so mesh remaps and season albedo swaps run again.
	if host == null or visual_id == &"":
		return null
	detach(host)
	return attach(host, visual_id)


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
		## Immediate free so a same-frame re-attach (season swap) does not stack two pivots.
		vis.free()
	var blob: Node = host.get_node_or_null("BlobShadow")
	if blob != null:
		blob.free()


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
	if String(visual_id).begins_with("obj_train1_"):
		## Stop wheel/door autoplay; strip root tracks (keep skinning for door).
		prepare_outdoor_train(pivot)
	else:
		_stop_autoplay(pivot)
	_apply_materials(
		pivot,
		FieldCatalog.is_ground_decal(visual_id),
		FieldCatalog.is_ocean_acre_visual(visual_id),
		visual_id,
	)
	_fit(pivot, visual_id)
	## Swap field/tree albedos from the seasons pack (autumn grass, winter snow).
	apply_season_textures(pivot)
	_attach_blob_shadow(host, visual_id)
	return pivot


static func _attach_blob_shadow(host: Node3D, visual_id: StringName) -> void:
	## Authored `*_shadow_v` companion. Separate from GeneratedVisual so actor AABB fit
	## ignores the flat fan. Characters use `actor_blob_shadow.tscn` instead.
	if host == null or visual_id == &"":
		return
	var existing: Node = host.get_node_or_null("BlobShadow")
	if existing != null:
		existing.free()
	var paths: PackedStringArray = FieldCatalog.blob_shadow_paths(visual_id)
	if paths.is_empty():
		return
	var pivot := Node3D.new()
	pivot.name = "BlobShadow"
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
		return
	host.add_child(pivot)
	pivot.scale = Vector3.ONE * FieldCatalog.actor_uniform_scale_for(visual_id)
	## Same 2 GX bias as footprints / the actor blob so the flat decal clears the
	## acre plane (and the raised `StructureOffset` apron) without z-fighting.
	pivot.position.y = FootprintMarks.GROUND_LIFT
	_apply_blob_shadow_materials(pivot)
	_disable_shadows(pivot)


static func _apply_blob_shadow_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var surface_count: int = (
			mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		)
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_active_material(i)
			if not mat is StandardMaterial3D:
				continue
			var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			std.roughness = 1.0
			std.metallic = 0.0
			std.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			if std.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
				std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			## Clear of grass; under window spill / footprints.
			std.render_priority = 2
			mesh_instance.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		_apply_blob_shadow_materials(child)


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
	_apply_materials(node, false, _tree_is_ocean_acre(node))


static func apply_authored_interior(pivot: Node3D) -> void:
	## Scene-tree museum / train shells: materials + no shadows. Scale/origin stay in the tscn.
	if pivot == null:
		return
	_apply_materials(pivot)
	_disable_shadows(pivot)


static func layout_authored_interior(
	pivot: Node3D, room: Room, grid: WorldGrid, wall_height: float = 3.0
) -> void:
	## Authored GLB children under `Shell/GeneratedVisual`: materials, room textures, fit.
	## Museum wings keep editor transforms (apply materials only).
	if pivot == null or room == null or grid == null:
		return
	_apply_materials(pivot)
	_apply_room_textures(pivot, room.wall_id, room.floor_id)
	_mark_shell_room_prim(pivot)
	refresh_room_prim(pivot)
	_disable_shadows(pivot)
	if room.kind == Room.Kind.MUSEUM:
		return
	var visual_id: StringName = &""
	if not room.shell_ids.is_empty():
		visual_id = StringName(room.shell_ids[0])
	elif pivot.get_child_count() > 0:
		visual_id = StringName(pivot.get_child(0).name)
	if visual_id == &"":
		return
	var target := (
		AABB(
			grid.origin,
			Vector3(float(grid.columns) * grid.cell_size, wall_height, float(grid.rows) * grid.cell_size)
		)
		if _interior_keeps_acre_origin(visual_id, room)
		else _authored_shell_bounds(room, grid, wall_height)
	)
	_fit_interior(pivot, target, visual_id)


static func _authored_shell_bounds(room: Room, grid: WorldGrid, wall_height: float) -> AABB:
	var nw: Vector3 = grid.cell_corner(room.inner_origin)
	var se: Vector3 = grid.cell_corner(room.inner_origin + room.inner_size)
	return AABB(Vector3(nw.x, 0.0, nw.z), Vector3(se.x - nw.x, wall_height, se.z - nw.z))


static func apply_season_textures(node: Node) -> void:
	## Replace grass/earth/leaf/trunk albedos from `environment/seasons/{s,f,w}/`.
	## Acre GLBs bake wrap into the PNG; re-tile the season tile to the current atlas size.
	if node == null:
		return
	_apply_season_textures_inner(node)


static func _apply_season_textures_inner(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat == null:
				continue
			if mat is ShaderMaterial:
				if _apply_season_beach_wet(mesh_instance, i, mat as ShaderMaterial):
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
			var target: Vector2i = _albedo_size(std)
			var clamp_v := _season_tile_clamp_v(role)
			## Wrap-bake cell size from the atlas period (32 native / 128 capped ACHD).
			## Season HD into a stale native 512² atlas must resize to 32 — using the
			## 128 season sheet as the cell yields 4×4 tiles and 4× oversized grass.
			var cell := 0
			if target != Vector2i.ZERO and std.albedo_texture != null:
				cell = _infer_atlas_tile_size(std.albedo_texture, 0)
			std.albedo_texture = (
				_tile_to_atlas(season_tex, target, false, clamp_v, cell)
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
		_apply_season_textures_inner(child)


static func _apply_season_beach_wet(
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
		_tile_to_atlas(season_tex, target, false, true) if target != Vector2i.ZERO else season_tex
	)
	sh.set_shader_parameter("albedo_texture", tiled)
	mesh_instance.set_surface_override_material(surface, sh)
	return true


static func _season_tile_clamp_v(role: String) -> bool:
	## River banks and cliff fringes sample GX_CLAMP T; grass stays REPEAT/REPEAT.
	return role in ["earth", "river_edge", "bush_a", "bush_b", "sand", "stone", "cliff", "rail"]


static func refresh_window_lights(root: Node) -> void:
	## `mEnv_NPC_LIGHTS_*`: panes and ground spill 18:00–05:00.
	_set_window_lights(root, _window_lights_on())


static func refresh_room_prim(root: Node, color: Color = Color.WHITE) -> void:
	## `Global_kankyo_set_room_prim` — indoor outdoor-view quads use room prim RGB.
	if root == null:
		return
	if color.a <= 0.0:
		color = _room_prim_color()
	_set_room_prim_fills(root, color)


static func room_prim_color() -> Color:
	return _room_prim_color()


static func water_wave_cos(game_frame: float) -> float:
	## `aFD_MakeMarinScrollInfo`: cos((game_frame % 300) / 300 * 2π).
	var frame: float = fmod(game_frame, 300.0)
	return cos(frame / 300.0 * TAU)


static func beach_env_srgb(game_frame: float) -> Color:
	## Same cosine as ocean, phase −1.2. 8-bit ENV / 255, not linearized.
	var beach_cos: float = cos(fmod(game_frame, 300.0) / 300.0 * TAU - 1.2)
	return Color(
		(144.0 + (beach_cos * -21.0 + 21.0)) / 255.0,
		(128.0 + (beach_cos * -18.0 + 18.0)) / 255.0,
		(96.0 + (beach_cos * -14.0 + 14.0)) / 255.0
	)


static func attach_villager(host: Node3D, species: StringName, fit_actor: bool = true) -> Node3D:
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
	if fit_actor:
		_fit_actor(pivot)
	return pivot


static func apply_actor_scale(pivot: Node3D, visual_id: StringName = &"") -> void:
	## GX→meter scale without standing foot snap (sleep / sit poses).
	if pivot == null:
		return
	var s: float = FieldCatalog.actor_uniform_scale_for(visual_id)
	pivot.scale = Vector3.ONE * s


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
			var label := _surface_label(mi, i, mi.get_active_material(i))
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
	_mark_shell_room_prim(pivot)
	refresh_room_prim(pivot)
	_fit_interior(pivot, target, StringName(shell_ids[0]))
	_disable_shadows(pivot)
	return pivot


static func _fit(pivot: Node3D, visual_id: StringName) -> void:
	if _is_light_shaft_visual(visual_id):
		## Skylight shafts are authored in acre space alongside the museum shell.
		_fit_acre(pivot)
		return
	if FieldCatalog.is_acre(visual_id) or visual_id == &"obj_museum5":
		## `obj_museum5` draws with field `Matrix_scale(0.0625)` and no translate —
		## verts share the acre datum with `rom_museum5` (floor at authored Y=40 GX).
		_fit_acre(pivot)
		return
	if FieldCatalog.is_ground_decal(visual_id):
		_fit_ground_decal(pivot)
		return
	_fit_actor(pivot, visual_id)


static func fit_acre(pivot: Node3D) -> void:
	## Same scale and origin for every `grd_*` so neighbors share edges and the land datum.
	if pivot == null:
		return
	var s: float = FieldCatalog.acre_uniform_scale()
	pivot.scale = Vector3.ONE * s
	pivot.position = Vector3(0.0, FieldCatalog.acre_ground_y_offset(), 0.0)


static func _fit_acre(pivot: Node3D) -> void:
	fit_acre(pivot)


static func align_actor_to_height_gx(pivot: Node3D, height_gx: float) -> void:
	## Place the model's lowest rest-pose vertex on a GX height (standing feet, etc.).
	if pivot == null:
		return
	var aabb: AABB = local_aabb(pivot)
	if aabb.size == Vector3.ZERO:
		return
	var s: float = pivot.scale.y
	pivot.position.y = height_gx * FieldCatalog.GX_TO_METERS - aabb.position.y * s


static func align_actor_world_min_to_height_gx(pivot: Node3D, height_gx: float) -> void:
	## Snap the posed world-space mesh min-Y onto a GX height. Use for clips whose rest
	## AABB spikes (sleep poses) would lift the body off the bench.
	if pivot == null:
		return
	var box: AABB = _world_aabb_named(pivot, "")
	if box.size == Vector3.ZERO:
		return
	pivot.position.y += height_gx * FieldCatalog.GX_TO_METERS - box.position.y


static func local_aabb(node: Node) -> AABB:
	return _local_aabb(node)


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
	## Snap the mesh rest onto the host origin. Museum art hosts sit at
	## `aMP_DrawOneArt` Y=40 GX, so this puts the frame bottom on the hang line
	## (pipeline verts start ~10 GX above local 0).
	if min_y > -0.5 and min_y < 2.0:
		pivot.position.y = -min_y * s


static func _fit_ground_decal(pivot: Node3D) -> void:
	## Keep authored Y. AABB-snapping a coplanar fan onto the acre z-fights with grass.
	pivot.scale = Vector3.ONE * FieldCatalog.actor_uniform_scale()


static func fit_train_car_shell(pivot: Node3D) -> void:
	## `rom_train_in` BG DLs use 16× acre verts + `Matrix_scale(0.0625)` (`ac_field_draw`).
	var s: float = FieldCatalog.acre_uniform_scale()
	pivot.scale = Vector3.ONE * s
	var aabb: AABB = _local_aabb(pivot)
	if aabb.size.y > 0.001:
		pivot.position = Vector3(0.0, -aabb.position.y * s, 0.0)
	else:
		pivot.position = Vector3(0.0, FieldCatalog.interior_ground_y_offset(&"rom_train_in"), 0.0)


static func fit_train_window_shell(pivot: Node3D, car_pivot: Node3D = null) -> void:
	## `rom_train_out` uses raw GX verts + `Matrix_scale(0.05)` (`ac_train_window`) → world GX,
	## then `GX_TO_METERS` like actors / acre shells.
	## Decomp draws car BG and window actor at the same translate(0,0,0). Reuse the car's
	## floor snap so we do not independently raise scenery ~20 GX into the panes.
	var s: float = FieldCatalog.train_window_uniform_scale()
	pivot.scale = Vector3.ONE * s
	if car_pivot != null:
		pivot.position = Vector3(0.0, car_pivot.position.y, 0.0)
	else:
		pivot.position = Vector3.ZERO


static func apply_train_door_materials(node: Node) -> void:
	## Match `rom_train_in` OPA + glass rules so the vestibule door reads like the car shell.
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			return
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var node_label := String(mesh_instance.name).to_lower()
		for i: int in mesh_instance.mesh.get_surface_count():
			var mat: Material = mesh_instance.get_active_material(i)
			if not mat is StandardMaterial3D:
				continue
			var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			## Mesh is often `obj_romtrain_door`; glass is the surface / material name.
			var label := _surface_label(mesh_instance, i, mat).to_lower()
			if label.is_empty():
				label = node_label
			if "glass" in label:
				IntroTrainPresentation._apply_glass_surface(std)
			else:
				std.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				std.roughness = 1.0
				std.metallic = 0.0
				std.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				std.emission_enabled = false
				if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
					std.alpha_scissor_threshold = maxf(std.alpha_scissor_threshold, 0.5)
			mesh_instance.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		apply_train_door_materials(child)


static func place_train_door_at_gateway(
	host: Node3D,
	pivot: Node3D,
	gateway_gx: Vector3,
	car_pivot: Node3D = null,
	panel_z_bias_gx: float = 0.0
) -> void:
	## `obj_romtrain_door` is an actor — `gateway_gx` is the decomp spawn origin. When
	## `car_pivot` is set, nudge Z so the closed door frame lines up with `rom_train_in`'s
	## vestibule jambs; `panel_z_bias_gx` recesses toward the deck (negative = smaller Z).
	if host == null or pivot == null:
		return
	host.global_transform = Transform3D.IDENTITY
	host.global_position = gateway_gx * FieldCatalog.GX_TO_METERS
	if car_pivot == null:
		return
	var opening_z: float = _train_vestibule_opening_z_gx(car_pivot)
	if opening_z <= 0.0:
		return
	var panel_z: float = train_door_panel_center_gx(host, pivot).z
	host.global_position.z += (opening_z + panel_z_bias_gx - panel_z) * FieldCatalog.GX_TO_METERS


static func train_vestibule_opening_z_gx(car_pivot: Node3D) -> float:
	return _train_vestibule_opening_z_gx(car_pivot)


static func _train_vestibule_opening_z_gx(car_pivot: Node3D) -> float:
	## Mid-Z of `rom_train_in` verts in the vestibule cutout near aisle x=140.
	if car_pivot == null:
		return 0.0
	var zs: Array[float] = []
	_collect_train_vestibule_z(car_pivot, car_pivot.global_transform, zs)
	if zs.is_empty():
		return 0.0
	zs.sort()
	return zs[zs.size() / 2] / FieldCatalog.GX_TO_METERS


static func _collect_train_vestibule_z(node: Node, xf: Transform3D, zs: Array[float]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			return
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			return
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			var w: Vector3 = xf * v
			var x_gx: float = w.x / FieldCatalog.GX_TO_METERS
			if x_gx < 115.0 or x_gx > 165.0:
				continue
			var z_gx: float = w.z / FieldCatalog.GX_TO_METERS
			if z_gx < 118.0 or z_gx > 132.0:
				continue
			var y_gx: float = w.y / FieldCatalog.GX_TO_METERS
			if y_gx < 10.0 or y_gx > 75.0:
				continue
			zs.append(w.z)
	for child: Node in node.get_children():
		if child is Node3D:
			_collect_train_vestibule_z(child, xf * (child as Node3D).transform, zs)


static func train_door_panel_center_gx(host: Node3D, pivot: Node3D) -> Vector3:
	if pivot == null:
		return Vector3.ZERO
	var panel: AABB = _world_aabb_named(pivot, "door")
	if panel.size == Vector3.ZERO:
		panel = _world_aabb_named(pivot, "")
	if panel.size == Vector3.ZERO:
		return Vector3.ZERO
	return panel.get_center() / FieldCatalog.GX_TO_METERS


static func _fit_interior(pivot: Node3D, target: AABB, visual_id: StringName) -> void:
	## `room01` verts are raw GX (max Z 320 = 8 units). Place at the field origin
	## with GX→meter scale so FG cells (1,1)–(6,6) sit on the floor. Do not AABB-fit.
	## Acre-style shells (`rom_*`, `police_indoor`, `grd_post_office`) stay at acre scale
	## (40 GX = 2 m). Homes translate the floor min-corner onto the walkable rect.
	## Museum / Nook / post / police keep the 16×16 acre origin so FG ut / RSV / door GX
	## match `cell_to_world` — only Y is snapped to the floor.
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
	if _shell_keeps_acre_origin(visual_id):
		pivot.position = Vector3(target.position.x, -aabb.position.y * s, target.position.z)
		return
	pivot.position = Vector3(
		target.position.x - aabb.position.x * s,
		-aabb.position.y * s,
		target.position.z - aabb.position.z * s
	)


static func _shell_keeps_acre_origin(visual_id: StringName) -> bool:
	var id := String(visual_id)
	return (
		id.begins_with("rom_museum")
		or id.begins_with("rom_shop")
		or id == "rom_tailor"
		or id == "police_indoor"
		or id == "grd_post_office"
	)


static func _interior_keeps_acre_origin(visual_id: StringName, room: Room) -> bool:
	return room.kind == Room.Kind.MUSEUM or _shell_keeps_acre_origin(visual_id)


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
			if (
				_is_window_spill_surface(mesh_instance, i, src)
				or _is_window_pane_surface(mesh_instance, i, src)
				or _is_river_water_surface(mesh_instance, i, src)
				or _is_ocean_water_surface(mesh_instance, i, src)
				or _is_splash_water_surface(mesh_instance, i, src)
				or _is_beach_wet_surface(mesh_instance, i, src)
			):
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
			if _is_vertex_shade_surface(mesh_instance, i, src_mat):
				_apply_vertex_shade_material(std)
			else:
				std.vertex_color_use_as_albedo = false
			var target: Vector2i = _albedo_size(std)
			## Floors use GX_MIRROR (corner tile → one room medallion). Walls REPEAT.
			## Bank pages are always 64². Do not infer period from a MIRROR atlas —
			## odd cells are flipped so `_image_has_period(64)` fails and 128 wins,
			## stretching stone/wallpaper 2× across the shell.
			var mirror := kind == &"floor"
			std.albedo_texture = _tile_to_atlas(tile, target, mirror, mirror, 64)
			## `Global_kankyo_set_room_prim`: TEXEL × SHADE × PRIM on indoor shells.
			std.albedo_color = _room_prim_color()
			std.set_meta("room_prim_surface", true)
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
	tile: Texture2D,
	target: Vector2i,
	mirror_u: bool = false,
	mirror_v: bool = false,
	tile_size: int = 0
) -> Texture2D:
	## Pipeline wrap-bake expands a bank tile into an atlas and remaps UVs to 0–1.
	## Swapping a single tile without re-tiling makes wallpapers look glitchy.
	## Room floors are GX_MIRROR (odd cells flipped) so a corner tile becomes one medallion.
	if tile == null:
		return null
	if target.x <= 0 or target.y <= 0:
		return tile
	var src: Image = _texture_image(tile)
	if src == null:
		return tile
	## Bank pages are 64×64. Field capped ACHD tiles are 128²; tree leaf/trunk may
	## be full ACHD (512²). Only shrink when the season sheet is not an exact
	## atlas cell (room wallpaper HD / stale pack mismatch).
	const BANK_TILE := 64
	var cell: int = tile_size
	if cell <= 0:
		var sw: int = src.get_width()
		var sh: int = src.get_height()
		var exact_cell := (
			sw > 0
			and sh > 0
			and target.x % sw == 0
			and target.y % sh == 0
		)
		if (
			not exact_cell
			and sw == sh
			and sw > BANK_TILE
			and (mirror_u or mirror_v or target.x < sw or target.y < sh)
		):
			cell = BANK_TILE
		else:
			cell = 0
	if cell > 0 and (src.get_width() != cell or src.get_height() != cell):
		src = src.duplicate()
		src.resize(cell, cell, Image.INTERPOLATE_NEAREST)
	var tw: int = src.get_width()
	var th: int = src.get_height()
	if tw <= 0 or th <= 0:
		return tile
	if tw == target.x and th == target.y and not mirror_u and not mirror_v:
		return ImageTexture.create_from_image(src)
	var out := Image.create(target.x, target.y, false, Image.FORMAT_RGBA8)
	var tiles_u: int = maxi(1, int(ceili(float(target.x) / float(tw))))
	var tiles_v: int = maxi(1, int(ceili(float(target.y) / float(th))))
	for tj: int in tiles_v:
		for ti: int in tiles_u:
			var patch: Image = src
			var flip_u := mirror_u and (ti & 1) == 1
			var flip_v := mirror_v and (tj & 1) == 1
			if flip_u or flip_v:
				patch = src.duplicate()
				if flip_u:
					patch.flip_x()
				if flip_v:
					patch.flip_y()
			out.blit_rect(patch, Rect2i(0, 0, tw, th), Vector2i(ti * tw, tj * th))
	if out.get_width() != target.x or out.get_height() != target.y:
		out = out.get_region(Rect2i(0, 0, target.x, target.y))
	return ImageTexture.create_from_image(out)


static func _infer_atlas_tile_size(atlas: Texture2D, fallback: int = 64) -> int:
	## Smallest period that tiles the wrap-bake atlas (shop wall DMA is 64²).
	var img: Image = _texture_image(atlas)
	if img == null:
		return fallback
	var w: int = img.get_width()
	var h: int = img.get_height()
	## Prefer the smallest period that actually repeats (≥2 cells on an axis).
	for period: int in [32, 64, 128, 256]:
		if period > mini(w, h):
			continue
		if w % period != 0 or h % period != 0:
			continue
		if w < period * 2 and h < period * 2:
			continue
		if _image_has_period(img, period):
			return period
	return fallback


static func _image_has_period(img: Image, period: int) -> bool:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if period <= 0 or w % period != 0 or h % period != 0:
		return false
	## Sample a sparse grid — full compare is expensive on large atlases.
	if w >= period * 2:
		for y: int in range(0, h, maxi(period / 8, 1)):
			for x: int in range(0, w - period, maxi(period / 8, 1)):
				if img.get_pixel(x, y) != img.get_pixel(x + period, y):
					return false
	if h >= period * 2:
		for x: int in range(0, w, maxi(period / 8, 1)):
			for y: int in range(0, h - period, maxi(period / 8, 1)):
				if img.get_pixel(x, y) != img.get_pixel(x, y + period):
					return false
	return w >= period * 2 or h >= period * 2



static func _room_surface_kind(mesh_instance: MeshInstance3D, surface: int) -> StringName:
	## Empty → leave the baked shell texture (window, exit trim, props).
	## Prefer the GLB material; runtime overrides drop the `rom_myhome_window_tex` name.
	var baked: Material = null
	if mesh_instance.mesh != null:
		baked = mesh_instance.mesh.surface_get_material(surface)
	var mat: Material = baked if baked != null else mesh_instance.get_active_material(surface)
	return _classify_room_surface(_surface_label(mesh_instance, surface, mat))


static func _classify_room_surface(label: String) -> StringName:
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


static func _apply_materials(
	node: Node, as_decal: bool = false, keep_imported: bool = false, visual_id: StringName = &""
) -> void:
	_apply_materials_inner(node, as_decal, _tree_has_splash_water(node), keep_imported, visual_id)


static func _apply_materials_inner(
	node: Node, as_decal: bool, mouth_river: bool, keep_imported: bool, visual_id: StringName = &""
) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat == null:
				mat = StandardMaterial3D.new()
			if mat is StandardMaterial3D:
				var src := mat
				if keep_imported and not (
					_is_river_water_surface(mesh_instance, i, src)
					or _is_ocean_water_surface(mesh_instance, i, src)
					or _is_splash_water_surface(mesh_instance, i, src)
					or _is_waterfall_water_surface(mesh_instance, i, src)
					or _is_fall_rainbow_surface(mesh_instance, i, src)
					or _is_beach_wet_surface(mesh_instance, i, src)
				):
					## Ocean-acre land stays imported; river/splash/wet-sand still get shaders.
					continue
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
				if _is_vertex_shade_surface(mesh_instance, i, src):
					_apply_vertex_shade_material(std)
				else:
					std.vertex_color_use_as_albedo = false
				if _is_window_spill_surface(mesh_instance, i, src):
					mesh_instance.set_surface_override_material(i, _make_window_spill_material(std))
				elif _is_window_pane_surface(mesh_instance, i, src):
					_apply_window_pane_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif _is_room_prim_fill_surface(mesh_instance, i, src):
					_apply_room_prim_fill_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif _is_splash_water_surface(mesh_instance, i, src):
					mesh_instance.set_surface_override_material(i, _make_splash_water_material(std))
				elif _is_river_water_surface(mesh_instance, i, src):
					mesh_instance.set_surface_override_material(
						i, _make_river_water_material(std, mouth_river)
					)
				elif _is_ocean_water_surface(mesh_instance, i, src):
					mesh_instance.set_surface_override_material(
						i, _make_ocean_water_material(std, src)
					)
				elif _is_waterfall_water_surface(mesh_instance, i, src):
					mesh_instance.set_surface_override_material(
						i, _make_waterfall_water_material(std, src, mesh_instance, i)
					)
				elif _is_fall_rainbow_surface(mesh_instance, i, src):
					mesh_instance.set_surface_override_material(i, _make_fall_rainbow_material())
				elif _is_beach_wet_surface(mesh_instance, i, src):
					mesh_instance.set_surface_override_material(
						i, _make_beach_wet_material(std, mesh_instance, i, src)
					)
				elif _is_player_select_spot_surface(mesh_instance, i, src):
					_apply_player_select_spot_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif _is_player_select_shade_surface(mesh_instance, i, src):
					_apply_player_select_shade_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif _is_kanban_paper_surface(mesh_instance, i, src, visual_id):
					_apply_kanban_paper_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif _is_kanban_frame_surface(mesh_instance, i, src, visual_id):
					_apply_kanban_frame_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif _is_museum_art_surface(mesh_instance, i, src, visual_id):
					_apply_museum_art_material(std)
					mesh_instance.set_surface_override_material(i, std)
				elif _is_light_shaft_visual(visual_id):
					_apply_light_shaft_surface(std)
					mesh_instance.set_surface_override_material(i, std)
				elif _is_fish_tank_visual(visual_id):
					_apply_fish_tank_surface(std, _surface_label(mesh_instance, i, src))
					mesh_instance.set_surface_override_material(i, std)
				elif _is_single_sided_shell_visual(visual_id):
					std.cull_mode = BaseMaterial3D.CULL_BACK
					mesh_instance.set_surface_override_material(i, std)
				elif HostCollision.uses_structure_offset(visual_id):
					_apply_structure_surface(std)
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
					_harden_imported_cutout(std)
					var field_role := FieldCatalog.season_role_for_surface(mesh_instance, i, src)
					if not field_role.is_empty():
						std.set_meta("field_role", field_role)
					mesh_instance.set_surface_override_material(i, std)
		if as_decal:
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh_instance.sorting_offset = 1.0
	for child in node.get_children():
		_apply_materials_inner(child, as_decal, mouth_river, keep_imported, visual_id)


static func _harden_imported_cutout(std: StandardMaterial3D) -> void:
	## Match structure TEX_EDGE: scissor + depth write so transparent water cannot
	## overdraw ears/faces whose soft BLEND fringe left holes in the depth buffer.
	if std.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
		return
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	std.alpha_scissor_threshold = maxf(std.alpha_scissor_threshold, 0.5)
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY


static func _is_light_shaft_visual(visual_id: StringName) -> bool:
	## Museum skylight god-rays (`obj_museum1_shine` / `obj_museum4_shine`).
	var s := String(visual_id)
	return s.begins_with("obj_museum") and s.ends_with("_shine")


## Soft translucent light cone: unshaded, additive-ish MIX, no depth write, daylight-gated.
static func _apply_light_shaft_surface(std: StandardMaterial3D) -> void:
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


static func _is_single_sided_shell_visual(visual_id: StringName) -> bool:
	## `ac_mailbox`: `inside1_tex` is the exact same wall quad as `side1_tex`, authored
	## with reversed winding (verified against the ROM's own vertex data) — GX fakes
	## "visible from both sides" with two coincident single-sided polys, not blending.
	## The pipeline's blanket `doubleSided: true` (`glb.py::_material`, needed for most
	## structures) draws both at once here and z-fights; force single-sided back-cull so
	## only the poly actually facing the camera renders, matching the original GX result.
	return visual_id == &"obj_s_post" or visual_id == &"obj_w_post"


static func _is_fish_tank_visual(visual_id: StringName) -> bool:
	## Small tanks + sea tank: OPA shell, TEX_EDGE frame, XLU glass/water.
	return visual_id == &"obj_suisou1" or visual_id == &"obj_museum5"


static func _apply_fish_tank_surface(std: StandardMaterial3D, label: String = "") -> void:
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


static func _apply_structure_surface(std: StandardMaterial3D) -> void:
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


static func _is_museum_art_surface(
	_mesh_instance: MeshInstance3D, _surface: int, _mat: Material, visual_id: StringName
) -> bool:
	return _is_museum_art_visual(visual_id)


static func _apply_museum_art_material(std: StandardMaterial3D) -> void:
	## `aMP_DrawOneArt` draws on POLY_OPA (`G_RM_AA_ZB_OPA_SURF2`). Alpha mode is pipeline-owned.
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY


static func _is_kanban_paper_surface(
	mesh_instance: MeshInstance3D, surface: int, mat: Material, visual_id: StringName
) -> bool:
	if not _is_kanban_visual(visual_id):
		return false
	if not (mat is StandardMaterial3D):
		return false
	var label := _surface_label(mesh_instance, surface, mat)
	return (
		"my_original" in label
		or "hakushi" in label
		or (mat as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
		and "kanban_base" not in label
		and surface == 0
	)


static func _is_kanban_frame_surface(
	mesh_instance: MeshInstance3D, surface: int, mat: Material, visual_id: StringName
) -> bool:
	if not _is_kanban_visual(visual_id):
		return false
	if not (mat is StandardMaterial3D):
		return false
	var label := _surface_label(mesh_instance, surface, mat)
	return "kanban_base" in label or surface == 1


static func _apply_kanban_paper_material(std: StandardMaterial3D) -> void:
	## `write_model` draws first as a decal (`G_DECAL_LEQUAL`); do not win depth over the frame.
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.render_priority = 0


static func _apply_kanban_frame_material(std: StandardMaterial3D) -> void:
	## `obj_sign_{s,w}_model` masks wood over the paper (`G_RM_AA_ZB_TEX_EDGE2`).
	std.render_priority = 1
	if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		std.alpha_scissor_threshold = maxf(std.alpha_scissor_threshold, 0.5)


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


static func stop_autoplay(node: Node) -> void:
	## Furniture cKF clips are open/close; rest is frame 1 (closed). Do not play.
	var anim: AnimationPlayer = find_animation_player(node)
	if anim == null:
		return
	anim.autoplay = ""
	anim.stop()
	anim.seek(0.0, true)


static func stop_autoplay_keep_rest(node: Node) -> void:
	## Outdoor trains bake a non-bind `joint_0` translation into every clip frame.
	## Seeking frame 0 would shove the car off the rails — stop and snap to bind.
	var anim: AnimationPlayer = find_animation_player(node)
	if anim != null:
		anim.autoplay = ""
		anim.stop()
	reset_skeleton_rest(node)


static func prepare_outdoor_train(node: Node) -> void:
	## Trains bake anim-bind (+ joint-0 rest) with `ckf_basis` — upright, long on +X.
	## Stop autoplay so wheel/door clips do not run until the stage asks; strip
	## `joint_0` tracks so those clips cannot shove the whole car off the rails.
	## Keep skinning so caboose door open can deform the door joints.
	## `*_close` frame 1 is open (clip runs open→closed); snap doors shut for approach.
	stop_autoplay_keep_rest(node)
	var anim: AnimationPlayer = find_animation_player(node)
	strip_named_joint_tracks(anim, "joint_0")
	snap_train_doors_closed(anim)


static func snap_train_doors_closed(anim_player: AnimationPlayer) -> void:
	## Decomp actions 0–3: `obj_train1_3_open` frozen at frame 1 (closed), speed 0.
	## Prefer open@0 over close@end — same pose, matches `aTR1_setupAction`.
	## Keep the clip "playing" at speed 0 so the seeked pose sticks (pause/stop clears it).
	if anim_player == null:
		return
	for name: String in ["obj_train1_3_open", "open"]:
		if not anim_player.has_animation(name):
			continue
		var animation: Animation = anim_player.get_animation(name)
		if animation != null:
			animation.loop_mode = Animation.LOOP_NONE
		anim_player.play(name)
		anim_player.seek(0.0, true)
		anim_player.speed_scale = 0.0
		return
	for name: String in ["obj_train1_3_close", "close"]:
		if not anim_player.has_animation(name):
			continue
		var animation: Animation = anim_player.get_animation(name)
		if animation == null:
			return
		animation.loop_mode = Animation.LOOP_NONE
		anim_player.play(name)
		anim_player.seek(animation.length, true)
		anim_player.speed_scale = 0.0
		return


static func disable_skinning(node: Node) -> void:
	## Render the authored bind-shape mesh; ignore Skeleton3D / Skin.
	if node == null:
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.skin = null
		mi.skeleton = NodePath()
	for child in node.get_children():
		disable_skinning(child)


static func reset_skeleton_rest(node: Node) -> void:
	## Clear AnimationPlayer pose and snap every Skeleton3D back to bind.
	if node == null:
		return
	if node is Skeleton3D:
		(node as Skeleton3D).reset_bone_poses()
	for child in node.get_children():
		reset_skeleton_rest(child)


static func strip_named_joint_tracks(
	anim_player: AnimationPlayer,
	joint_name: String = "joint_0",
	clip_names: PackedStringArray = PackedStringArray(),
) -> void:
	## Drop position/rotation tracks on `joint_name` so door/wheel clips cannot move the root.
	## When `clip_names` is set, only those animations (exact or suffix match) are edited.
	if anim_player == null or joint_name.is_empty():
		return
	var needle := ":%s:" % joint_name
	var needle_end := ":%s" % joint_name
	for clip_name: String in anim_player.get_animation_list():
		if not clip_names.is_empty() and not _clip_name_matches(clip_name, clip_names):
			continue
		var animation: Animation = anim_player.get_animation(clip_name)
		if animation == null:
			continue
		for track_i: int in range(animation.get_track_count() - 1, -1, -1):
			var path := String(animation.track_get_path(track_i))
			if path.contains(needle) or path.ends_with(needle_end):
				animation.remove_track(track_i)


static func _clip_name_matches(clip_name: String, names: PackedStringArray) -> bool:
	for want: String in names:
		if want.is_empty():
			continue
		if clip_name == want or clip_name.ends_with("/" + want) or clip_name.ends_with(want):
			return true
	return false


static func _stop_autoplay(node: Node) -> void:
	stop_autoplay(node)


static func _is_window_spill_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	## Prefer glTF extras from pipeline (XLU decal); legacy name match for older GLBs.
	if bool(_gltf_extras(mat).get("ground_spill", false)):
		return true
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
	## Opaque prim fill in wall TEX_EDGE holes. Outdoor-view uses bright unlit prim.
	var n := _surface_label(mesh_instance, surface, mat).to_lower()
	if n.contains("light_model") or n.contains("lightt_model"):
		return true
	if bool(_gltf_extras(mat).get("unlit_fill", false)):
		if mat is StandardMaterial3D:
			var c: Color = (mat as StandardMaterial3D).albedo_color
			## Outdoor sky fill is near-white; facade panes are black.
			return c.r + c.g + c.b < 1.5
		return true
	return false


static func _is_room_prim_fill_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	## Indoor `rom_*` outdoor-view quads (`G_CC_PRIMITIVE` after window MASK).
	## Bright unlit_fill — not facade night panes.
	if not bool(_gltf_extras(mat).get("unlit_fill", false)):
		return false
	if _is_window_pane_surface(mesh_instance, surface, mat):
		return false
	return true


static func _gltf_extras(mat: Material) -> Dictionary:
	if mat == null:
		return {}
	for key: String in ["extras", "gltf_extras"]:
		if mat.has_meta(key):
			var extras: Variant = mat.get_meta(key)
			if extras is Dictionary:
				return extras as Dictionary
	return {}


static func _surface_has_vertex_colors(mesh_instance: MeshInstance3D, surface: int) -> bool:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null or surface < 0 or surface >= mesh.get_surface_count():
		return false
	var arrays: Array = mesh.surface_get_arrays(surface)
	if arrays.is_empty():
		return false
	return arrays[Mesh.ARRAY_COLOR] != null


static func _is_vertex_shade_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	## Indoor shells: TEXEL0 × SHADE with G_LIGHTING off (ceiling AO in Vtx.cn[]).
	if bool(_gltf_extras(mat).get("vertex_shade", false)):
		return true
	return _surface_has_vertex_colors(mesh_instance, surface)


static func _apply_vertex_shade_material(std: StandardMaterial3D) -> void:
	std.vertex_color_use_as_albedo = true
	## Original BG DLs skip LightsN; keep the baked shade band free of Godot lights.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


static func _water_kind(mat: Material) -> String:
	return str(_gltf_extras(mat).get("water_kind", ""))


static func _is_river_water_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	## Prefer glTF extras; fall back to XLU name `river_mFM_grd_water1_tex` (not OPA `…river_tex`).
	if _water_kind(mat) == "river":
		return true
	var n := _surface_label(mesh_instance, surface, mat).to_lower()
	return n.contains("river_mfm_grd_water") or n.contains("grd_water1")


static func _is_ocean_water_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	if _water_kind(mat) == "ocean":
		return true
	var n := _surface_label(mesh_instance, surface, mat).to_lower()
	return n.contains("ocean_") or (n.contains("wave") and not n.contains("waterfall"))


static func _is_splash_water_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	## River-mouth connector: `mFM_grd_sprashC` + `sprashA` (decomp spelling).
	if _water_kind(mat) == "splash":
		return true
	var n := _surface_label(mesh_instance, surface, mat).to_lower()
	return n.contains("sprash") or n.contains("splash")


static func _is_waterfall_water_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	if _water_kind(mat) == "waterfall":
		return true
	var n := _surface_label(mesh_instance, surface, mat).to_lower()
	return n.contains("waterfall_") or (n.contains("fall") and n.contains("grp"))


## `obj_fallS_rainbowT_model` (`ac_fallS_draw.c_inc`): only drawn when
## `Common_Get(rainbow_opacity) > 0` — a billboarded, alpha-faded arc that shows up
## after it rains. We don't track that weather state, so the baked-in decal has to
## default to invisible rather than a permanent, wrongly-shaped arc hanging over the
## falls. Name-free: every OTHER surface sharing this mesh with a `waterfall`-tagged
## layer is one of the 4 grpAT/BT/CT/DT scrolling sheets — a sibling surface that
## itself carries no water classification is the leftover rainbow.
static func _is_fall_rainbow_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	if _water_kind(mat) != "":
		return false
	var n: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 0
	for j: int in n:
		if j == surface:
			continue
		var sibling: Material = mesh_instance.get_active_material(j)
		if sibling != null and _water_kind(sibling) == "waterfall":
			return true
	return false


static func _make_fall_rainbow_material() -> StandardMaterial3D:
	var std := StandardMaterial3D.new()
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	std.cull_mode = BaseMaterial3D.CULL_DISABLED
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.render_priority = -1
	std.set_meta("fall_rainbow", true)
	return std


static func _tree_has_splash_water(node: Node) -> bool:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat != null and _is_splash_water_surface(mesh_instance, i, mat):
				return true
	for child in node.get_children():
		if _tree_has_splash_water(child):
			return true
	return false


static func _tree_is_ocean_acre(node: Node) -> bool:
	## Detect `grd_*_m_*` / `grd_*_o_*` from instanced scene paths / node names.
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if FieldCatalog.is_ocean_acre_visual(StringName(n.name)):
			return true
		var path := String(n.scene_file_path).to_lower()
		if not path.is_empty():
			var stem := path.get_file().get_basename()
			if FieldCatalog.is_ocean_acre_visual(StringName(stem)):
				return true
		for child in n.get_children():
			stack.append(child)
	return false


static func _is_beach_wet_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	if _water_kind(mat) == "beach_wet":
		return true
	var n := _surface_label(mesh_instance, surface, mat).to_lower()
	return (
		n.contains("beach_wet")
		or n.contains("beacha")
		or n.contains("beachb")
		or n.contains("beach1")
		or n.contains("beach2")
	)


static func _is_player_select_spot_surface(
	mesh_instance: MeshInstance3D, surface: int, mat: Material
) -> bool:
	return "rom_open_spot" in _surface_label(mesh_instance, surface, mat).to_lower()


static func _is_player_select_shade_surface(
	mesh_instance: MeshInstance3D, surface: int, mat: Material
) -> bool:
	return "rom_open_shade" in _surface_label(mesh_instance, surface, mat).to_lower()


static func _apply_player_select_spot_material(std: StandardMaterial3D) -> void:
	## Baked yellow cone XLU (`grd_player_select_modelT`). GC uses RDP combine + EVW
	## scroll on spot2 — not a programmable shader; keep the imported bake.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.vertex_color_use_as_albedo = false
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	std.texture_repeat = false
	std.set_meta("player_select_spot", true)


static func _apply_player_select_shade_material(std: StandardMaterial3D) -> void:
	## Shade curtain: black prim × I alpha. Wrap-baked like the spot.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.vertex_color_use_as_albedo = false
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	std.texture_repeat = false
	std.set_meta("player_select_shade", true)


static func _layer1_texture(std: StandardMaterial3D) -> Texture2D:
	if std.ao_texture != null:
		return std.ao_texture
	if std.emission_texture != null:
		return std.emission_texture
	return std.albedo_texture


static func _make_river_water_material(std: StandardMaterial3D, mouth: bool = false) -> ShaderMaterial:
	## Decomp grd_*_modelT: prim (255,255,255,50) lod=50; env inland (0,100,255) / mouth (0,60,255).
	var sh := ShaderMaterial.new()
	sh.shader = _RIVER_WATER_SHADER
	sh.render_priority = 1
	var water1: Texture2D = std.albedo_texture
	var water2: Texture2D = _layer1_texture(std)
	if water2 == null or water2 == water1:
		push_warning("GeneratedVisual: river water2 missing; dual scroll will look wrong")
	sh.set_shader_parameter("water1", water1)
	sh.set_shader_parameter("water2", water2)
	sh.set_shader_parameter("env_color", _RIVER_ENV_MOUTH if mouth else _RIVER_ENV_INLAND)
	sh.set_shader_parameter("prim_color", Color(1.0, 1.0, 1.0, 50.0 / 255.0))
	sh.set_shader_parameter("game_fps", 180.0)
	sh.set_shader_parameter("ground_lift", FieldCatalog.GX_TO_METERS * 0.5)
	sh.set_meta("river_water", true)
	return sh


static func _make_ocean_water_material(std: StandardMaterial3D, src: Material) -> ShaderMaterial:
	## Decomp grd_*_modelT XLU: prim (60,120,255); wave1 × wave2/wave3 IA8 pair.
	var sh := ShaderMaterial.new()
	sh.shader = _OCEAN_WATER_SHADER
	## Above the opaque beachB bed, below the river-mouth sprash.
	sh.render_priority = 1
	var wave1: Texture2D = std.albedo_texture
	var wave2: Texture2D = _layer1_texture(std)
	if wave2 == null or wave2 == wave1:
		push_warning("GeneratedVisual: ocean tile1 missing; wave crests will look wrong")
	sh.set_shader_parameter("wave1", wave1)
	sh.set_shader_parameter("wave2", wave2)
	sh.set_shader_parameter("prim_color", Color(60.0 / 255.0, 120.0 / 255.0, 1.0, 1.0))
	sh.set_shader_parameter("game_fps", 180.0)
	sh.set_shader_parameter("ground_lift", FieldCatalog.GX_TO_METERS * 0.5)
	## Shore band tile1 is wave2 with GX_CLAMP T; open water is wave3 REPEAT.
	sh.set_shader_parameter(
		"wave2_clamp_v", 1.0 if bool(_gltf_extras(src).get("wave2_clamp_t", false)) else 0.0
	)
	sh.set_meta("ocean_water", true)
	return sh


static func _waterfall_layer_index(
	mat: Material, mesh_instance: MeshInstance3D, surface: int
) -> int:
	var layer := str(_gltf_extras(mat).get("waterfall_layer", "")).to_lower()
	match layer:
		"at":
			return 0
		"bt":
			return 1
		"ct":
			return 2
		"dt":
			return 3
	## GLBs converted before `waterfall_layer` extras: grpAT..DT match primitive order.
	var label := _surface_label(mesh_instance, surface, mat).to_lower()
	if label.contains("grpat"):
		return 0
	if label.contains("grpct"):
		return 2
	if label.contains("grpdt"):
		return 3
	if label.contains("grpbt"):
		return 1
	if mesh_instance.mesh is ArrayMesh and surface >= 0 and surface <= 3:
		return surface
	return 1


static func _make_waterfall_water_material(
	std: StandardMaterial3D, src: Material, mesh_instance: MeshInstance3D, surface: int
) -> ShaderMaterial:
	## Decomp obj_fallS grpAT/BT/CT/DT — dual-scroll EVW_ANIME SCROLL2.
	var sh := ShaderMaterial.new()
	sh.shader = _WATERFALL_WATER_SHADER
	sh.render_priority = 2
	var tile0: Texture2D = std.albedo_texture
	var tile1: Texture2D = _layer1_texture(std)
	if tile1 == null or tile1 == tile0:
		push_warning("GeneratedVisual: waterfall tile1 missing; dual scroll will look wrong")
	sh.set_shader_parameter("tile0", tile0)
	sh.set_shader_parameter("tile1", tile1)
	sh.set_shader_parameter("waterfall_layer", _waterfall_layer_index(src, mesh_instance, surface))
	sh.set_shader_parameter("game_fps", 180.0)
	sh.set_shader_parameter("ground_lift", FieldCatalog.GX_TO_METERS * 0.5)
	var extras := _gltf_extras(src)
	sh.set_shader_parameter("tile0_mirror_s", 1.0 if bool(extras.get("tile0_mirror_s", false)) else 0.0)
	sh.set_shader_parameter("tile0_clamp_v", 1.0 if bool(extras.get("tile0_clamp_v", false)) else 0.0)
	sh.set_shader_parameter("tile1_mirror_s", 1.0 if bool(extras.get("tile1_mirror_s", false)) else 0.0)
	sh.set_shader_parameter("tile1_clamp_v", 1.0 if bool(extras.get("tile1_clamp_v", false)) else 0.0)
	sh.set_meta("waterfall_water", true)
	return sh


static func _make_splash_water_material(std: StandardMaterial3D) -> ShaderMaterial:
	## Decomp mouth sprash: prim (100,140,255,200); seg 0x09 scroll {0,-6}/{0,0}.
	var sh := ShaderMaterial.new()
	sh.shader = _SPLASH_WATER_SHADER
	sh.render_priority = 2
	var sprash_c: Texture2D = std.albedo_texture
	var sprash_a: Texture2D = _layer1_texture(std)
	if sprash_a == null or sprash_a == sprash_c:
		push_warning("GeneratedVisual: sprashA missing; mouth splash will look wrong")
	sh.set_shader_parameter("sprash_c", sprash_c)
	sh.set_shader_parameter("sprash_a", sprash_a)
	sh.set_shader_parameter("prim_color", Color(100.0 / 255.0, 140.0 / 255.0, 1.0, 200.0 / 255.0))
	sh.set_shader_parameter("game_fps", 180.0)
	## Slightly above river/ocean XLU so the mouth foam composites cleanly.
	sh.set_shader_parameter("ground_lift", FieldCatalog.GX_TO_METERS * 0.75)
	sh.set_meta("splash_water", true)
	return sh


static func _make_beach_wet_material(
	std: StandardMaterial3D, mesh_instance: MeshInstance3D, surface: int, src: Material
) -> ShaderMaterial:
	## Combiner mix from I4 alpha; prim from DL extras so bed stays blue not sand-white.
	var sh := ShaderMaterial.new()
	sh.shader = _BEACH_WET_SHADER
	sh.set_shader_parameter("albedo_texture", std.albedo_texture)
	sh.set_shader_parameter("prim_color", _beach_prim_color(mesh_instance, surface, src))
	sh.set_shader_parameter("game_fps", 180.0)
	sh.set_meta("beach_wet", true)
	return sh


static func _beach_prim_color(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> Color:
	var raw: Variant = _gltf_extras(mat).get("beach_prim", null)
	if raw is Array and (raw as Array).size() >= 3:
		var p: Array = raw
		return Color(float(p[0]) / 255.0, float(p[1]) / 255.0, float(p[2]) / 255.0)
	var n := _surface_label(mesh_instance, surface, mat).to_lower()
	if n.contains("beachb") or n.contains("beach2"):
		return _BEACH_PRIM_BED
	return _BEACH_PRIM_SAND


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


static func _apply_room_prim_fill_material(std: StandardMaterial3D) -> void:
	## `Global_kankyo_set_room_prim` fills indoor window holes with room prim RGB.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.cull_mode = BaseMaterial3D.CULL_BACK
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	std.render_priority = -1
	std.albedo_texture = null
	std.vertex_color_use_as_albedo = false
	std.set_meta("room_prim_fill", true)
	std.albedo_color = _room_prim_color()


static func _room_prim_color() -> Color:
	## Fine-weather `room_color` from `l_mEnv_kcolor_fine_data` (no electric-point blend yet).
	var clock: Node = Engine.get_main_loop().root.get_node_or_null("/root/Clock")
	if clock != null and clock.has_method("outdoor_light"):
		var pal: Dictionary = clock.call("outdoor_light") as Dictionary
		if pal.has("room"):
			return pal["room"] as Color
	return Color8(200, 240, 240)


static func _mark_shell_room_prim(node: Node) -> void:
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
			if _is_window_pane_surface(mesh_instance, i, mat) or _is_room_prim_fill_surface(
				mesh_instance, i, mat
			):
				continue
			if not _is_vertex_shade_surface(mesh_instance, i, mat):
				continue
			var std: StandardMaterial3D
			if mat is StandardMaterial3D:
				std = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				continue
			std.set_meta("room_prim_surface", true)
			mesh_instance.set_surface_override_material(i, std)
	for child in node.get_children():
		_mark_shell_room_prim(child)


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
			var atlas: Vector2i = _albedo_size(std)
			## Wrap-baked villager shirts remap UVs to 0–1 on a packed atlas — retile
			## the bank PNG into that atlas (same as room walls). Mannequins keep U≤2.
			if atlas.x > 0 and atlas.y > 0 and tiles_u <= 1 and tiles_v <= 1:
				## Wrap-baked villager shirts are a single 0–1 atlas (not U-repeat).
				## Stretch the bank shirt into that atlas; do not re-tile by period.
				var shirt: Image = _texture_image(tex)
				if shirt != null:
					shirt = shirt.duplicate()
					shirt.resize(atlas.x, atlas.y, Image.INTERPOLATE_NEAREST)
					std.albedo_texture = ImageTexture.create_from_image(shirt)
				else:
					std.albedo_texture = tex
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


static func _is_cloth_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	var label := _surface_label(mesh_instance, surface, mat)
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


static func _local_aabb(node: Node) -> AABB:
	return _local_aabb_named(node, "")


static func _world_aabb_named(root: Node3D, needle: String) -> AABB:
	var boxes: Array[AABB] = []
	_collect_world_mesh_aabbs(root, needle.to_lower(), boxes)
	var merged := AABB()
	for box: AABB in boxes:
		if merged.size == Vector3.ZERO:
			merged = box
		else:
			merged = merged.merge(box)
	return merged


static func _collect_world_mesh_aabbs(node: Node, needle: String, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			if needle.is_empty() or String(node.name).to_lower().contains(needle):
				boxes.append(mi.global_transform * mi.mesh.get_aabb())
	for child: Node in node.get_children():
		if child is Node3D:
			_collect_world_mesh_aabbs(child, needle, boxes)


static func _local_aabb_named(node: Node, needle: String) -> AABB:
	## Empty needle → every mesh. Otherwise meshes under a matching name
	## (`rom_myhome2_floor`, …) or surfaces whose material contains the needle
	## (combined shells like `rom_museum1` with `*_floorA_tex`).
	return _local_aabb_named_inner(node, needle.to_lower(), needle.is_empty())


static func _local_aabb_named_inner(node: Node, needle: String, under_match: bool) -> AABB:
	var match := under_match or String(node.name).to_lower().contains(needle)
	var merged := AABB()
	var started := false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var mesh_aabb := AABB()
			if match:
				mesh_aabb = mi.mesh.get_aabb()
			elif not needle.is_empty():
				mesh_aabb = _mesh_surface_aabb_named(mi.mesh, needle)
			if mesh_aabb.size != Vector3.ZERO:
				merged = mi.transform * mesh_aabb
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


static func _mesh_surface_aabb_named(mesh: Mesh, needle: String) -> AABB:
	## Surfaces whose baked material / albedo name contains `needle`.
	var merged := AABB()
	var started := false
	for i: int in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(i)
		var label := _resource_label(mat).to_lower()
		if mat is StandardMaterial3D:
			label += " " + _resource_label((mat as StandardMaterial3D).albedo_texture).to_lower()
		if not label.contains(needle):
			continue
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if typeof(verts) != TYPE_PACKED_VECTOR3_ARRAY:
			continue
		var points: PackedVector3Array = verts
		if points.is_empty():
			continue
		var surface_aabb := AABB(points[0], Vector3.ZERO)
		for p: Vector3 in points:
			surface_aabb = surface_aabb.expand(p)
		if started:
			merged = merged.merge(surface_aabb)
		else:
			merged = surface_aabb
			started = true
	return merged
