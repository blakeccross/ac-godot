class_name TestIntroTrainScene
extends GdUnitTestSuite

## Intro scene load + dialogue stage cues wired to `IntroTrainStage`.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	DialogueCatalog.reset()


func after_test() -> void:
	DialogueCatalog.reset()
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_intro_scene_loads_and_has_stage_hosts() -> void:
	var packed: PackedScene = load("res://scenes/ui/intro_train.tscn")
	assert_that(packed).is_not_null()
	var scene: Node3D = auto_free(packed.instantiate()) as Node3D
	assert_that(scene).is_not_null()
	add_child(scene)
	await get_tree().process_frame
	assert_that(scene.get_node_or_null("%TrainCar")).is_not_null()
	assert_that(scene.get_node_or_null("%Rover")).is_not_null()
	assert_that((scene.get_node("%Rover") as Node3D).get_node_or_null("AnimationTree")).is_not_null()
	assert_that(scene.get_node_or_null("%StageSync")).is_not_null()
	assert_that(scene.get_node_or_null("%IntroCameraRig")).is_not_null()
	assert_that(scene.get_node_or_null("%IntroCamera")).is_not_null()
	assert_that(scene.get_node_or_null("%DialogueOverlay")).is_not_null()
	assert_that(scene.get_node_or_null("%MissingBanner")).is_not_null()
	var keitai: Node = scene.get_node_or_null("%Keitai")
	assert_that(keitai).is_not_null()
	assert_that(keitai is IntroTrainKeitai).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	var attach: Node = keitai.get_parent()
	assert_that(attach is BoneAttachment3D).is_true()
	assert_str((attach as BoneAttachment3D).bone_name).is_equal(HeldTool.HAND_BONE)
	assert_vector((keitai as Node3D).position).is_equal(Vector3.ZERO)


func test_window_scenery_fits_and_scrolls() -> void:
	var packed: PackedScene = load("res://scenes/ui/intro_train.tscn")
	var scene: Node3D = auto_free(packed.instantiate()) as Node3D
	add_child(scene)
	await get_tree().process_frame
	var win: Node3D = scene.get_node("%TrainCar/WindowScenery/GeneratedVisual") as Node3D
	assert_that(win).is_not_null()
	assert_float(win.scale.x).is_equal_approx(FieldCatalog.train_window_uniform_scale(), 0.0001)
	assert_that(win.find_child("rom_train_out", true, false)).is_not_null()
	## Car glass must be XLU so outside scenery reads through the panes.
	var car_vis: Node3D = scene.get_node("%TrainCar/GeneratedVisual") as Node3D
	var glass_found := false
	for node: Node in car_vis.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(i)
			if mat == null:
				continue
			var label := String(mat.resource_name).to_lower()
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
				label += " " + (mat as StandardMaterial3D).albedo_texture.resource_path.get_file().to_lower()
			if "glass" not in label:
				continue
			glass_found = true
			assert_that(mat is StandardMaterial3D).is_true()
			var std := mat as StandardMaterial3D
			assert_int(std.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
			assert_float(std.albedo_color.a).is_less(0.95)
	assert_that(glass_found).is_true()
	var car: Node = scene.get_node("%TrainCar")
	assert_that(car.get("_tree_mats")).is_not_null()
	var tree_mats: Array = car.get("_tree_mats") as Array
	assert_int(tree_mats.size()).is_greater(0)
	var before: Vector3 = (tree_mats[0] as StandardMaterial3D).uv1_offset
	await get_tree().create_timer(0.1).timeout
	var after: Vector3 = (tree_mats[0] as StandardMaterial3D).uv1_offset
	assert_float(after.x).is_greater(before.x)


func test_rover_intro_has_stage_cue_nodes() -> void:
	var data: DialogueData = DialogueCatalog.conversation(&"rover_intro")
	assert_that(data).is_not_null()
	for node_id: StringName in [&"sit_stage", &"phone_stage", &"phone_done_stage", &"return_sit_stage"]:
		assert_bool(data.has_node(node_id)).is_true()


func test_stage_cues_follow_decomp_action_order() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null)
	## Fast-forward to seated talk.
	for _i: int in 220:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.TALK:
			break
	stage.cue_sit()
	for _i: int in 120:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.SEATED:
			break
	assert_that(stage.action).is_equal(IntroTrainStage.Action.SEATED)
	stage.cue_phone()
	for _i: int in 5:
		stage.tick(0.0)
	assert_that(stage.action).is_in(
		[
			IntroTrainStage.Action.STANDUP,
			IntroTrainStage.Action.MOVE_AISLE,
			IntroTrainStage.Action.MOVE_DOOR,
			IntroTrainStage.Action.MOVE_DECK,
			IntroTrainStage.Action.KEITAI_ON,
			IntroTrainStage.Action.KEITAI_TALK,
		]
	)
	stage.end_phone_talk()
	stage.cue_return_sit()
	for _i: int in 400:
		stage.tick(1.0 / 30.0)
		if stage.action == IntroTrainStage.Action.SEATED:
			break
	assert_that(stage.action).is_in(
		[
			IntroTrainStage.Action.SEATED,
			IntroTrainStage.Action.SITDOWN,
			IntroTrainStage.Action.TALK,
			IntroTrainStage.Action.KEITAI_OFF,
			IntroTrainStage.Action.OPEN_DOOR,
			IntroTrainStage.Action.RETURN_APPROACH,
			IntroTrainStage.Action.LAST_SIT,
		]
	)
	rover.queue_free()


func test_game_start_intro_targets_train_scene() -> void:
	assert_str(Game.INTRO_KK_SCENE).is_equal("res://scenes/ui/intro_kk.tscn")
	assert_str(Game.INTRO_SCENE).is_equal("res://scenes/ui/intro_train.tscn")
	assert_that(ResourceLoader.exists(Game.INTRO_KK_SCENE)).is_true()
	assert_that(ResourceLoader.exists(Game.INTRO_SCENE)).is_true()
