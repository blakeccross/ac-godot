class_name TestMissingModel
extends GdUnitTestSuite

## `GeneratedVisual.mark_missing`: the one stand-in for a visual with no generated model.

const NO_SUCH_VISUAL := &"obj_no_such_model_for_test"


func _host() -> Node3D:
	var host := Node3D.new()
	add_child(host)
	auto_free(host)
	return host


func test_marker_is_one_box_sized_and_tinted_by_the_caller() -> void:
	var host: Node3D = _host()
	var marker: MissingModel = GeneratedVisual.mark_missing(
		host, NO_SUCH_VISUAL, Color(0.2, 0.4, 0.6), Vector3(0.8, 1.0, 0.4)
	)
	assert_that(marker).is_not_null()
	assert_that(marker.get_parent()).is_same(host)
	var box := marker.get_node("Box") as MeshInstance3D
	assert_vector((box.mesh as BoxMesh).size).is_equal_approx(Vector3(0.8, 1.0, 0.4), Vector3(0.001, 0.001, 0.001))
	assert_float(box.position.y).is_equal_approx(0.5, 0.001)
	var material := box.material_override as StandardMaterial3D
	assert_bool(material.albedo_color.is_equal_approx(Color(0.2, 0.4, 0.6))).is_true()
	assert_int(material.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_DISABLED)


func test_ungrounded_marker_centres_on_the_origin_and_alpha_goes_translucent() -> void:
	var host: Node3D = _host()
	var marker: MissingModel = GeneratedVisual.mark_missing(
		host, NO_SUCH_VISUAL, Color(0.1, 0.1, 0.1, 0.5), Vector3.ONE
	)
	marker.grounded = false
	var box := marker.get_node("Box") as MeshInstance3D
	assert_float(box.position.y).is_equal_approx(0.0, 0.001)
	assert_int((box.material_override as StandardMaterial3D).transparency).is_equal(
		BaseMaterial3D.TRANSPARENCY_ALPHA
	)


func test_marking_twice_reuses_the_marker() -> void:
	var host: Node3D = _host()
	var first: MissingModel = GeneratedVisual.mark_missing(host, NO_SUCH_VISUAL)
	var second: MissingModel = GeneratedVisual.mark_missing(host, NO_SUCH_VISUAL, Color.RED, Vector3.ONE)
	assert_that(second).is_same(first)
	assert_int(host.get_child_count()).is_equal(1)


func test_markers_do_not_share_a_material() -> void:
	var one: MissingModel = GeneratedVisual.mark_missing(_host(), NO_SUCH_VISUAL, Color.RED)
	var two: MissingModel = GeneratedVisual.mark_missing(_host(), NO_SUCH_VISUAL, Color.BLUE)
	var red := (one.get_node("Box") as MeshInstance3D).material_override as StandardMaterial3D
	var blue := (two.get_node("Box") as MeshInstance3D).material_override as StandardMaterial3D
	assert_bool(red.albedo_color.is_equal_approx(Color.RED)).is_true()
	assert_bool(blue.albedo_color.is_equal_approx(Color.BLUE)).is_true()


func test_detach_removes_the_marker() -> void:
	var host: Node3D = _host()
	GeneratedVisual.mark_missing(host, NO_SUCH_VISUAL)
	GeneratedVisual.detach(host)
	await get_tree().process_frame
	assert_that(host.get_node_or_null(GeneratedVisual.MISSING_NODE)).is_null()
	## A same-frame mark after a detach gets a fresh marker, not the one being freed.
	assert_that(GeneratedVisual.mark_missing(host, NO_SUCH_VISUAL)).is_not_null()
	assert_int(host.get_child_count()).is_equal(1)


func test_furniture_without_a_model_shows_the_marker_sized_to_its_footprint() -> void:
	var furniture := load("res://scenes/world/furniture.tscn").instantiate() as StaticBody3D
	## The scene's default `data` would override `visual_id`.
	furniture.set("data", null)
	furniture.set("visual_id", NO_SUCH_VISUAL)
	furniture.set("footprint", Vector2i(2, 1))
	add_child(furniture)
	auto_free(furniture)
	var marker := furniture.get_node_or_null(GeneratedVisual.MISSING_NODE) as MissingModel
	assert_that(marker).is_not_null()
	assert_float(marker.size.x).is_equal_approx(2.0 * 2.0 * 0.85 * 0.7, 0.001)
	assert_float(marker.size.z).is_equal_approx(1.0 * 2.0 * 0.85 * 0.7, 0.001)
