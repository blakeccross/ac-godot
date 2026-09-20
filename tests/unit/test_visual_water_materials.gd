class_name TestVisualWaterMaterials
extends GdUnitTestSuite

## Water is classified only from the `water_kind` glTF extra the pipeline stamps from Gfx
## state. Material names never decide it.


func _material(extras: Dictionary, label: String = "") -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = label
	if not extras.is_empty():
		mat.set_meta("extras", extras)
	return mat


func test_water_kind_reads_only_the_stamp() -> void:
	assert_str(VisualWaterMaterials.water_kind(_material({"water_kind": "river"}))).is_equal("river")
	assert_str(VisualWaterMaterials.water_kind(_material({"water_kind": "beach_wet"}))).is_equal("beach_wet")
	assert_str(VisualWaterMaterials.water_kind(_material({}))).is_empty()


func test_water_looking_names_without_a_stamp_are_not_water() -> void:
	for label: String in [
		"river_mFM_grd_water1_tex",
		"mFM_grd_ocean_wave_tex",
		"sprash_tex",
		"obj_fallS_grpAT_model",
		"int_nog_beachbed_side_tex",
	]:
		assert_str(VisualWaterMaterials.water_kind(_material({}, label))).override_failure_message(
			"%s must not be classified by name" % label
		).is_empty()


func test_beach_bed_furniture_gets_no_water_shader() -> void:
	## `int_nog_beachbed` used to match the `beachb` name needle and got the wet-sand shader.
	if FieldCatalog.mesh_paths(&"int_nog_beachbed").is_empty():
		return
	var host := Node3D.new()
	add_child(host)
	var pivot: Node3D = GeneratedVisual.attach(host, &"int_nog_beachbed")
	assert_that(pivot).is_not_null()
	for mesh_instance: MeshInstance3D in _mesh_instances(pivot):
		for surface: int in mesh_instance.mesh.get_surface_count():
			assert_bool(mesh_instance.get_active_material(surface) is ShaderMaterial).is_false()
	host.free()


func test_waterfall_layer_comes_from_the_stamp_then_primitive_order() -> void:
	var std := StandardMaterial3D.new()
	var stamped := _material({"water_kind": "waterfall", "waterfall_layer": "ct"})
	assert_that(_layer(VisualWaterMaterials.make_waterfall_water_material(std, stamped, 0))).is_equal(2)
	var unstamped := _material({"water_kind": "waterfall"})
	assert_that(_layer(VisualWaterMaterials.make_waterfall_water_material(std, unstamped, 3))).is_equal(3)
	assert_that(_layer(VisualWaterMaterials.make_waterfall_water_material(std, unstamped, 7))).is_equal(1)


func test_wet_sand_prim_comes_from_the_stamp_else_sand() -> void:
	var std := StandardMaterial3D.new()
	var bed := VisualWaterMaterials.make_beach_wet_material(std, _material({"beach_prim": [32, 48, 144, 255]}))
	assert_that(bed.get_shader_parameter("prim_color")).is_equal(Color(32.0 / 255.0, 48.0 / 255.0, 144.0 / 255.0))
	var sand := VisualWaterMaterials.make_beach_wet_material(std, _material({}))
	assert_that(sand.get_shader_parameter("prim_color")).is_equal(Color(206.0 / 255.0, 189.0 / 255.0, 148.0 / 255.0))


func _layer(mat: ShaderMaterial) -> int:
	return int(mat.get_shader_parameter("waterfall_layer"))


func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		out.append_array(_mesh_instances(child))
	return out
