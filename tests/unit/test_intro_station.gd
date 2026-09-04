class_name TestIntroStation
extends GdUnitTestSuite

## Station arrival (`ac_intro_demo`) after the Rover train.


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


func test_game_intro_station_starts_generated_world() -> void:
	assert_that(ResourceLoader.exists(Game.WORLD_SCENE)).is_true()
	assert_that(ResourceLoader.exists("res://scenes/world/intro_station_director.gd")).is_true()


func test_porter_and_nook_dialogue_authored() -> void:
	## Bank ids when converted; authored fallbacks always present.
	var porter: DialogueData = DialogueCatalog.conversation(&"msg_2013")
	if porter == null:
		porter = DialogueCatalog.conversation(&"porter_arrive")
	assert_that(porter).is_not_null()
	var call: DialogueData = DialogueCatalog.conversation(&"msg_2014")
	if call == null:
		call = DialogueCatalog.conversation(&"nook_station_call")
	assert_that(call).is_not_null()
	var greet: DialogueData = DialogueCatalog.conversation(&"msg_2015")
	if greet == null:
		greet = DialogueCatalog.conversation(&"nook_station_greeting")
	assert_that(greet).is_not_null()
	assert_that(DialogueCatalog.conversation(&"nook_station_greeting")).is_not_null()
	assert_that(DialogueCatalog.conversation(&"nook_show_houses")).is_not_null()
	assert_that(DialogueCatalog.conversation(&"nook_house_look")).is_not_null()
	assert_that(DialogueCatalog.conversation(&"nook_house_debt")).is_not_null()
	assert_that(DialogueCatalog.conversation(&"nook_first_job")).is_not_null()
	## Bank house-look line when converted.
	var look: DialogueData = DialogueCatalog.conversation(&"msg_2020")
	if look == null:
		look = DialogueCatalog.conversation(&"nook_house_look")
	assert_that(look).is_not_null()


func test_landmarks_survive_bind() -> void:
	## `bind` must not wipe town house GX set via `set_landmarks`.
	var stage := IntroStationStage.new()
	var houses: Array[Vector3] = [Vector3(500.0, 0.0, 900.0), Vector3(600.0, 0.0, 900.0)]
	stage.bind(null, null, null, null, null, null, null, null)
	stage.set_landmarks(400.0, Vector3.ZERO, Vector3.ZERO, Vector3(550.0, 0.0, 820.0), houses)
	assert_int(stage._house_gx.size()).is_equal(2)
	assert_float(stage._house_gx[0].x).is_equal(500.0)
	assert_float(stage._nook_explain_gx.z).is_equal(820.0)


func test_stage_landmarks_match_decomp_offsets() -> void:
	## Relative to block (3,1) origin — absolute doorway is (2180, 820).
	assert_float(IntroStationStage.DOORWAY_GX.x).is_equal(260.0)
	assert_float(IntroStationStage.DOORWAY_GX.z).is_equal(180.0)
	assert_float(IntroStationStage.OFF_UT_GX.x).is_equal(300.0)
	assert_float(IntroStationStage.OUT_STATION_Z_GX).is_equal(330.0)
	assert_float(IntroStationStage.CABOOSE_GAP_GX).is_equal(125.0)
	assert_float(IntroStationStage.PASSENGER_GAP_GX).is_equal(250.0)
	assert_int(IntroStationStage.HOUSE_GX.size()).is_equal(4)


func test_train_is_loco_mid_passenger_layout() -> void:
	## TRAIN0: loco + mid at −125; TRAIN1 passenger at −250 with door ride offset.
	## Yaws: anim-bind + ckf_basis makes all three cars long on +X.
	assert_float(IntroStationStage.CABOOSE_GAP_GX).is_equal(125.0)
	assert_float(IntroStationStage.PASSENGER_GAP_GX).is_equal(250.0)
	assert_float(IntroStationStage.LOCO_YAW).is_equal(0.0)
	assert_float(IntroStationStage.MID_YAW).is_equal(0.0)
	assert_float(IntroStationStage.CABOOSE_YAW).is_equal(0.0)
	assert_float(IntroStationStage.RIDE_YAW).is_equal(0.0)
	assert_that(ResourceLoader.exists("res://assets/generated/environment/obj_train1_1.glb")).is_true()
	assert_that(ResourceLoader.exists("res://assets/generated/environment/obj_train1_2.glb")).is_true()
	assert_that(ResourceLoader.exists("res://assets/generated/environment/obj_train1_3.glb")).is_true()
	assert_that(ResourceLoader.exists("res://assets/generated/characters/villagers/mnk_1.glb")).is_true()


func test_nook_lead_locks_controls() -> void:
	## Free stick only after Porter and for house pick; TAKE_WITH is demo-walk.
	var stage := IntroStationStage.new()
	stage.action = IntroStationStage.Action.NOOK_LEAD
	assert_that(stage.player_controls_locked()).is_true()
	assert_that(stage.player_cutscene_driven()).is_true()
	stage.action = IntroStationStage.Action.PLAYER_CONTROL
	assert_that(stage.player_controls_locked()).is_false()
	stage.action = IntroStationStage.Action.PLAYER_PICK
	assert_that(stage.player_controls_locked()).is_false()
	assert_that(stage.player_cutscene_driven()).is_false()


func test_stage_platform_height_and_camera_match_decomp() -> void:
	assert_float(IntroStationStage.PLATFORM_Y_GX).is_equal(40.0)
	assert_float(IntroStationStage.TRACK_Y_GX).is_equal(20.0)
	assert_float(IntroStationStage.CAM_DIST_GX).is_equal(620.0)
	assert_float(IntroStationStage.CAM_FOV).is_equal(20.0)
	assert_float(IntroStationStage.CAM_LOOK_Y_OFF_GX).is_equal(-35.0)
	var stage := IntroStationStage.new()
	assert_float(stage.ground_y_gx(220.0, 180.0)).is_equal_approx(40.0, 0.1)
	## Arrive look Y = platform ground + GetBgY −35 offset.
	assert_float(40.0 + IntroStationStage.CAM_LOOK_Y_OFF_GX).is_equal(5.0)


func test_vacant_player_houses_resolve_interior() -> void:
	assert_that(InteriorCatalog.resolve_entry(&"player_house")).is_equal(&"player_main")
	assert_that(InteriorCatalog.resolve_entry(&"player_house_1")).is_equal(&"player_main")
	assert_that(InteriorCatalog.resolve_entry(&"player_house_2")).is_equal(&"player_main")
	assert_that(InteriorCatalog.resolve_entry(&"player_house_3")).is_equal(&"player_main")
