class_name TestIntroTrainStage
extends GdUnitTestSuite

## GX landmarks + stage cues for the Rover train demo.


func test_gx_to_meters_matches_field_catalog() -> void:
	var p: Vector3 = IntroTrainStage.gx_to_meters(Vector3(100.0, 80.0, 400.0))
	assert_float(p.x).is_equal_approx(100.0 * FieldCatalog.GX_TO_METERS, 0.0001)
	assert_float(p.y).is_equal_approx(80.0 * FieldCatalog.GX_TO_METERS, 0.0001)
	assert_float(p.z).is_equal_approx(400.0 * FieldCatalog.GX_TO_METERS, 0.0001)


func test_intro_pipeline_scales_match_decomp_draw() -> void:
	## `m_actor.c` 0.01, `ac_field_draw` 0.0625, `ac_train_window` 0.05.
	assert_float(FieldCatalog.actor_uniform_scale()).is_equal_approx(0.5, 0.0001)
	assert_float(FieldCatalog.acre_uniform_scale()).is_equal_approx(3.125, 0.0001)
	assert_float(FieldCatalog.train_window_uniform_scale()).is_equal_approx(2.5, 0.0001)


func test_door_actor_origin_before_rover_door_stop() -> void:
	## Door actor sits in the vestibule alcove; Rover stops further in the aisle.
	assert_float(IntroTrainStage.DOOR_GATE_GX.z).is_equal(120.0)
	assert_float(IntroTrainStage.ROVER_DOOR_GX.z).is_equal(130.0)


func test_sitdown_snaps_rover_landmarks() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	for _i: int in 220:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.TALK:
			break
	stage.cue_sit()
	for _i: int in 120:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.SITDOWN:
			break
	assert_vector(stage._pos_gx).is_equal_approx(IntroTrainStage.ROVER_SIT_GX, Vector3(0.001, 0.001, 0.001))
	assert_float(stage._yaw).is_equal_approx(0.0, 0.001)
	rover.queue_free()


func test_required_assets_list_train_set() -> void:
	var paths: PackedStringArray = IntroTrainStage.required_asset_paths()
	assert_int(paths.size()).is_equal(6)
	assert_str(paths[0]).contains("rom_train_in")
	assert_str(paths[2]).contains("obj_romtrain_door")
	assert_str(paths[3]).contains("xct_1")
	assert_str(paths[4]).contains("kab_1")
	assert_str(paths[5]).contains("tol_keitai_1")


func test_bind_starts_enter_and_emits_talk_without_mesh() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	var door := Node3D.new()
	var keitai := Node3D.new()
	var cam := Camera3D.new()
	add_child(rover)
	add_child(door)
	add_child(keitai)
	add_child(cam)
	var talked := [false]
	stage.ready_for_talk.connect(func() -> void: talked[0] = true)
	stage.bind(rover, null, door, keitai, cam)
	assert_that(stage.action).is_equal(IntroTrainStage.Action.ENTER)
	## No AnimationPlayer → enter finishes immediately; walk 160 GX @ 1 GX/tick.
	for _i: int in 220:
		stage.tick(1.0 / 30.0)
		if talked[0]:
			break
	assert_that(talked[0]).is_true()
	assert_that(stage.action).is_equal(IntroTrainStage.Action.TALK)
	rover.queue_free()
	door.queue_free()
	keitai.queue_free()
	cam.queue_free()


func test_bind_places_camera_near_decomp_eye() -> void:
	var stage := IntroTrainStage.new()
	var cam := Camera3D.new()
	add_child(cam)
	stage.bind(null, null, null, null, cam)
	var expected: Vector3 = IntroTrainStage.gx_to_meters(IntroTrainStage.CAM_EYE_GX)
	## Sway adds ~0.1 GX on the first frame; allow that slack.
	assert_vector(cam.global_position).is_equal_approx(
		expected, Vector3(0.01, 0.01, 0.01)
	)
	assert_float(cam.fov).is_equal_approx(IntroTrainStage.CAM_FOV, 0.001)
	assert_float(cam.near).is_equal_approx(
		IntroTrainStage.CAM_NEAR_METERS, 0.0001
	)
	assert_float(cam.far).is_equal_approx(
		IntroTrainStage.CAM_FAR_GX * FieldCatalog.GX_TO_METERS, 0.0001
	)
	cam.queue_free()


func test_approach_keeps_rover_in_aisle() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	for _i: int in 200:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.TALK:
			break
	assert_that(stage.action).is_equal(IntroTrainStage.Action.TALK)
	var aisle_x: float = IntroTrainStage.gx_to_meters(
		Vector3(IntroTrainStage.ROVER_AISLE_X_GX, 0.0, 0.0)
	).x
	assert_float(rover.global_position.x).is_equal_approx(aisle_x, 0.02)
	assert_float(rover.global_position.z).is_equal_approx(
		IntroTrainStage.gx_to_meters(IntroTrainStage.ROVER_TALK_GX).z, 0.02
	)
	rover.queue_free()


func test_resolve_rover_clip_prefers_exact_sitdown() -> void:
	var anim := AnimationPlayer.new()
	add_child(anim)
	anim.add_animation_library(
		"",
		AnimationLibrary.new()
	)
	var library: AnimationLibrary = anim.get_animation_library("")
	library.add_animation(&"npc_1_sitdown_wait_d1", Animation.new())
	library.add_animation(&"npc_1_sitdown_d1", Animation.new())
	assert_str(IntroTrainStage.resolve_rover_clip(anim, "npc_1_sitdown_d1")).is_equal(
		"npc_1_sitdown_d1"
	)
	anim.queue_free()


func test_talk_yaw_faces_player_at_aisle() -> void:
	var yaw: float = IntroTrainStage.yaw_toward_player(IntroTrainStage.ROVER_TALK_GX)
	assert_float(yaw).is_less(0.0)
	assert_float(yaw).is_greater(-1.0)


func test_rover_anim_blend_matches_decomp_morph() -> void:
	assert_float(IntroTrainStage._rover_anim_blend(IntroTrainStage.ANIM_OPEN_D1)).is_equal(0.0)
	assert_float(IntroTrainStage._rover_anim_blend(IntroTrainStage.ANIM_SITDOWN)).is_equal(0.0)
	assert_float(IntroTrainStage._rover_anim_blend(IntroTrainStage.ANIM_STANDUP)).is_equal(0.0)
	assert_float(IntroTrainStage._rover_anim_blend(IntroTrainStage.ANIM_WALK)).is_equal_approx(
		IntroTrainStage.ANIM_MORPH_BLEND, 0.0001
	)


func test_sleep_npc_spawn_matches_decomp() -> void:
	var spawn: Vector3 = IntroTrainSleepNpc.SPAWN_GX
	assert_vector(IntroTrainStage.gx_to_meters(spawn)).is_equal_approx(
		IntroTrainStage.gx_to_meters(Vector3(174.0, 0.0, 156.0)),
		Vector3(0.001, 0.001, 0.001)
	)
	## Search-turn toward player for the seated GC frame.
	var yaw: float = IntroTrainSleepNpc.spawn_yaw()
	assert_float(yaw).is_equal_approx(
		IntroTrainStage.yaw_toward_player(IntroTrainSleepNpc.SPAWN_GX), 0.001
	)


func test_return_flow_reaches_aisle_talk_after_phone_done() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	for _i: int in 220:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.TALK:
			break
	stage.cue_sit()
	for _i: int in 120:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.SEATED:
			break
	stage.cue_phone()
	for _i: int in 400:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.KEITAI_TALK:
			break
	stage.end_phone_talk()
	for _i: int in 400:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.TALK:
			break
	assert_that(stage.action).is_equal(IntroTrainStage.Action.TALK)
	assert_float(stage._pos_gx.z).is_equal_approx(IntroTrainStage.ROVER_TALK_GX.z, 0.05)
	rover.queue_free()


func test_cue_return_does_not_skip_to_open_door_mid_walk() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	for _i: int in 220:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.TALK:
			break
	stage.cue_sit()
	for _i: int in 120:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.SEATED:
			break
	stage.cue_phone()
	for _i: int in 30:
		stage.tick(1.0 / 30.0)
	stage.end_phone_talk()
	assert_that(stage.action).is_not_equal(IntroTrainStage.Action.OPEN_DOOR)
	rover.queue_free()


func test_cue_return_sit_plays_sitdown_after_phone_return() -> void:
	## `aNGD_sitdown2` — Rover sits again once the farewell talk starts.
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	stage._phone_trip_started = true
	stage.action = IntroTrainStage.Action.TALK
	stage._pos_gx = IntroTrainStage.ROVER_TALK_GX
	stage.cue_return_sit()
	assert_that(stage.action).is_equal(IntroTrainStage.Action.SITDOWN)
	assert_vector(stage._pos_gx).is_equal_approx(
		IntroTrainStage.ROVER_SIT_GX, Vector3(0.001, 0.001, 0.001)
	)
	assert_that(stage.stage_wait_met("return_seated")).is_false()
	stage.action = IntroTrainStage.Action.SEATED
	assert_that(stage.stage_wait_met("return_seated")).is_true()
	rover.queue_free()


func test_cue_return_sit_arms_pending_while_still_on_phone() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	stage._phone_trip_started = true
	stage.action = IntroTrainStage.Action.MOVE_DOOR
	stage.cue_return_sit()
	assert_that(stage.action).is_equal(IntroTrainStage.Action.MOVE_DOOR)
	assert_that(stage._pending_return_sit).is_true()
	stage._pos_gx = IntroTrainStage.ROVER_TALK_GX
	stage._set_action(IntroTrainStage.Action.TALK)
	assert_that(stage.action).is_equal(IntroTrainStage.Action.SITDOWN)
	rover.queue_free()


func test_dialogue_gate_blocks_phone_until_keitai_talk() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	stage.cue_phone()
	for _i: int in 20:
		stage.tick(1.0 / 30.0)
	assert_that(stage.can_advance_dialogue(&"phone_lead", &"phone_stage")).is_true()
	assert_that(stage.stage_wait_met("keitai_talk")).is_false()
	assert_that(stage.can_advance_dialogue(&"phone_stage", &"phone_call")).is_false()
	for _i: int in 400:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.KEITAI_TALK:
			break
	assert_that(stage.stage_wait_met("keitai_talk")).is_true()
	assert_that(stage.can_advance_dialogue(&"phone_stage", &"phone_call")).is_true()
	rover.queue_free()


func test_stage_wait_seated_after_sit() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	stage.cue_sit()
	assert_that(stage.stage_wait_met("seated")).is_false()
	for _i: int in 30:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.SEATED:
			break
	assert_that(stage.stage_wait_met("seated")).is_true()
	rover.queue_free()


func test_cue_sit_snaps_to_seat_and_sits() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	for _i: int in 220:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.TALK:
			break
	stage.cue_sit()
	assert_that(stage.action).is_equal(IntroTrainStage.Action.SITDOWN)
	for _i: int in 8:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.SEATED:
			break
	assert_that(stage.action).is_equal(IntroTrainStage.Action.SEATED)
	assert_vector(rover.global_position).is_equal_approx(
		IntroTrainStage.gx_to_meters(IntroTrainStage.ROVER_SIT_GX),
		Vector3(0.02, 0.02, 0.02)
	)
	rover.queue_free()


func test_sitdown_camera_morphs_from_aisle_talk() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	for _i: int in 260:
		stage.tick(1.0 / 30.0)
		if stage.lock_camera and stage.action == IntroTrainStage.Action.TALK:
			break
	stage.cue_sit()
	assert_that(stage.action).is_equal(IntroTrainStage.Action.SITDOWN)
	assert_float(stage._camera_morph_from_gx.x).is_equal_approx(
		IntroTrainStage.ROVER_TALK_GX.x, 0.001
	)
	assert_float(stage._camera_morph_from_gx.z).is_equal_approx(
		IntroTrainStage.ROVER_TALK_GX.z, 0.001
	)
	assert_float(stage._camera_morph_from_gx.x).is_not_equal(IntroTrainStage.CAM_LOOK_GX.x)
	assert_that(stage._camera_morph_tracks_rover).is_true()
	rover.queue_free()


func test_sitdown_steady_look_tracks_rover_on_bench() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	stage.action = IntroTrainStage.Action.SITDOWN
	stage.obj_look_talk = true
	stage.camera_morph = 0
	stage.lock_camera = false
	stage._pos_gx = IntroTrainStage.ROVER_SIT_GX
	stage._obj_look_y_gx = IntroTrainStage.OBJ_LOOK_Y_TALK_GX
	var look_gx: Vector3 = stage._steady_camera_look_gx(stage._pos_gx)
	assert_float(look_gx.x).is_equal_approx(IntroTrainStage.ROVER_SIT_GX.x, 0.001)
	assert_float(look_gx.z).is_equal_approx(IntroTrainStage.ROVER_SIT_GX.z, 0.001)
	assert_float(look_gx.x).is_not_equal(IntroTrainStage.CAM_LOOK_GX.x)
	rover.queue_free()


func test_standup_moves_host_before_anim() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	stage.action = IntroTrainStage.Action.SEATED
	stage._pos_gx = IntroTrainStage.ROVER_SIT_GX
	stage.cue_phone()
	assert_that(stage.action).is_equal(IntroTrainStage.Action.STANDUP)
	assert_vector(stage._pos_gx).is_equal_approx(
		IntroTrainStage.ROVER_STAND_GX, Vector3(0.001, 0.001, 0.001)
	)
	rover.queue_free()


func test_standup_keeps_camera_locked_on_rover() -> void:
	## Decomp never clears `lock_camera_flag` — look follows Rover to the phone.
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	stage.action = IntroTrainStage.Action.SEATED
	stage._pos_gx = IntroTrainStage.ROVER_SIT_GX
	stage.lock_camera = true
	stage.obj_look_talk = true
	stage._obj_look_y_gx = IntroTrainStage.OBJ_LOOK_Y_TALK_GX
	stage.cue_phone()
	assert_that(stage.action).is_equal(IntroTrainStage.Action.STANDUP)
	assert_that(stage.lock_camera).is_true()
	assert_float(stage._obj_look_y_target_gx).is_equal_approx(
		IntroTrainStage.OBJ_LOOK_Y_NORMAL_GX, 0.001
	)
	var look_gx: Vector3 = stage._steady_camera_look_gx(stage._pos_gx)
	assert_float(look_gx.x).is_equal_approx(IntroTrainStage.ROVER_STAND_GX.x, 0.001)
	assert_float(look_gx.z).is_equal_approx(IntroTrainStage.ROVER_STAND_GX.z, 0.001)
	rover.queue_free()


func test_phone_walk_steady_look_tracks_rover() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	stage.action = IntroTrainStage.Action.MOVE_DOOR
	stage.obj_look_talk = true
	stage.camera_morph = 0
	stage.lock_camera = true
	stage._pos_gx = Vector3(140.0, 0.0, 200.0)
	stage._obj_look_y_gx = IntroTrainStage.OBJ_LOOK_Y_NORMAL_GX
	var look_gx: Vector3 = stage._steady_camera_look_gx(stage._pos_gx)
	assert_float(look_gx.x).is_equal_approx(140.0, 0.001)
	assert_float(look_gx.z).is_equal_approx(200.0, 0.001)
	assert_float(look_gx.x).is_not_equal(IntroTrainStage.CAM_LOOK_GX.x)
	rover.queue_free()


func test_phone_tilt_starts_when_rover_nears_vestibule() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	stage.action = IntroTrainStage.Action.MOVE_DOOR
	stage.lock_camera = true
	stage._pos_gx = Vector3(140.0, 0.0, 145.0)
	stage._speed_gx = IntroTrainStage.WALK_SPEED2_GX
	assert_float(stage.phone_tilt_goal()).is_equal_approx(0.0, 0.001)
	## Cross z=140 while walking toward the door.
	for _i: int in 20:
		stage._tick_move_door(1.0 / 30.0)
		if stage._pos_gx.z < IntroTrainStage.CAMERA_TILT_Z_GX:
			break
	assert_that(stage._pos_gx.z < IntroTrainStage.CAMERA_TILT_Z_GX).is_true()
	assert_float(stage.phone_tilt_goal()).is_equal_approx(
		IntroTrainStage.CAMERA_TILT_GOAL_PHONE, 0.001
	)
	rover.queue_free()


func test_return_approach_steady_look_tracks_rover() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	stage.action = IntroTrainStage.Action.RETURN_APPROACH
	stage.obj_look_talk = true
	stage.camera_morph = 0
	stage.lock_camera = false
	stage._pos_gx = IntroTrainStage.ROVER_RETURN_START_GX
	stage._obj_look_y_gx = IntroTrainStage.OBJ_LOOK_Y_TALK_GX
	var look_gx: Vector3 = stage._steady_camera_look_gx(stage._pos_gx)
	assert_float(look_gx.x).is_equal_approx(IntroTrainStage.ROVER_RETURN_START_GX.x, 0.001)
	assert_float(look_gx.z).is_equal_approx(IntroTrainStage.ROVER_RETURN_START_GX.z, 0.001)
	rover.queue_free()


func test_second_talk_stays_locked_without_remorph() -> void:
	## Return talk keeps `lock_camera` — no aisle-POV remorph.
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	stage.action = IntroTrainStage.Action.RETURN_APPROACH
	stage._pos_gx = IntroTrainStage.ROVER_TALK_GX
	stage.obj_look_talk = true
	stage.camera_morph = 0
	stage.lock_camera = true
	stage._obj_look_y_gx = IntroTrainStage.OBJ_LOOK_Y_NORMAL_GX
	stage._set_action(IntroTrainStage.Action.TALK)
	assert_that(stage.lock_camera).is_true()
	assert_that(stage.camera_morph).is_equal(0)
	assert_float(stage._obj_look_y_target_gx).is_equal_approx(
		IntroTrainStage.OBJ_LOOK_Y_TALK_GX, 0.001
	)
	rover.queue_free()


func test_keitai_on_off_plays_phone_mesh_clips() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	var keitai := IntroTrainKeitai.new()
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	var on_anim := Animation.new()
	on_anim.length = 1.0
	var off_anim := Animation.new()
	off_anim.length = 1.0
	lib.add_animation(&"tol_keitai_1_keitai_on1", on_anim)
	lib.add_animation(&"tol_keitai_1_keitai_off1", off_anim)
	anim.add_animation_library(&"", lib)
	keitai.add_child(anim)
	add_child(rover)
	add_child(keitai)
	stage.bind(rover, null, null, keitai, null)
	assert_that(keitai.visible).is_false()
	stage._set_action(IntroTrainStage.Action.KEITAI_ON)
	assert_that(keitai.visible).is_true()
	assert_str(String(anim.current_animation)).contains("keitai_on")
	assert_float(anim.speed_scale).is_equal_approx(IntroTrainStage.KEITAI_ON_ANIM_SPEED, 0.001)
	stage._set_action(IntroTrainStage.Action.KEITAI_OFF)
	assert_str(String(anim.current_animation)).contains("keitai_off")
	stage._set_action(IntroTrainStage.Action.OPEN_DOOR)
	assert_that(keitai.visible).is_false()
	rover.queue_free()
	keitai.queue_free()


func test_keitai_binds_to_hand_bone() -> void:
	var rover := IntroTrainRoverAnim.new()
	rover.name = "Rover"
	var skel := Skeleton3D.new()
	for i: int in 21:
		skel.add_bone("joint_%d" % i)
		if i > 0:
			skel.set_bone_parent(i, i - 1)
	var vis := Node3D.new()
	vis.name = "GeneratedVisual"
	vis.add_child(skel)
	rover.add_child(vis)
	var keitai := IntroTrainKeitai.new()
	rover.add_child(keitai)
	add_child(rover)
	assert_that(keitai.bind_to_hand()).is_true()
	var attach: BoneAttachment3D = skel.get_node_or_null(IntroTrainKeitai.ATTACH_NAME) as BoneAttachment3D
	assert_that(attach).is_not_null()
	assert_str(attach.bone_name).is_equal(HeldTool.HAND_BONE)
	assert_that(keitai.get_parent()).is_same(attach)
	assert_vector(keitai.position).is_equal(Vector3.ZERO)
	assert_vector(keitai.scale).is_equal(Vector3.ONE)
	rover.queue_free()
