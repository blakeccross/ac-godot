class_name TestStructureDoor
extends GdUnitTestSuite

## Clip pick for outdoor structure doors (`ac_house` / `ac_my_house` / `ac_shop`).


func test_villager_house_enter_uses_out_clip() -> void:
	var anim: AnimationPlayer = _player_with(["obj_s_house1", "obj_s_house1_out"])
	assert_str(StructureDoor.enter_clip(anim, &"obj_s_house1")).is_equal("obj_s_house1_out")
	assert_str(StructureDoor.leave_clip(anim, &"obj_s_house1")).is_equal("obj_s_house1")


func test_player_house_enter_uses_base_clip() -> void:
	var anim: AnimationPlayer = _player_with(["obj_s_myhome1", "obj_s_myhome1_out"])
	assert_str(StructureDoor.enter_clip(anim, &"obj_s_myhome1")).is_equal("obj_s_myhome1")
	assert_str(StructureDoor.leave_clip(anim, &"obj_s_myhome1")).is_equal("obj_s_myhome1_out")


func test_shop_enter_uses_base_clip() -> void:
	var anim: AnimationPlayer = _player_with(["obj_s_shop1"])
	assert_str(StructureDoor.enter_clip(anim, &"obj_s_shop1")).is_equal("obj_s_shop1")
	assert_str(StructureDoor.leave_clip(anim, &"obj_s_shop1")).is_equal("obj_s_shop1")


func test_missing_visual_falls_back_to_library() -> void:
	var anim: AnimationPlayer = _player_with(["obj_s_house2", "obj_s_house2_out"])
	assert_str(StructureDoor.enter_clip(anim, &"")).is_equal("obj_s_house2_out")


func test_winter_mesh_matches_summer_visual_id() -> void:
	## Hosts keep `obj_s_*` ids; GeneratedVisual loads `obj_w_*` in winter.
	var house: AnimationPlayer = _player_with(["obj_w_house1", "obj_w_house1_out"])
	assert_str(StructureDoor.enter_clip(house, &"obj_s_house1")).is_equal("obj_w_house1_out")
	var home: AnimationPlayer = _player_with(["obj_w_myhome1", "obj_w_myhome1_out"])
	assert_str(StructureDoor.enter_clip(home, &"obj_s_myhome1")).is_equal("obj_w_myhome1")


func test_approach_steps_toward_building() -> void:
	var root := Node3D.new()
	auto_free(root)
	root.position = Vector3(10.0, 0.0, 10.0)
	var sensor := Node3D.new()
	sensor.name = "InteractVolume"
	sensor.position = Vector3(0.0, 1.0, 2.0)
	root.add_child(sensor)
	## Must be in a tree for global_position.
	var tree_root := Node3D.new()
	auto_free(tree_root)
	add_child(tree_root)
	tree_root.add_child(root)
	var target: Vector3 = StructureDoor.approach_position(root)
	assert_float(target.z).is_less(sensor.global_position.z)
	assert_float(StructureDoor.enter_yaw(root, sensor.global_position)).is_equal_approx(PI, 0.01)


func _player_with(names: PackedStringArray) -> AnimationPlayer:
	var anim := AnimationPlayer.new()
	auto_free(anim)
	var lib := AnimationLibrary.new()
	for name: String in names:
		lib.add_animation(name, Animation.new())
	anim.add_animation_library("", lib)
	return anim
