class_name TestIntroTrainStage
extends GdUnitTestSuite

## GX landmarks + stage cues for the Rover train demo.


func test_gx_to_meters_matches_field_catalog() -> void:
	var p: Vector3 = IntroTrainStage.gx_to_meters(Vector3(100.0, 80.0, 400.0))
	assert_float(p.x).is_equal_approx(100.0 * FieldCatalog.GX_TO_METERS, 0.0001)
	assert_float(p.y).is_equal_approx(80.0 * FieldCatalog.GX_TO_METERS, 0.0001)
	assert_float(p.z).is_equal_approx(400.0 * FieldCatalog.GX_TO_METERS, 0.0001)


func test_required_assets_list_train_set() -> void:
	var paths: PackedStringArray = IntroTrainStage.required_asset_paths()
	assert_int(paths.size()).is_equal(5)
	assert_str(paths[0]).contains("rom_train_in")
	assert_str(paths[2]).contains("obj_romtrain_door")
	assert_str(paths[3]).contains("cat_1")
	assert_str(paths[4]).contains("tol_keitai_1")


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
	stage.bind(rover, null, door, null, keitai, cam)
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
	stage.bind(null, null, null, null, null, cam)
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
	stage.bind(rover, null, null, null, null, null)
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


func test_cue_sit_walks_to_seat_before_sitting() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null, null)
	for _i: int in 220:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.TALK:
			break
	stage.cue_sit()
	stage.tick(0.0)
	assert_that(stage.action).is_equal(IntroTrainStage.Action.MOVE_TO_SEAT)
	for _i: int in 120:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.SEATED:
			break
	assert_that(stage.action).is_equal(IntroTrainStage.Action.SEATED)
	assert_vector(rover.global_position).is_equal_approx(
		IntroTrainStage.gx_to_meters(IntroTrainStage.ROVER_SIT_GX),
		Vector3(0.02, 0.02, 0.02)
	)
	rover.queue_free()
