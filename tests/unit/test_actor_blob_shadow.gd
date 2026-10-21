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
