class_name TestAcreScenes
extends GdUnitTestSuite

## Baked acre scenes (`tools/bake_acre_scenes.gd`): each `grd_*` acre is a scene with its
## materials, water shaders and grid, and the only form a field acre takes at runtime.
## Tests skip when the local asset pipeline has not produced the acre.

const GLB_DIR := "res://assets/generated/environment/acres/"

## River, river mouth, marine/beach, open ocean, waterfall, plain land, cliff, station.
const PARITY_ACRES: Array[StringName] = [
	&"grd_s_r1_p_1",
	&"grd_s_m_r1_1",
	&"grd_s_m_1",
	&"grd_s_o_1",
	&"grd_s_m_wf_1",
	&"grd_s_c1_1",
	&"grd_s_e2_1",
	&"grd_s_t_st1_1",
]
## Spring/summer, autumn, winter: three different season packs.
const SEASONS: Array[Dictionary] = [
	{"year": 2001, "month": 7, "day": 1, "hour": 12, "minute": 0},
	{"year": 2001, "month": 10, "day": 1, "hour": 12, "minute": 0},
	{"year": 2001, "month": 1, "day": 15, "hour": 12, "minute": 0},
]
const KNOWN_META: PackedStringArray = [
	"river_water", "ocean_water", "splash_water", "waterfall_water", "beach_wet", "fall_rainbow"
]
const STANDARD_PROPS: PackedStringArray = [
	"albedo_color", "transparency", "cull_mode", "alpha_scissor_threshold", "depth_draw_mode",
	"texture_filter", "texture_repeat", "roughness", "metallic", "vertex_color_use_as_albedo",
	"shading_mode", "blend_mode", "uv1_scale", "uv1_offset", "ao_enabled", "emission_enabled",
	"alpha_antialiasing_mode", "render_priority",
]


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Acre.clear_tile_cache()


func after_test() -> void:
	Clock.reset_to_default()


func test_baked_acre_attaches_as_scene_with_grid() -> void:
	var id := &"grd_s_r1_p_1"
	if FieldCatalog.acre_scene_path(id).is_empty():
		return
	var host := _host()
	var pivot: Node3D = GeneratedVisual.attach(host, id)
	assert_that(pivot).is_not_null()
	var acre: Acre = pivot.get_child(0) as Acre
	assert_that(acre).is_not_null()
	assert_str(String(acre.visual_id)).is_equal(String(id))
	assert_that(acre.grid).is_not_null()
	assert_bool(acre.grid.is_valid()).is_true()
	assert_array(acre.grid.units).is_equal(AcreGrid.from_col_json(String(id)).units)


func test_acres_have_no_glb_path() -> void:
	var id := &"grd_s_r1_p_1"
	if FieldCatalog.acre_scene_path(id).is_empty():
		return
	assert_array(FieldCatalog.mesh_paths(id)).is_equal(PackedStringArray([FieldCatalog.acre_scene_path(id)]))
	var host := _host()
	assert_object(GeneratedVisual.attach(host, &"grd_s_not_an_acre_9")).is_null()
	## The post office shell is an interior GLB, not an acre scene.
	assert_str(FieldCatalog.acre_scene_path(&"grd_post_office")).is_empty()


func test_grid_lookup_matches_col_json_for_every_baked_grid() -> void:
	var dir := DirAccess.open(FieldCatalog.ACRE_SCENE_ROOT + "grids")
	if dir == null:
		return
	for file: String in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var id: String = file.get_basename()
		assert_array(FieldCatalog.acre_units(StringName(id))).override_failure_message(
			"%s: baked grid differs from its col.json" % id
		).is_equal(AcreGrid.from_col_json(id).units)


func test_water_shader_and_textures_are_external_replaceable_files() -> void:
	var id := &"grd_s_r1_p_1"
	if FieldCatalog.acre_scene_path(id).is_empty():
		return
	var host := _host()
	var pivot: Node3D = GeneratedVisual.attach(host, id)
	var river: ShaderMaterial = null
	for mesh_instance: MeshInstance3D in _mesh_instances(pivot):
		for surface: int in mesh_instance.mesh.get_surface_count():
			var mat: Material = mesh_instance.get_surface_override_material(surface)
			if mat is ShaderMaterial and mat.has_meta("river_water"):
				river = mat as ShaderMaterial
	assert_that(river).is_not_null()
	assert_str(river.resource_path).contains("/materials/water/")
	for param: String in ["water1", "water2"]:
		var tex: Texture2D = river.get_shader_parameter(param) as Texture2D
		assert_that(tex).is_not_null()
		assert_str(tex.resource_path).contains("/textures/water/")
		assert_str(tex.resource_path).ends_with(".png")


func test_season_change_repoints_grass_in_place() -> void:
	var id := &"grd_s_c1_1"
	if FieldCatalog.acre_scene_path(id).is_empty():
		return
	Clock.apply_snapshot(SEASONS[0])
	var summer_path: String = FieldCatalog.season_texture_path("grass")
	Clock.apply_snapshot(SEASONS[2])
	if summer_path.is_empty() or summer_path == FieldCatalog.season_texture_path("grass"):
		return
	Clock.apply_snapshot(SEASONS[0])
	var host := _host()
	var pivot: Node3D = GeneratedVisual.attach(host, id)
	var summer: String = _grass_signature(pivot)
	assert_str(summer).is_not_empty()
	Clock.apply_snapshot(SEASONS[2])
	var refreshed: Node3D = GeneratedVisual.refresh(host, id)
	assert_object(refreshed).is_same(pivot)
	assert_str(_grass_signature(pivot)).is_not_equal(summer)
	Clock.apply_snapshot(SEASONS[0])
	GeneratedVisual.refresh(host, id)
	assert_str(_grass_signature(pivot)).is_equal(summer)


func test_baked_scene_matches_its_glb_in_every_season() -> void:
	## The scene is the GLB after the bake's material pass plus the season swap. Rebuild that
	## from the GLB and compare surface for surface (this also catches a scene left stale by
	## a GLB reconvert). `ACRE_PARITY_ALL=1` checks every baked acre.
	var compared := 0
	for id: StringName in _parity_acres():
		if FieldCatalog.acre_scene_path(id).is_empty() or not ResourceLoader.exists(GLB_DIR + id + ".glb"):
			continue
		compared += 1
		for season: Dictionary in SEASONS:
			Clock.apply_snapshot(season)
			Acre.clear_tile_cache()
			var glb_pivot: Node3D = _pivot_from_glb(id)
			var baked_pivot: Node3D = GeneratedVisual.attach(_host(), id)
			var expected: Dictionary = _signature(glb_pivot)
			var actual: Dictionary = _signature(baked_pivot)
			assert_that(actual).override_failure_message(
				"%s (%s): %s" % [id, season["month"], _first_difference(expected, actual)]
			).is_equal(expected)
			glb_pivot.free()
			baked_pivot.get_parent().free()
	print("acre parity: compared %d acres x %d seasons" % [compared, SEASONS.size()])


# ---- helpers -------------------------------------------------------------------------------


func _parity_acres() -> Array[StringName]:
	if OS.get_environment("ACRE_PARITY_ALL").is_empty():
		return PARITY_ACRES
	var ids: Array[StringName] = []
	for file: String in DirAccess.get_files_at(FieldCatalog.ACRE_SCENE_DIR):
		if file.ends_with(".tscn"):
			ids.append(StringName(file.get_basename()))
	return ids


func _pivot_from_glb(id: StringName) -> Node3D:
	var pivot := Node3D.new()
	pivot.add_child((load(GLB_DIR + id + ".glb") as PackedScene).instantiate())
	VisualWaterMaterials.prepare_acre(pivot, id)
	VisualSeasons.apply(pivot)
	return pivot


func _host() -> Node3D:
	var host := Node3D.new()
	add_child(host)
	return host


func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		out.append_array(_mesh_instances(child))
	return out


func _grass_signature(pivot: Node) -> String:
	for mesh_instance: MeshInstance3D in _mesh_instances(pivot):
		for surface: int in mesh_instance.mesh.get_surface_count():
			var mat: Material = mesh_instance.get_surface_override_material(surface)
			if mat is StandardMaterial3D and String(mat.get_meta("field_role", "")) == "grass":
				return _image_hash((mat as StandardMaterial3D).albedo_texture)
	return ""


func _signature(pivot: Node) -> Dictionary:
	var out := {}
	for mesh_instance: MeshInstance3D in _mesh_instances(pivot):
		var surfaces: Array = []
		for surface: int in mesh_instance.mesh.get_surface_count():
			surfaces.append(_material_signature(mesh_instance.get_active_material(surface)))
		out[String(mesh_instance.name)] = {
			"transform": mesh_instance.transform,
			"aabb": mesh_instance.mesh.get_aabb(),
			"cast_shadow": mesh_instance.cast_shadow,
			"sorting_offset": mesh_instance.sorting_offset,
			"surfaces": surfaces,
		}
	return out


func _material_signature(mat: Material) -> Dictionary:
	if mat == null:
		return {"class": "null"}
	var sig := {"class": mat.get_class(), "render_priority": mat.render_priority}
	for meta: String in KNOWN_META:
		sig["meta/" + meta] = mat.has_meta(meta)
	if mat is StandardMaterial3D:
		var std := mat as StandardMaterial3D
		for prop: String in STANDARD_PROPS:
			sig[prop] = _stable(std.get(prop))
		sig["albedo_texture"] = _image_hash(std.albedo_texture)
		sig["ao_texture"] = _image_hash(std.ao_texture)
		sig["emission_texture"] = _image_hash(std.emission_texture)
	elif mat is ShaderMaterial:
		var sh := mat as ShaderMaterial
		sig["shader"] = sh.shader.resource_path
		for uniform: Dictionary in sh.shader.get_shader_uniform_list():
			var value: Variant = sh.get_shader_parameter(uniform["name"])
			sig["u/" + String(uniform["name"])] = _image_hash(value) if value is Texture2D else _stable(value)
	return sig


## Shader floats are 32-bit on the GPU and in the saved `.tres`; the runtime path computes
## them as doubles (`0.0375` vs `0.037500000000000006`), so compare at float32 precision.
func _stable(value: Variant) -> String:
	if value is float:
		return "%.6f" % value
	return var_to_str(value)


func _image_hash(tex: Texture2D) -> String:
	if tex == null:
		return ""
	var img: Image = VisualAtlas.texture_image(tex)
	if img == null:
		return "unreadable"
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(img.get_data())
	return "%dx%d:%s" % [img.get_width(), img.get_height(), ctx.finish().hex_encode()]


func _first_difference(expected: Dictionary, actual: Dictionary) -> String:
	for node_name: String in expected:
		if not actual.has(node_name):
			return "missing node %s" % node_name
		var want: Dictionary = expected[node_name]
		var got: Dictionary = actual[node_name]
		for key: String in want:
			if key != "surfaces":
				if want[key] != got[key]:
					return "%s.%s: %s != %s" % [node_name, key, want[key], got[key]]
				continue
			for i: int in (want[key] as Array).size():
				var want_surface: Dictionary = want[key][i]
				var got_surface: Dictionary = got[key][i]
				for prop: String in want_surface:
					if want_surface[prop] != got_surface.get(prop):
						return "%s surface %d %s: %s != %s" % [
							node_name, i, prop, want_surface[prop], got_surface.get(prop)
						]
	for node_name: String in actual:
		if not expected.has(node_name):
			return "extra node %s" % node_name
	return "no difference found"
