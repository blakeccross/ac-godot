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
	assert_that(scene.get_node_or_null("%IntroCamera")).is_not_null()
	assert_that(scene.get_node_or_null("%DialogueOverlay")).is_not_null()
	assert_that(scene.get_node_or_null("%MissingBanner")).is_not_null()


func test_rover_intro_has_stage_cue_nodes() -> void:
	var data: DialogueData = DialogueCatalog.conversation(&"rover_intro")
	assert_that(data).is_not_null()
	for node_id: StringName in [&"sit_stage", &"phone_stage", &"phone_done_stage"]:
		assert_bool(data.has_node(node_id)).is_true()


func test_stage_cues_follow_decomp_action_order() -> void:
	var stage := IntroTrainStage.new()
	var rover := Node3D.new()
	add_child(rover)
	stage.bind(rover, null, null, null, null, null)
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
	for _i: int in 5:
		stage.tick(0.0)
	assert_that(stage.action).is_in(
		[
			IntroTrainStage.Action.KEITAI_OFF,
			IntroTrainStage.Action.OPEN_DOOR,
			IntroTrainStage.Action.RETURN_APPROACH,
			IntroTrainStage.Action.MOVE_TO_SEAT,
			IntroTrainStage.Action.SITDOWN,
			IntroTrainStage.Action.SEATED,
		]
	)
	rover.queue_free()


func test_game_start_intro_targets_train_scene() -> void:
	assert_str(Game.INTRO_SCENE).is_equal("res://scenes/ui/intro_train.tscn")
	assert_that(ResourceLoader.exists(Game.INTRO_SCENE)).is_true()
