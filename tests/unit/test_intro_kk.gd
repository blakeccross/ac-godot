class_name TestIntroKk
extends GdUnitTestSuite

## K.K. opening (`ac_npc_p_sel`) → train handoff.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	DialogueCatalog.reset()
	Audio.fade_sec = 0.0
	Audio.stop_bgm()


func after_test() -> void:
	Audio.stop_bgm()
	Audio.fade_sec = Audio.FADE_SEC
	DialogueCatalog.reset()
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_game_start_intro_targets_kk_scene() -> void:
	assert_str(Game.INTRO_KK_SCENE).is_equal("res://scenes/ui/intro_kk.tscn")
	assert_that(ResourceLoader.exists(Game.INTRO_KK_SCENE)).is_true()
	assert_str(Game.INTRO_SCENE).is_equal("res://scenes/ui/intro_train.tscn")


func test_kk_opening_dialogue_exists() -> void:
	var data: DialogueData = DialogueCatalog.conversation(&"kk_opening")
	assert_that(data).is_not_null()
	assert_bool(data.has_node(&"finish")).is_true()
	assert_bool(data.has_node(&"welcome")).is_true()
	assert_bool(data.has_node(&"ready_choice")).is_true()
	## First-game welcome paraphrases decomp msg 0x09C7 (move-out → friends → train).
	var welcome: Dictionary = data.node(&"welcome")
	assert_str(String(welcome.get("text", ""))).contains("own")
	var choice: Dictionary = data.node(&"ready_choice")
	assert_that(choice.get("type")).is_equal("choice")


func test_stage_strum_then_talk_then_fade() -> void:
	var stage := IntroKkStage.new()
	var talked := [false]
	var faded := [false]
	stage.ready_for_talk.connect(func() -> void: talked[0] = true)
	stage.fade_finished.connect(func() -> void: faded[0] = true)
	## Cover the decomp 440-frame strum window (plus a frame of float slack).
	stage.tick(float(IntroKkStage.STRUM_FRAMES) / IntroKkStage.FRAME_HZ + 0.05)
	assert_that(stage.phase).is_equal(IntroKkStage.Phase.TALK)
	assert_that(stage.pose).is_equal(IntroKkStage.Pose.LOOK_UP)
	assert_bool(talked[0]).is_true()
	stage.begin_fade()
	assert_that(stage.phase).is_equal(IntroKkStage.Phase.FADE)
	assert_that(stage.pose).is_equal(IntroKkStage.Pose.STRUM)
	stage.tick(float(IntroKkStage.FADE_FRAMES) / IntroKkStage.FRAME_HZ + 0.05)
	assert_that(stage.phase).is_equal(IntroKkStage.Phase.DONE)
	assert_bool(faded[0]).is_true()
	assert_float(stage.fade_alpha).is_equal_approx(1.0, 0.001)


func test_stage_silent_idle_looks_then_resumes_strum() -> void:
	var stage := IntroKkStage.new()
	stage.tick(float(IntroKkStage.STRUM_FRAMES) / IntroKkStage.FRAME_HZ + 0.05)
	assert_that(stage.pose).is_equal(IntroKkStage.Pose.LOOK_UP)
	## Still typing / not awaiting — silent counter resets; stay on look-up.
	stage.tick(1.0, false)
	assert_that(stage.pose).is_equal(IntroKkStage.Pose.LOOK_UP)
	## ~10 s unanswered → TALK1 remaps to default_animation 4haku (resume playing).
	stage.tick(float(IntroKkStage.SILENT_FRAMES) / IntroKkStage.FRAME_HZ + 0.05, true)
	assert_that(stage.pose).is_equal(IntroKkStage.Pose.STRUM)
	## Stay strumming while still unanswered past the threshold.
	stage.tick(0.5, true)
	assert_that(stage.pose).is_equal(IntroKkStage.Pose.STRUM)
	## Advancing (silent reset) while strumming → look up again.
	stage.tick(0.05, false)
	assert_that(stage.pose).is_equal(IntroKkStage.Pose.LOOK_UP)
	assert_str(IntroKkStage.anim_for_pose(IntroKkStage.Pose.LOOK_UP)).is_equal("npc_1_wait_e1")
	assert_str(IntroKkStage.anim_for_pose(IntroKkStage.Pose.STRUM)).is_equal("npc_1_4haku_e1")
	assert_float(IntroKkStage.morph_for_pose(IntroKkStage.Pose.LOOK_UP)).is_equal_approx(
		5.0 / 30.0, 0.001
	)
	assert_float(IntroKkStage.morph_for_pose(IntroKkStage.Pose.STRUM)).is_equal_approx(
		3.0 / 30.0, 0.001
	)


func test_camera_and_spawn_match_decomp() -> void:
	assert_vector(IntroKkStage.CAM_CENTER_GX).is_equal(Vector3(100.0, 10.0, 60.0))
	assert_vector(IntroKkStage.CAM_EYE_GX).is_equal(Vector3(100.0, 130.0, 210.0))
	assert_vector(IntroKkStage.KK_SPAWN_GX).is_equal(Vector3(100.0, 0.0, 60.0))
	assert_float(IntroKkStage.CAM_FOV).is_equal(40.0)
	assert_vector(IntroKkStage.SUN_DIR_GX).is_equal(Vector3(0.0, 89.0, 79.0))
	## Literal GX near (5 m) clips the seated mesh; use the train-style short near.
	assert_float(IntroKkStage.CAM_NEAR_METERS).is_equal_approx(0.1, 0.0001)
	## DirectionalLight shines along −Z; that should match −sun_dir (light travel).
	assert_that(
		(-IntroKkStage.sun_basis().z).dot((-IntroKkStage.SUN_DIR_GX).normalized())
	).is_greater(0.99)


func test_kk_scene_loads() -> void:
	var packed: PackedScene = load("res://scenes/ui/intro_kk.tscn")
	assert_that(packed).is_not_null()
	var scene: Node3D = auto_free(packed.instantiate()) as Node3D
	assert_that(scene).is_not_null()
	add_child(scene)
	await get_tree().process_frame
	assert_that(scene.get_node_or_null("%KkSlider")).is_not_null()
	assert_that(scene.get_node_or_null("%IntroCamera")).is_not_null()
	assert_that(scene.get_node_or_null("%DialogueOverlay")).is_not_null()
	assert_that(scene.get_node_or_null("%FadeRect")).is_not_null()
	assert_that(scene.get_node("%KkSlider") is IntroKkAnim).is_true()
	var kk: IntroKkAnim = scene.get_node("%KkSlider") as IntroKkAnim
	if ResourceLoader.exists(IntroKkStage.KK_PATH):
		var anim: AnimationPlayer = kk.body_animation_player()
		assert_that(anim).is_not_null()
		assert_str(IntroKkStage.resolve_clip(anim, IntroKkStage.ANIM_STRUM)).is_not_empty()
		assert_str(IntroKkStage.resolve_clip(anim, IntroKkStage.ANIM_LOOK_UP)).is_not_empty()
		assert_bool(kk.play_strum()).is_true()
		assert_bool(anim.is_playing()).is_true()
