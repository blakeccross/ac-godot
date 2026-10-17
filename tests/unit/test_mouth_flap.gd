extends GdUnitTestSuite

## `talk_type` 1 heads: joints 22–23 follow the `kutipaku` clip while a line utters.


func _model(code: String) -> Node3D:
	var path := "res://assets/generated/characters/villagers/%s_1.glb" % code
	if not ResourceLoader.exists(path):
		return null
	var host := Node3D.new()
	add_child(host)
	auto_free(host)
	host.add_child((load(path) as PackedScene).instantiate())
	return host


func test_clip_follows_the_draw_data_talk_type() -> void:
	assert_str(MouthFlap.clip_for(&"owl")).is_equal(MouthFlap.CLIP_ALT)
	assert_str(MouthFlap.clip_for(&"duk")).is_equal(MouthFlap.CLIP_ALT)
	assert_str(MouthFlap.clip_for(&"rcn")).is_equal(MouthFlap.CLIP_DEFAULT)
	assert_str(MouthFlap.clip_for(&"ttl")).is_equal(MouthFlap.CLIP_DEFAULT)
	## Goats and mice have a `mouth_*` bone but talk with a mouth texture.
	assert_str(MouthFlap.clip_for(&"goa")).is_empty()
	assert_str(MouthFlap.clip_for(&"mus")).is_empty()
	assert_str(MouthFlap.clip_for(&"cat")).is_empty()


func test_owl_beak_flaps_while_uttering_then_shuts() -> void:
	var host := _model("owl")
	if host == null:
		return
	var flap := MouthFlap.attach(host, &"owl")
	assert_object(flap).is_not_null()
	assert_object(MouthFlap.attach(host, &"owl")).is_same(flap)
	var skel := flap.get_skeleton()
	var bone := 23
	assert_str(skel.get_bone_name(bone)).is_equal("mouth_owl_model")

	flap._process_modification()
	var shut := skel.get_bone_pose_rotation(bone)
	flap.tick(0.1, true)
	flap._process_modification()
	assert_float(skel.get_bone_pose_rotation(bone).angle_to(shut)).is_greater(0.01)

	flap.tick(MouthFlap.TAIL_SECONDS * 0.5, false)
	assert_bool(flap.is_flapping()).is_true()
	flap.tick(MouthFlap.TAIL_SECONDS, false)
	flap.tick(0.016, false)
	assert_bool(flap.is_flapping()).is_false()
	flap._process_modification()
	assert_float(skel.get_bone_pose_rotation(bone).angle_to(shut)).is_less(0.001)


func test_npc_face_drives_nooks_snout() -> void:
	var host := _model("rcn")
	if host == null:
		return
	var face := NpcFace.new()
	face.bind(host, &"rcn")
	var flaps: Array[Node] = host.find_children("*", "MouthFlap", true, false)
	assert_int(flaps.size()).is_equal(1)
	var flap := flaps[0] as MouthFlap
	face.tick(0.1, true)
	assert_bool(flap.is_flapping()).is_true()


func test_texture_mouths_get_none() -> void:
	var host := _model("cat")
	if host == null:
		return
	assert_object(MouthFlap.attach(host, &"cat")).is_null()
	NpcFace.new().bind(host, &"cat")
	assert_int(host.find_children("*", "MouthFlap", true, false).size()).is_equal(0)
