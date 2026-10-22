class_name TestActorBlobShadow
extends GdUnitTestSuite

## Procedural character blob + FieldCatalog companion shadow paths.


func test_precip_dims_blob_alpha() -> void:
	var base: float = 0.4
	var kind: Weather.Kind = Weather.kind_from_name(Game.town.weather)
	var scaled: float = ActorBlobShadow.precip_alpha(base)
	if Weather.is_precip(kind):
		assert_float(scaled).is_equal_approx(base * Weather.PRECIP_SHADOW_SCALE, 0.0001)
	else:
		assert_float(scaled).is_equal_approx(base, 0.0001)


func test_flat_transform_lifts_above_feet() -> void:
	var xform: Transform3D = ActorBlobShadow.flat_transform(Vector3(3.0, 1.5, -2.0), 0.0)
	assert_float(xform.origin.x).is_equal_approx(3.0, 0.0001)
	assert_float(xform.origin.z).is_equal_approx(-2.0, 0.0001)
	assert_float(xform.origin.y).is_equal_approx(1.5 + ActorBlobShadow.GROUND_LIFT, 0.0001)
	assert_float(xform.basis.y.y).is_greater(0.9)


func test_station_shadow_mask_is_tinted_and_the_ellipse_is_not() -> void:
	var host := MeshInstance3D.new()
	add_child(host)
	auto_free(host)
	host.mesh = BoxMesh.new()
	var station := StandardMaterial3D.new()
	station.resource_name = "obj_station1_shadow_hiT_model"
	station.albedo_color = Color.WHITE
	station.vertex_color_use_as_albedo = true
	station.set_meta("extras", {"ground_spill": true})
	host.set_surface_override_material(0, station)
	var ellipse_mesh := MeshInstance3D.new()
	ellipse_mesh.mesh = BoxMesh.new()
	var ellipse := StandardMaterial3D.new()
	ellipse.resource_name = "blob_shadow"
	var baked := Color(6.0 / 255.0, 10.0 / 255.0, 16.0 / 255.0, 1.0)
	ellipse.albedo_color = baked
	ellipse.set_meta("extras", {"ground_spill": true})
	ellipse_mesh.set_surface_override_material(0, ellipse)
	host.add_child(ellipse_mesh)
	VisualBlobShadow._apply_blob_shadow_materials(host)
	var tinted := host.get_surface_override_material(0) as StandardMaterial3D
	assert_float(tinted.albedo_color.r).is_equal_approx(0.0, 0.001)
	assert_float(tinted.albedo_color.b).is_equal_approx(70.0 / 255.0, 0.001)
	assert_float(tinted.albedo_color.a).is_equal_approx(180.0 / 255.0, 0.001)
	assert_bool(tinted.vertex_color_use_as_albedo).is_false()
	var kept := ellipse_mesh.get_surface_override_material(0) as StandardMaterial3D
	assert_that(kept.albedo_color).is_equal(baked)


func test_blob_shadow_paths_skip_self_and_empty() -> void:
	assert_int(FieldCatalog.blob_shadow_paths(&"").size()).is_equal(0)
	assert_int(FieldCatalog.blob_shadow_paths(&"obj_s_kouban_shadow").size()).is_equal(0)
	## Companion may be missing until convert re-runs; API must not crash.
	var paths: PackedStringArray = FieldCatalog.blob_shadow_paths(&"obj_s_kouban")
	for path: String in paths:
		assert_str(path).contains("_shadow")


func test_small_props_find_their_season_free_shadow() -> void:
	## `obj_tree5_shadow` / `obj_stoneA_shadow` serve every season (`bIT_ShadowData_c`).
	if not FileAccess.file_exists(FieldCatalog.GENERATED_ROOT + "environment/trees/obj_tree5_shadow.glb"):
		return
	for visual: StringName in [&"TREE", &"ROCK_A", &"CEDAR_TREE", &"TREE_PALM", &"SIGNBOARD"]:
		var paths: PackedStringArray = FieldCatalog.blob_shadow_paths(visual)
		assert_int(paths.size()).override_failure_message(String(visual)).is_equal(1)
