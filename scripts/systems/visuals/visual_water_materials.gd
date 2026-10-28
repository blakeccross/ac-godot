class_name VisualWaterMaterials
extends RefCounted
## River / ocean / splash / waterfall / wet-sand shaders and the water-edge gap fix. Used at runtime for FG waterfalls and at bake time for acres (`prepare_acre`).

const _RIVER_WATER_SHADER := preload("res://shaders/river_water.gdshader")
const _SPLASH_WATER_SHADER := preload("res://shaders/splash_water.gdshader")
const _OCEAN_WATER_SHADER := preload("res://shaders/ocean_water.gdshader")
const _WATERFALL_WATER_SHADER := preload("res://shaders/waterfall_water.gdshader")
const _BEACH_WET_SHADER := preload("res://shaders/beach_wet.gdshader")
const _SHRINE_WATER_SHADER := preload("res://shaders/shrine_water.gdshader")
const _SHRINE_BUBBLE_SHADER := preload("res://shaders/shrine_bubble.gdshader")
## Wet-sand beachA DL prim (206,189,148), used when a surface carries no `beach_prim` stamp.
const _BEACH_PRIM_SAND := Color(206.0 / 255.0, 189.0 / 255.0, 148.0 / 255.0)
## Inland river env (0,100,255); mouth acres use (0,60,255) when sprash is present.
const _RIVER_ENV_INLAND := Color(0.0, 100.0 / 255.0, 1.0, 1.0)
const _RIVER_ENV_MOUTH := Color(0.0, 60.0 / 255.0, 1.0, 1.0)
## Sheet opacity, and how much each ripple map adds to it. The decomp's prim alpha and
## PRIM_LOD_FRAC are both 50/255, but the RDP blended in 8-bit gamma and Godot blends in
## linear light, which lifts the crests. These were fitted by capture to the gamma composite.
const _RIVER_BASE_ALPHA := 0.14
const _RIVER_RIPPLE_ALPHA := 0.10
## The `game_frame` rate the scrolling water was tuned to by eye (the decomp runs 60), for
## maps at their native 32 px. emu64 moves a tile 1/8 texel per unit of EVW scroll.
const _WATER_FRAME_RATE := 45.0
## EVW SCROLL2 {1,-1} / {-1,-2}; evw flips T, so the sheets drift (-1,-1) and (1,-2).
const _RIVER_SCROLL_UNIT := _WATER_FRAME_RATE / 8.0 / 32.0
## `aFD_MakeMarinScrollInfo`: wave1 climbs 0.42666667 per frame, pre-shifted so it moves a
## quarter texel per unit.
const _OCEAN_SCROLL := Vector2(0.0, 0.42666667 * _WATER_FRAME_RATE / 4.0 / 32.0)
## Its 300-frame cosine, at the 180 frames/second it was tuned to (the decomp's 60 is 5 s).
## Ocean crests and wet sand share it; the sand runs 1.2 radians behind.
const _OCEAN_SWELL_PERIOD := 300.0 / 180.0
const _BEACH_SWELL_PHASE := -1.2
## Map b swings 16 texels (half of map a) in the decomp. The acres have always shown a
## quarter of that, from 4× maps read as native ones; kept so the shore looks the same.
const _OCEAN_SWELL_REACH := 0.125
## UV per second on the 32×16 well sheet. 7.5 texels/second.
const _BASIN_SPEED := 7.5
const _BASIN_SIZE := Vector2(32.0, 16.0)
## The well water's resting opacity and how much the ripple adds (decomp 50/255 each). The
## RDP blended in 8-bit gamma and Godot blends in linear light, so these were fitted by
## capture to the gamma composite, as for the river.
const _SHRINE_BASE_ALPHA := 0.09
const _SHRINE_RIPPLE_ALPHA := 0.15
## Some river acres (verified: `grd_s_c5_r2`, `grd_s_r2`) convert with their XLU
## water surface stopping short of the acre's own edge on one side by a small,
## consistent margin (~0.46 of a ~10.24-unit acre) while every opaque ground
## surface reaches the full edge. `world_builder.gd` places acres edge-to-edge
## with no overlap, so that shortfall shows up in-game as a flat, unpatterned
## seam right at the acre boundary — no water sheet draws there, so the bed shows
## through with no ripple pattern. Reproduced directly:
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


## Test-only: no in-game callers; kept for tests.
static func water_wave_cos(game_frame: float) -> float:
	## `aFD_MakeMarinScrollInfo`: cos((game_frame % 300) / 300 * 2π).
	var frame: float = fmod(game_frame, 300.0)
	return cos(frame / 300.0 * TAU)


## Test-only: no in-game callers; kept for tests.
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
## beach_wet, shrine_water, shrine_splash, shrine_bubble, or "" for anything else.
## The only water classification; there is no name matching.
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
		## The mesh's own materials: siblings may already carry their water override.
		var sibling: Material = mesh_instance.mesh.surface_get_material(j)
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
	var ripple_a: Texture2D = std.albedo_texture
	var ripple_b: Texture2D = _layer1_texture(std)
	if ripple_b == null or ripple_b == ripple_a:
		push_warning("GeneratedVisual: river water2 missing; dual scroll will look wrong")
	sh.set_shader_parameter("ripple_texture_a", ripple_a)
	sh.set_shader_parameter("ripple_texture_b", ripple_b)
	sh.set_shader_parameter("deep_color", _RIVER_ENV_MOUTH if mouth else _RIVER_ENV_INLAND)
	sh.set_shader_parameter("crest_color", Color.WHITE)
	sh.set_shader_parameter("base_alpha", _RIVER_BASE_ALPHA)
	sh.set_shader_parameter("ripple_alpha", _RIVER_RIPPLE_ALPHA)
	sh.set_shader_parameter("scroll_a", Vector2(-1.0, -1.0) * _RIVER_SCROLL_UNIT)
	sh.set_shader_parameter("scroll_b", Vector2(1.0, -2.0) * _RIVER_SCROLL_UNIT)
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
	sh.set_shader_parameter("wave_texture_a", wave1)
	sh.set_shader_parameter("wave_texture_b", wave2)
	sh.set_shader_parameter("water_color", Color(60.0 / 255.0, 120.0 / 255.0, 1.0))
	sh.set_shader_parameter("scroll_a", _OCEAN_SCROLL)
	sh.set_shader_parameter("swell_period", _OCEAN_SWELL_PERIOD)
	sh.set_shader_parameter("swell_reach", _OCEAN_SWELL_REACH)
	## The mesh UVs count wave1 tiles; the shore's wave2 is a taller map.
	if wave1 != null and wave2 != null:
		sh.set_shader_parameter("wave_b_scale", wave1.get_size() / wave2.get_size())
	sh.set_shader_parameter("ground_lift", FieldCatalog.GX_TO_METERS * 0.5)
	## Shore band tile1 is wave2 with GX_CLAMP T; open water is wave3 REPEAT.
	sh.set_shader_parameter("wave_b_clamp_v", bool(VisualSurface.gltf_extras(src).get("wave2_clamp_t", false)))
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


## The four `obj_fallS` sheets (grpAT, BT, CT, DT), in draw order. Colours are the
## combiners' fixed PRIM / ENV; `*_lit` / `*_add` are their TEXEL terms (LOD 32 / 47 on AT /
## CT). Scroll is the EVW SCROLL2 pair as evw hands it to the tile (Y negated: AT {0,2}
## becomes (0,-2)); `uv` is each tile's shift (AT tile1 (0,14) ×4 V, CT tile0 (15,15) ×2, DT tile1 (0,1)
## ½ V) times its size against the 32 px tile 0 (AT / CT tile1 is 16 px).
const _WATERFALL_LAYERS: Array[Dictionary] = [
	{
		"water": Color8(200, 220, 255), "glow": Color8(20, 30, 40),
		"a_lit": 0.0, "a_add": 0.0, "b_add": 32.0 / 255.0, "a_alpha_offset": 0.0,
		"scroll_a": Vector2(0.0, 0.0), "scroll_b": Vector2(0.0, -2.0),
		"uv_a": Vector2(1.0, 1.0), "uv_b": Vector2(2.0, 8.0), "native_b": 16.0,
		"alpha_a": false, "alpha_b": false,
	},
	{
		"water": Color8(100, 140, 255), "glow": Color8(0, 0, 0),
		"a_lit": 1.0, "a_add": 0.0, "b_add": 1.0, "a_alpha_offset": 0.0,
		"scroll_a": Vector2(0.0, 3.0), "scroll_b": Vector2(0.0, 8.0),
		"uv_a": Vector2(1.0, 1.0), "uv_b": Vector2(1.0, 1.0), "native_b": 32.0,
		"alpha_a": true, "alpha_b": true,
	},
	{
		"water": Color8(200, 220, 255), "glow": Color8(30, 40, 50),
		"a_lit": 0.0, "a_add": 47.0 / 255.0, "b_add": 0.0, "a_alpha_offset": 1.0,
		"scroll_a": Vector2(-1.0, -1.0), "scroll_b": Vector2(0.0, 0.0),
		"uv_a": Vector2(2.0, 2.0), "uv_b": Vector2(2.0, 2.0), "native_b": 16.0,
		"alpha_a": false, "alpha_b": false,
	},
	{
		## Tile 1 is only the crest mask; adding it as colour clamps the lip to white.
		"water": Color8(100, 140, 255), "glow": Color8(0, 0, 0),
		"a_lit": 1.0, "a_add": 1.0, "b_add": 0.0, "a_alpha_offset": 0.0,
		"scroll_a": Vector2(0.0, 8.0), "scroll_b": Vector2(0.0, 0.0),
		"uv_a": Vector2(1.0, 1.0), "uv_b": Vector2(1.0, 0.5), "native_b": 32.0,
		"alpha_a": true, "alpha_b": false,
	},
]


static func make_waterfall_water_material(
	std: StandardMaterial3D, src: Material, surface: int
) -> ShaderMaterial:
	## Decomp obj_fallS grpAT/BT/CT/DT — dual-scroll EVW_ANIME SCROLL2.
	var sh := ShaderMaterial.new()
	sh.shader = _WATERFALL_WATER_SHADER
	var index := _waterfall_layer_index(src, surface)
	var layer: Dictionary = _WATERFALL_LAYERS[index]
	## Draw AT → DT so each sheet composites over the one before it.
	sh.render_priority = 2 + index
	var tile0: Texture2D = std.albedo_texture
	var tile1: Texture2D = _layer1_texture(std)
	if tile1 == null or tile1 == tile0:
		push_warning("GeneratedVisual: waterfall tile1 missing; dual scroll will look wrong")
	sh.set_shader_parameter("texture_a", tile0)
	sh.set_shader_parameter("texture_b", tile1)
	sh.set_shader_parameter("water_color", layer["water"])
	sh.set_shader_parameter("glow_color", layer["glow"])
	for term: String in ["a_lit", "a_add", "b_add", "a_alpha_offset"]:
		sh.set_shader_parameter(term, layer[term])
	sh.set_shader_parameter("uv_scale_a", layer["uv_a"])
	sh.set_shader_parameter("uv_scale_b", layer["uv_b"])
	## emu64 moves a tile 1/8 texel per unit; the drift runs against the texel offset.
	sh.set_shader_parameter("scroll_a", -(layer["scroll_a"] as Vector2) * _WATER_FRAME_RATE / 8.0 / 32.0)
	sh.set_shader_parameter(
		"scroll_b", -(layer["scroll_b"] as Vector2) * _WATER_FRAME_RATE / 8.0 / float(layer["native_b"])
	)
	sh.set_shader_parameter("coverage_a_in_alpha", layer["alpha_a"])
	sh.set_shader_parameter("coverage_b_in_alpha", layer["alpha_b"])
	sh.set_shader_parameter("ground_lift", FieldCatalog.GX_TO_METERS * 0.5)
	var extras := VisualSurface.gltf_extras(src)
	sh.set_shader_parameter("mirror_a_u", bool(extras.get("tile0_mirror_s", false)))
	sh.set_shader_parameter("clamp_a_v", bool(extras.get("tile0_clamp_v", false)))
	sh.set_shader_parameter("mirror_b_u", bool(extras.get("tile1_mirror_s", false)))
	sh.set_shader_parameter("clamp_b_v", bool(extras.get("tile1_clamp_v", false)))
	sh.set_meta("waterfall_water", true)
	sh.set_meta("waterfall_layer", index)
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
	sh.set_shader_parameter("streak_texture", sprash_c)
	sh.set_shader_parameter("foam_texture", sprash_a)
	sh.set_shader_parameter("water_color", Color8(100, 140, 255))
	sh.set_shader_parameter("opacity", 200.0 / 255.0)
	## Evw {0,-6}, 1/8 texel per unit on the 32 px map. The foam map's shift_t 1 halves V.
	sh.set_shader_parameter("streak_scroll", Vector2(0.0, -6.0 * _WATER_FRAME_RATE / 8.0 / 32.0))
	sh.set_shader_parameter("foam_scale", Vector2(1.0, 0.5))
	## Slightly above river/ocean XLU so the mouth foam composites cleanly.
	sh.set_shader_parameter("ground_lift", FieldCatalog.GX_TO_METERS * 0.75)
	sh.set_meta("splash_water", true)
	return sh


static func make_shrine_basin_material(std: StandardMaterial3D, splash: bool) -> ShaderMaterial:
	## Water sits under the splash rim. The rim is the opaque grey sheet.
	var sh := ShaderMaterial.new()
	sh.shader = _SHRINE_WATER_SHADER
	sh.render_priority = 2 if splash else 1
	var tile0: Texture2D = std.albedo_texture
	var tile1: Texture2D = _layer1_texture(std)
	if tile1 == null or tile1 == tile0:
		push_warning("GeneratedVisual: shrine basin tile1 missing; the well water will look flat")
	sh.set_shader_parameter("ripple_texture_a", tile0)
	sh.set_shader_parameter("ripple_texture_b", tile1)
	## Texels per second on the 32×16 sheet; the masks drift against their texel offset.
	var scroll_a := Vector2(0.0, 5.0)
	var scroll_b := Vector2(0.0, 3.0)
	var water_color := Color8(0, 100, 255)
	var ripple_alpha := _SHRINE_RIPPLE_ALPHA
	var base_alpha := _SHRINE_BASE_ALPHA
	var depth_bias := 0.01
	if splash:
		scroll_a = Vector2(-50.0, 0.0)
		scroll_b = Vector2(0.0, -13.0)
		water_color = Color8(127, 160, 160)
		ripple_alpha = 120.0 / 255.0
		base_alpha = 1.0
		depth_bias = 0.02
	sh.set_shader_parameter("scroll_a", -scroll_a * _BASIN_SPEED / _BASIN_SIZE)
	sh.set_shader_parameter("scroll_b", -scroll_b * _BASIN_SPEED / _BASIN_SIZE)
	sh.set_shader_parameter("water_color", water_color)
	sh.set_shader_parameter("ripple_alpha", ripple_alpha)
	sh.set_shader_parameter("base_alpha", base_alpha)
	sh.set_shader_parameter("depth_bias", depth_bias)
	sh.set_meta("shrine_water", true)
	return sh


static func make_shrine_bubble_material(std: StandardMaterial3D) -> ShaderMaterial:
	## Rising card above the rim: the lit colour lifted by 80, coverage 180.
	var sh := ShaderMaterial.new()
	sh.shader = _SHRINE_BUBBLE_SHADER
	sh.render_priority = 3
	sh.set_shader_parameter("bubble_texture", std.albedo_texture)
	sh.set_shader_parameter("lift", Color8(80, 80, 80))
	sh.set_shader_parameter("opacity", 180.0 / 255.0)
	sh.set_meta("shrine_bubble", true)
	return sh


static func make_beach_wet_material(
	std: StandardMaterial3D, src: Material
) -> ShaderMaterial:
	## Combiner mix from I4 alpha; prim from DL extras so bed stays blue not sand-white.
	var sh := ShaderMaterial.new()
	sh.shader = _BEACH_WET_SHADER
	sh.set_shader_parameter("albedo_texture", std.albedo_texture)
	sh.set_shader_parameter("surface_color", _beach_prim_color(src))
	## `aFD_MakeMarinScrollInfo` env: (144,128,96) plus up to (42,36,28) on the swell.
	sh.set_shader_parameter("wet_color_low", Color8(144, 128, 96))
	sh.set_shader_parameter("wet_color_high", Color8(186, 164, 124))
	sh.set_shader_parameter("swell_period", _OCEAN_SWELL_PERIOD)
	sh.set_shader_parameter("swell_phase", _BEACH_SWELL_PHASE)
	sh.set_meta("beach_wet", true)
	return sh


static func _beach_prim_color(mat: Material) -> Color:
	## The pipeline stamps each surface's DL prim (sand for beachA, dark blue for the ocean bed).
	var raw: Variant = VisualSurface.gltf_extras(mat).get("beach_prim", null)
	if raw is Array and (raw as Array).size() >= 3:
		var p: Array = raw
		return Color(float(p[0]) / 255.0, float(p[1]) / 255.0, float(p[2]) / 255.0)
	return _BEACH_PRIM_SAND
