extends GdUnitTestSuite

## `aMHS_actor_draw_before` joints 3 / 5: the fish weathervane follows the wind.


func test_turn_axis_follows_house_size() -> void:
	var quarter := 0x4000
	var small := HouseWeathervane.turn(0, quarter)
	assert_vector(small * Vector3.BACK).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 0.001)
	var large := HouseWeathervane.turn(2, quarter)
	assert_vector(large * Vector3.UP).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.001)


func test_attaches_to_the_house_skeleton_and_turns_the_vane() -> void:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(&"obj_s_myhome1")
	if paths.is_empty():
		return
	var host := Node3D.new()
	add_child(host)
	host.add_child((load(paths[0]) as PackedScene).instantiate())
	var vane := HouseWeathervane.attach(host, 0, 0)
	assert_object(vane).is_not_null()
	var skel := vane.get_skeleton()
	var bone := -1
	for i: int in skel.get_bone_count():
		if skel.get_bone_name(i).ends_with(HouseWeathervane.VANE_SUFFIX):
			bone = i
	assert_int(bone).is_greater_equal(0)
	vane._process_modification()
	var rest := skel.get_bone_rest(bone).basis.get_rotation_quaternion()
	var want := HouseWeathervane.turn(0, float(Wind.angle_s())) * rest
	assert_float(skel.get_bone_pose_rotation(bone).angle_to(want)).is_less(0.001)
	host.queue_free()
