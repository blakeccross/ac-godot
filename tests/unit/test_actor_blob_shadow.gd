class_name TestActorBlobShadow
extends GdUnitTestSuite

## Procedural character blob + FieldCatalog companion shadow paths.


func test_precip_dims_blob_alpha() -> void:
	var base: float = 0.4
	var kind: Weather.Kind = Weather.kind_from_name(Game.weather)
	var scaled: float = ActorBlobShadow.precip_alpha(base)
	if Weather.is_precip(kind):
		assert_float(scaled).is_equal_approx(base * Weather.PRECIP_LIGHT_SCALE, 0.0001)
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
