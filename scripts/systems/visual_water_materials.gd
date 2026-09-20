class_name VisualWaterMaterials
extends RefCounted
## River / ocean / splash / waterfall / wet-sand shaders and the water-edge gap fix. Used at runtime for FG waterfalls and at bake time for acres (`prepare_acre`).

const _RIVER_WATER_SHADER := preload("res://shaders/river_water.gdshader")
const _SPLASH_WATER_SHADER := preload("res://shaders/splash_water.gdshader")
const _OCEAN_WATER_SHADER := preload("res://shaders/ocean_water.gdshader")
const _WATERFALL_WATER_SHADER := preload("res://shaders/waterfall_water.gdshader")
const _BEACH_WET_SHADER := preload("res://shaders/beach_wet.gdshader")
## Wet-sand beachA DL prim (206,189,148), used when a surface carries no `beach_prim` stamp.
const _BEACH_PRIM_SAND := Color(206.0 / 255.0, 189.0 / 255.0, 148.0 / 255.0)
## Inland river env (0,100,255); mouth acres use (0,60,255) when sprash is present.
const _RIVER_ENV_INLAND := Color(0.0, 100.0 / 255.0, 1.0, 1.0)
const _RIVER_ENV_MOUTH := Color(0.0, 60.0 / 255.0, 1.0, 1.0)
## Some river acres (verified: `grd_s_c5_r2`, `grd_s_r2`) convert with their XLU
## water surface stopping short of the acre's own edge on one side by a small,
## consistent margin (~0.46 of a ~10.24-unit acre) while every opaque ground
## surface reaches the full edge. `world_builder.gd` places acres edge-to-edge
## with no overlap, so that shortfall shows up in-game as a flat, unpatterned
## seam right at the acre boundary — nothing draws there, so the water shader's
## screen-texture read shows through with no pattern. Reproduced directly:
## placing two such acres side by side (their real `world_builder.gd` layout)
## renders exactly this gap.
##
## Rather than re-run the whole pipeline chasing the exact per-vertex cause,
## stretch the water surface (a `Transform3D` scale only — Godot's default
## normal transform already compensates, and a ~4.5% stretch is invisible on a
## repeating tile) so it reaches whichever edge(s) of the acre's own ground
## plane it was already anchored to but fell short of. An edge the water was
## never meant to reach (a channel narrower than the acre) is left alone: it
## only stretches an edge where the *other* side already exactly matches the
## ground, so a real narrow channel (matching neither ground edge) is untouched.
##
## The shortfall must also be small (`_WATER_EDGE_MAX_GAP`). A meandering river
## (`grd_s_r4_*`–`r7_*`) or a shoreline (`grd_s_m_*`) touches one acre edge on each
## axis while legitimately ending well short of the other. Without the bound the
## sheet was scaled up to 2.3x, dragging the ripple layer off the river bed and
## under the land — the bed then read as flat, unshaded blue.
const _WATER_EDGE_EPS := 0.05
const _WATER_EDGE_MAX_GAP := 0.5


## Bake-time entry for `tools/bake_acre_scenes.gd`: the material pass a `grd_*` GLB gets.
## Water shaders, edge stretch and cutout hardening land on the mesh instances so the tool
## can save the result into the acre scene.
static func prepare_acre(pivot: Node3D, visual_id: StringName) -> void:
	_close_water_edge_gaps(pivot)
	VisualMaterials.apply(pivot, FieldCatalog.is_ground_decal(visual_id), visual_id)


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


static func _close_water_edge_gaps(node: Node) -> void:
	var ground: MeshInstance3D = _find_ground_mesh_instance(node)
	if ground == null or ground.mesh == null:
		return
	var ground_aabb: AABB = ground.transform * ground.mesh.get_aabb()
	if ground_aabb.size == Vector3.ZERO:
		return
	_stretch_water_instances(node, ground_aabb)


static func _find_ground_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s: int in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(s)
				## The ground plane is the surface the pipeline stamped `field_role: grass`.
				if (
					mat != null
					and water_kind(mat) == ""
					and FieldCatalog.season_role_from_extras(mat) == "grass"
				):
					return mi
	for child in node.get_children():
		var found: MeshInstance3D = _find_ground_mesh_instance(child)
		if found != null:
			return found
	return null


static func _stretch_water_instances(node: Node, ground_aabb: AABB) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s: int in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(s)
				if mat != null and (water_kind(mat) == "river" or water_kind(mat) == "ocean"):
					_fit_water_to_ground_edge(mi, ground_aabb)
					break
	for child in node.get_children():
		_stretch_water_instances(child, ground_aabb)


static func _fit_water_to_ground_edge(mi: MeshInstance3D, ground_aabb: AABB) -> void:
	var water_aabb: AABB = mi.transform * mi.mesh.get_aabb()
	var scale := Vector3.ONE
	var anchor: Vector3 = water_aabb.position
	for axis: int in [Vector3.AXIS_X, Vector3.AXIS_Z]:
		var w_min: float = water_aabb.position[axis]
		var w_max: float = water_aabb.position[axis] + water_aabb.size[axis]
		var g_min: float = ground_aabb.position[axis]
		var g_max: float = ground_aabb.position[axis] + ground_aabb.size[axis]
		var touches_min: bool = absf(w_min - g_min) < _WATER_EDGE_EPS
		var touches_max: bool = absf(w_max - g_max) < _WATER_EDGE_EPS
		var span: float = maxf(w_max - w_min, 0.001)
		var gap_max: float = g_max - w_max
		var gap_min: float = w_min - g_min
		if (
			touches_min
			and not touches_max
			and gap_max > _WATER_EDGE_EPS
			and gap_max <= _WATER_EDGE_MAX_GAP
		):
			scale[axis] = (g_max - w_min) / span
			anchor[axis] = w_min
		elif (
			touches_max
			and not touches_min
			and gap_min > _WATER_EDGE_EPS
			and gap_min <= _WATER_EDGE_MAX_GAP
		):
			scale[axis] = (w_max - g_min) / span
			anchor[axis] = w_max
	if scale.is_equal_approx(Vector3.ONE):
		return
	var origin: Vector3 = anchor - Vector3(scale.x * anchor.x, scale.y * anchor.y, scale.z * anchor.z)
	mi.transform = Transform3D(Basis().scaled(scale), origin) * mi.transform


## `water_kind` glTF extra the pipeline stamps from Gfx state: river, ocean, splash, waterfall,
## beach_wet, or "" for anything else. The only water classification; there is no name matching.
static func water_kind(mat: Material) -> String:
	return str(VisualSurface.gltf_extras(mat).get("water_kind", ""))


## `obj_fallS_rainbowT_model` (`ac_fallS_draw.c_inc`): only drawn when
## `Common_Get(rainbow_opacity) > 0` — a billboarded, alpha-faded arc that shows up
## after it rains. We don't track that weather state, so the baked-in decal has to
## default to invisible rather than a permanent, wrongly-shaped arc hanging over the
## falls. Name-free: every OTHER surface sharing this mesh with a `waterfall`-tagged
## layer is one of the 4 grpAT/BT/CT/DT scrolling sheets — a sibling surface that
## itself carries no water classification is the leftover rainbow.
static func is_fall_rainbow_surface(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> bool:
	if water_kind(mat) != "":
		return false
	var n: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 0
	for j: int in n:
		if j == surface:
			continue
		var sibling: Material = mesh_instance.get_active_material(j)
		if sibling != null and water_kind(sibling) == "waterfall":
			return true
	return false


static func make_fall_rainbow_material() -> StandardMaterial3D:
	var std := StandardMaterial3D.new()
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	std.cull_mode = BaseMaterial3D.CULL_DISABLED
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.render_priority = -1
	std.set_meta("fall_rainbow", true)
	return std


static func tree_has_splash_water(node: Node) -> bool:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat != null and water_kind(mat) == "splash":
				return true
	for child in node.get_children():
		if tree_has_splash_water(child):
			return true
	return false


static func _layer1_texture(std: StandardMaterial3D) -> Texture2D:
	if std.ao_texture != null:
		return std.ao_texture
	if std.emission_texture != null:
		return std.emission_texture
	return std.albedo_texture


static func make_river_water_material(std: StandardMaterial3D, mouth: bool = false) -> ShaderMaterial:
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


static func make_ocean_water_material(std: StandardMaterial3D, src: Material) -> ShaderMaterial:
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
		"wave2_clamp_v", 1.0 if bool(VisualSurface.gltf_extras(src).get("wave2_clamp_t", false)) else 0.0
	)
	sh.set_meta("ocean_water", true)
	return sh


static func _waterfall_layer_index(mat: Material, surface: int) -> int:
	var layer := str(VisualSurface.gltf_extras(mat).get("waterfall_layer", "")).to_lower()
	match layer:
		"at":
			return 0
		"bt":
			return 1
		"ct":
			return 2
		"dt":
			return 3
	## Unstamped (non-fall surfaces the pipeline tags `waterfall`): primitive order.
	return surface if surface >= 0 and surface <= 3 else 1


static func make_waterfall_water_material(
	std: StandardMaterial3D, src: Material, surface: int
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
	sh.set_shader_parameter("waterfall_layer", _waterfall_layer_index(src, surface))
	sh.set_shader_parameter("game_fps", 180.0)
	sh.set_shader_parameter("ground_lift", FieldCatalog.GX_TO_METERS * 0.5)
	var extras := VisualSurface.gltf_extras(src)
	sh.set_shader_parameter("tile0_mirror_s", 1.0 if bool(extras.get("tile0_mirror_s", false)) else 0.0)
	sh.set_shader_parameter("tile0_clamp_v", 1.0 if bool(extras.get("tile0_clamp_v", false)) else 0.0)
	sh.set_shader_parameter("tile1_mirror_s", 1.0 if bool(extras.get("tile1_mirror_s", false)) else 0.0)
	sh.set_shader_parameter("tile1_clamp_v", 1.0 if bool(extras.get("tile1_clamp_v", false)) else 0.0)
	sh.set_meta("waterfall_water", true)
	return sh


static func make_splash_water_material(std: StandardMaterial3D) -> ShaderMaterial:
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


static func make_beach_wet_material(
	std: StandardMaterial3D, src: Material
) -> ShaderMaterial:
	## Combiner mix from I4 alpha; prim from DL extras so bed stays blue not sand-white.
	var sh := ShaderMaterial.new()
	sh.shader = _BEACH_WET_SHADER
	sh.set_shader_parameter("albedo_texture", std.albedo_texture)
	sh.set_shader_parameter("prim_color", _beach_prim_color(src))
	sh.set_shader_parameter("game_fps", 180.0)
	sh.set_meta("beach_wet", true)
	return sh


static func _beach_prim_color(mat: Material) -> Color:
	## The pipeline stamps each surface's DL prim (sand for beachA, dark blue for the ocean bed).
	var raw: Variant = VisualSurface.gltf_extras(mat).get("beach_prim", null)
	if raw is Array and (raw as Array).size() >= 3:
		var p: Array = raw
		return Color(float(p[0]) / 255.0, float(p[1]) / 255.0, float(p[2]) / 255.0)
	return _BEACH_PRIM_SAND
