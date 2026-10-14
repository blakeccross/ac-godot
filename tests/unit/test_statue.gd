extends GdUnitTestSuite

## `ac_douzou`: which figure, face and colours the station statue shows.


func test_face_tables_follow_eye_and_mouth_tbl() -> void:
	assert_str(Statue.face_texture_symbol(false, false, 0)).is_equal("obj_s_douzou_b1_tex_pic_i4")
	assert_str(Statue.face_texture_symbol(true, true, 2)).is_equal("obj_w_douzou_g3_tex_pic_i4")
	## The seventh girl face borrows boy 7's eyes.
	assert_str(Statue.face_texture_symbol(false, true, 6)).is_equal("obj_s_douzou_b7_tex_pic_i4")
	assert_str(Statue.mouth_texture_symbol(false, false, 0)).is_equal("obj_s_douzou_bm2_tex_pic_i4")
	assert_str(Statue.mouth_texture_symbol(false, false, 1)).is_equal("obj_s_douzou_bm1_tex_pic_i4")
	assert_str(Statue.mouth_texture_symbol(false, true, 4)).is_equal("obj_s_douzou_gm2_tex_pic_i4")


func test_shown_only_for_a_statue_house() -> void:
	var house := House.new()
	assert_bool(Statue.shown_for(house)).is_false()
	house.next_size_tier = House.SizeTier.STATUE
	assert_bool(Statue.shown_for(house)).is_true()


func test_hiding_a_figure_drops_its_triangles() -> void:
	var model: Node3D = GeneratedVisual.instantiate_raw(&"obj_s_douzou")
	if model == null:
		return
	add_child(model)
	var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var mi := skel.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var boy := Statue._without_bones(mi.mesh, mi.skin, skel, Statue._bones(skel, Statue.FEMALE_BONES))
	var girl := Statue._without_bones(mi.mesh, mi.skin, skel, Statue._bones(skel, Statue.MALE_BONES))
	assert_int(_tris(boy)).is_less(_tris(mi.mesh))
	assert_int(_tris(girl)).is_less(_tris(mi.mesh))
	assert_int(_tris(boy) + _tris(girl)).is_greater(_tris(mi.mesh))
	model.queue_free()


func _tris(mesh: Mesh) -> int:
	var n := 0
	for s: int in mesh.get_surface_count():
		var idx: Variant = mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else 0
	return n
