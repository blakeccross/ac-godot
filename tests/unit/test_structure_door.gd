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


func test_walk_in_uses_into_not_open1() -> void:
	## `door_type != 0` (museum / police / shop) → INTO_S1; demo type 0 → OPEN1.
	assert_bool(StructureDoor.uses_walk_in(&"obj_s_museum")).is_true()
	assert_bool(StructureDoor.uses_walk_in(&"obj_s_kouban")).is_true()
	assert_bool(StructureDoor.uses_walk_in(&"obj_s_shop1")).is_true()
	assert_bool(StructureDoor.uses_walk_in(&"obj_s_myhome1")).is_false()
	assert_bool(StructureDoor.uses_walk_in(&"obj_s_tailor")).is_false()
	assert_bool(StructureDoor.uses_walk_in(&"obj_s_house1")).is_false()


func test_museum_exit_stand_is_south_of_door() -> void:
	## `aMsm_rewrite_out_data`: home + 120 GX south — past the +100 door and raised footprint.
	assert_that(StructureDoor.exit_offset_gx(&"obj_s_museum")).is_equal(StructureDoor.MUSEUM_EXIT_GX)
	assert_float(StructureDoor.MUSEUM_EXIT_GX.y).is_greater(HostCollision.MUSEUM_DOOR_GX.y)
	var root := Node3D.new()
	auto_free(root)
	root.position = Vector3(10.0, 0.0, 10.0)
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar visual_id: StringName = &\"obj_s_museum\"\n"
	script.reload()
	root.set_script(script)
	var tree_root := Node3D.new()
	auto_free(tree_root)
	add_child(tree_root)
	tree_root.add_child(root)
	var stand: Vector3 = StructureDoor.exit_stand(root)
	assert_float(stand.z).is_equal_approx(
		root.global_position.z + StructureDoor.MUSEUM_EXIT_GX.y * FieldCatalog.GX_TO_METERS, 0.01
	)


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
	assert_float(StructureDoor.leave_yaw(root, sensor.global_position)).is_equal_approx(0.0, 0.01)


func test_house_approach_uses_demo_stand_not_exit() -> void:
	## Player/villager OPEN1 stands are check/porch GX — not rewrite_out exit.
	assert_that(StructureDoor.approach_offset_gx(&"obj_s_myhome1")).is_equal(
		StructureDoor.PLAYER_APPROACH_GX
	)
	assert_that(StructureDoor.approach_offset_gx(&"obj_s_house1")).is_equal(
		StructureDoor.NPC_HOUSE_APPROACH_GX
	)
	assert_float(StructureDoor.PLAYER_APPROACH_GX.length()).is_less(
		Vector2(HostCollision.PLAYER_DOOR_GX, HostCollision.PLAYER_DOOR_GX).length()
	)
	assert_float(StructureDoor.NPC_HOUSE_APPROACH_GX.y).is_less(StructureDoor.NPC_HOUSE_EXIT_GX.y)
	var root := Node3D.new()
	auto_free(root)
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar visual_id: StringName = &\"obj_s_myhome1\"\n"
	script.reload()
	root.set_script(script)
	root.position = Vector3(5.0, 0.0, 5.0)
	var tree_root := Node3D.new()
	auto_free(tree_root)
	add_child(tree_root)
	tree_root.add_child(root)
	var stand: Vector3 = StructureDoor.approach_position(root)
	var s: float = FieldCatalog.GX_TO_METERS
	assert_float(stand.x).is_equal_approx(
		root.global_position.x + StructureDoor.PLAYER_APPROACH_GX.x * s, 0.05
	)
	assert_float(stand.z).is_equal_approx(
		root.global_position.z + StructureDoor.PLAYER_APPROACH_GX.y * s, 0.05
	)


func test_find_near_picks_closest_house() -> void:
	var tree_root := Node3D.new()
	auto_free(tree_root)
	add_child(tree_root)
	var near: Node3D = _fake_house(tree_root, "Near", Vector3(1.0, 0.0, 0.0), &"obj_s_house1")
	_fake_house(tree_root, "Far", Vector3(20.0, 0.0, 0.0), &"obj_s_house1")
	var found: Node3D = StructureDoor.find_near(tree_root, Vector3(0.0, 0.0, 0.0))
	assert_object(found).is_same(near)


func test_arrive_uses_spawn_as_animation_move_target() -> void:
	## Non-museum post-load INTO_S1: AnimationMove correctpos is the spawn; joint_0 clears sensors.
	assert_float(StructureDoor.INTO_GX).is_equal_approx(30.0, 0.01)
	assert_float(StructureDoor.INTO_SEC).is_equal_approx(49.0 / 30.0, 0.01)


func test_door_camera_distance_matches_follow() -> void:
	## CAMERA2_PROCESS_DOOR uses the same 620 focus as Init_Camera2.
	var cam_script = load("res://scenes/world/follow_camera.gd")
	assert_float(cam_script.ORIG_DISTANCE).is_equal_approx(620.0, 0.01)


func _fake_house(parent: Node, node_name: String, pos: Vector3, visual_id: StringName) -> Node3D:
	var host := Node3D.new()
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar visual_id: StringName = &\"\"\n"
	script.reload()
	host.set_script(script)
	host.name = node_name
	host.position = pos
	host.set("visual_id", visual_id)
	parent.add_child(host)
	host.add_to_group("interactable")
	var gv := Node3D.new()
	gv.name = "GeneratedVisual"
	host.add_child(gv)
	return host


func _player_with(names: PackedStringArray) -> AnimationPlayer:
	var anim := AnimationPlayer.new()
	auto_free(anim)
	var lib := AnimationLibrary.new()
	for name: String in names:
		lib.add_animation(name, Animation.new())
	anim.add_animation_library("", lib)
	return anim


func test_strip_joint0_only_on_named_door_clips() -> void:
	## INDEX_DOOR clips strip joint_0 after baking AnimationMove; wait keeps its track.
	var anim := AnimationPlayer.new()
	auto_free(anim)
	var lib := AnimationLibrary.new()
	for clip_name: String in ["ply_1_into_s1", "ply_1_wait1"]:
		var animation := Animation.new()
		var track: int = animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(track, NodePath("Armature/Skeleton3D:joint_0"))
		animation.position_track_insert_key(track, 0.0, Vector3(0.0, 1.0, 0.0))
		animation.position_track_insert_key(track, 1.0, Vector3(0.0, 1.0, 6.4))
		lib.add_animation(clip_name, animation)
	anim.add_animation_library("", lib)
	GeneratedVisual.strip_named_joint_tracks(
		anim, "joint_0", PackedStringArray(["ply_1_into_s1"])
	)
	assert_int(anim.get_animation("ply_1_into_s1").get_track_count()).is_equal(0)
	assert_int(anim.get_animation("ply_1_wait1").get_track_count()).is_equal(1)


func test_animation_move_counter_matches_decomp() -> void:
	## `AnimationMove_ct_base(..., 9.0f, flag 5)` at −0.5 / 60 Hz frame → ~0.3 s.
	assert_float(StructureDoor.ANIM_MOVE_COUNTER).is_equal_approx(9.0, 0.01)
	assert_float(StructureDoor.ANIM_MOVE_HZ).is_equal_approx(60.0, 0.01)
	assert_float(
		StructureDoor.ANIM_MOVE_COUNTER / 0.5 / StructureDoor.ANIM_MOVE_HZ
	).is_equal_approx(StructureDoor.APPROACH_SEC, 0.01)
	assert_float(StructureDoor.OPEN1_SEC).is_equal_approx(65.0 / 30.0, 0.01)
