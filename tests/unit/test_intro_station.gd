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


func test_stage_landmarks_match_decomp_offsets() -> void:
	## Stage GX = decomp world GX − station block (3, 1) origin (1920, 640).
	assert_vector(IntroStationStage.BLOCK_ORIGIN_GX).is_equal(Vector3(1920.0, 0.0, 640.0))
	var at := func(x: float, z: float) -> Vector3:
		return IntroStationStage.block_gx(Vector3(x, 0.0, z))
	assert_vector(IntroStationStage.PLAYER_START_GX).is_equal(at.call(1970.0, 760.0))
	assert_vector(IntroStationStage.DOORWAY_GX).is_equal(at.call(2180.0, 820.0))
	assert_vector(IntroStationStage.OFF_UT_GX).is_equal(at.call(2220.0, 840.0))
	assert_float(IntroStationStage.OUT_STATION_Z_GX).is_equal(970.0 - 640.0)
	assert_vector(IntroStationStage.PORTER_GX).is_equal(at.call(2140.0, 820.0))
	assert_vector(IntroStationStage.NOOK_SPAWN_GX).is_equal(at.call(2260.0, 1260.0))
	assert_vector(IntroStationStage.NOOK_FACE_GX).is_equal(at.call(2320.0, 980.0))
	assert_vector(IntroStationStage.NOOK_LEAD_GX[0]).is_equal(at.call(2240.0, 1300.0))
	assert_vector(IntroStationStage.NOOK_LEAD_GX[1]).is_equal(at.call(2240.0, 1500.0))
	assert_vector(IntroStationStage.RIDE_OFF_GX).is_equal(Vector3(60.0, 20.0, 20.0))


func test_nook_restart_points_match_birth_table() -> void:
	## `aID_birth_rcn_guide`: block (3, 2) unit centre + (±10, 8).
	var ux: Array[int] = [6, 9, 6, 9]
	var uz: Array[int] = [5, 5, 12, 12]
	var ofs_x: Array[float] = [10.0, -10.0, 10.0, -10.0]
	for i: int in 4:
		var world := Vector3(
			3.0 * 640.0 + ux[i] * 40.0 + 20.0 + ofs_x[i], 0.0, 2.0 * 640.0 + uz[i] * 40.0 + 20.0 + 8.0
		)
		assert_vector(IntroStationStage.NOOK_RESTART_GX[i]).is_equal(IntroStationStage.block_gx(world))
	assert_int(IntroStationStage.house_index(&"player_house")).is_equal(0)
	assert_int(IntroStationStage.house_index(&"player_house_3")).is_equal(3)


func test_nook_exit_leave_points() -> void:
	## `aNRG_exit`: x 2240; north of z 1540 run to 1300 then 1220, south to 1900 then 1980.
	var at := func(z: float) -> Vector3:
		return IntroStationStage.nook_exit_waypoint(IntroStationStage.block_gx(Vector3(2240.0, 0.0, z)))
	assert_float(at.call(1500.0).z + 640.0).is_equal(1300.0)
	assert_float(at.call(1300.0).z + 640.0).is_equal(1220.0)
	assert_that(at.call(1220.0)).is_equal(Vector3.INF)
	assert_float(at.call(1600.0).z + 640.0).is_equal(1900.0)
	assert_float(at.call(1900.0).z + 640.0).is_equal(1980.0)
	assert_that(at.call(1980.0)).is_equal(Vector3.INF)


func test_train_demo_init_matches_decomp() -> void:
	## `mTRC_demo_init`: slowing at 2037, due out 4:50 before now (so 20 s after the dwell).
	var control := TrainControl.new()
	control.init(36000, 1)
	var state: int = control.step(36000, 1, false, false, true)
	assert_int(state).is_equal(TrainControl.STATE_DEMO)
	assert_int(control.action).is_equal(TrainControl.Action.BEGIN_SLOWDOWN)
	assert_float(control.speed).is_equal(TrainControl.SLOW_SPEED)
	assert_float(control.x_gx).is_equal(2037.0 + 0.5 * TrainControl.SLOW_SPEED)
	assert_int(control.start_timer).is_equal(36000 - 290)
	## Runs through the stop into WAIT_STOPPED, then leaves once the dwell is over.
	var frames: int = 0
	while control.action != TrainControl.Action.WAIT_STOPPED and frames < 5000:
		control.step(36000, 1)
		frames += 1
	assert_int(control.action).is_equal(TrainControl.Action.WAIT_STOPPED)
	assert_int(control.start_timer).is_equal(36000 + 20)
	control.step(36019, 1)
	assert_int(control.action).is_equal(TrainControl.Action.WAIT_STOPPED)
	control.step(36020, 1)
	assert_int(control.action).is_equal(TrainControl.Action.SIGNAL_STARTING)


func test_npc_point_move_run_speed_and_arrival() -> void:
	## `aNPC_spd_data` run: max 3.0, accel 0.3 × 0.5 per frame, `0.5 · speed` GX per frame.
	var move := NpcPointMove.new()
	move.reset(0.0)
	var pos := Vector3.ZERO
	pos = move.step_to(pos, Vector3(0.0, 0.0, 400.0), true)
	assert_float(move.speed).is_equal_approx(0.15, 0.0001)
	for i: int in 100:
		pos = move.step_to(pos, Vector3(0.0, 0.0, 400.0), true)
	assert_float(move.speed).is_equal_approx(NpcPointMove.RUN_MAX, 0.0001)
	assert_that(NpcPointMove.arrived(Vector3(0.0, 0.0, 391.6), Vector3(0.0, 0.0, 400.0))).is_true()
	assert_that(NpcPointMove.arrived(Vector3(0.0, 0.0, 391.4), Vector3(0.0, 0.0, 400.0))).is_false()


func test_npc_point_move_turn_rate() -> void:
	## `TURN` / `TALK_TURN`: 0x800 per 30 fps frame → 0x400 per 60 Hz frame.
	var move := NpcPointMove.new()
	move.reset(0.0)
	var done: bool = move.step_turn(PI * 0.5)
	assert_that(done).is_false()
	assert_float(move.facing).is_equal_approx(float(0x400) * MLib.S16, 0.00001)
	for i: int in 16:
		done = move.step_turn(PI * 0.5)
	assert_that(done).is_true()


func test_intro_wade_border_moves_in_one_unit() -> void:
	## `mCoBG_BLOCK_BGCHECK_MODE_INTRO_DEMO`: player-house acre walled 18 + 40 from its edges.
	var old := Vector3(1920.0 + 100.0, 0.0, 1280.0 + 100.0)
	var held: Vector3 = AcreWade.confine(old, Vector3(1920.0 + 30.0, 0.0, 1280.0 + 100.0), 40.0)
	assert_float(held.x).is_equal(1920.0 + 58.0)
	## Unable to wade: the direction is reported even when landing is refused.
	var at_east := Vector3(1920.0 + 640.0 - 50.0, 0.0, 1280.0 + 300.0)
	var no_land := func(_d: AcreWade.Dir) -> bool: return false
	assert_int(AcreWade.direction(at_east, PI * 0.5, Vector2(1.0, 0.0), no_land, 40.0, true)).is_equal(
		AcreWade.Dir.RIGHT
	)
	assert_int(AcreWade.direction(at_east, PI * 0.5, Vector2(1.0, 0.0), no_land, 0.0, true)).is_equal(
		AcreWade.Dir.NONE
	)


func test_loco_wheel_speed_matches_decomp() -> void:
	## `aTR0_actor_move`: (speed/40)*10, max 0.5. Approach 2.0 GX → full 0.5.
	assert_float(IntroStationStage.loco_wheel_speed_scale(2.0)).is_equal_approx(0.5, 0.0001)
	assert_float(IntroStationStage.loco_wheel_speed_scale(1.0)).is_equal_approx(0.25, 0.0001)
	assert_float(IntroStationStage.loco_wheel_speed_scale(0.0)).is_equal_approx(0.0, 0.0001)
	assert_float(IntroStationStage.loco_wheel_speed_scale(40.0)).is_equal_approx(0.5, 0.0001)


func test_caboose_door_snaps_closed_from_open_clip() -> void:
	## Close clip frame 1 is open; closed pose is open@0 (or close@end).
	var anim := AnimationPlayer.new()
	add_child(anim)
	var lib := AnimationLibrary.new()
	var open := Animation.new()
	open.length = 0.8
	lib.add_animation("obj_train1_3_open", open)
	var close := Animation.new()
	close.length = 31.0 / 30.0
	lib.add_animation("obj_train1_3_close", close)
	anim.add_animation_library("", lib)
	VisualTrain.snap_train_doors_closed(anim)
	assert_that(String(anim.current_animation)).is_equal("obj_train1_3_open")
	assert_float(anim.current_animation_position).is_equal_approx(0.0, 0.001)
	assert_float(anim.speed_scale).is_equal_approx(0.0, 0.001)
	anim.queue_free()


func test_stage_control_flags() -> void:
	## Stick free after the one-unit walk and during the pick; demo walks ignore the stick
	## themselves; the ride pins the pose; the pick locks the acre.
	var stage := IntroStationStage.new()
	stage.action = IntroStationStage.Action.TRAIN_APPROACH
	assert_that(stage.player_controls_locked()).is_true()
	assert_that(stage.player_cutscene_driven()).is_true()
	assert_that(stage.uses_demo_camera()).is_true()
	stage.action = IntroStationStage.Action.WALK_ONE_UNIT
	assert_that(stage.player_controls_locked()).is_false()
	assert_that(stage.uses_demo_camera()).is_true()
	stage.action = IntroStationStage.Action.PLAYER_CONTROL
	assert_that(stage.player_controls_locked()).is_false()
	assert_that(stage.uses_demo_camera()).is_false()
	stage.action = IntroStationStage.Action.NOOK_LEAD
	assert_that(stage.player_controls_locked()).is_false()
	assert_that(stage.player_cutscene_driven()).is_false()
	stage.action = IntroStationStage.Action.PLAYER_PICK
	assert_that(stage.player_controls_locked()).is_false()
	assert_that(stage.player_unable_wade()).is_true()
	stage.action = IntroStationStage.Action.NOOK_EXIT
	assert_that(stage.player_controls_locked()).is_true()


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


func test_message_bgm_table_matches_decomp() -> void:
	## `mMsg_bgm_num`: 1 ARRIVE, 2 RCN_GUIDE, 3 SELECT_HOUSE, 4 SELECT_HOUSE2; 0 / 6 quiet.
	assert_that(MessageBgm.track(1)).is_equal(&"intro_arrive")
	assert_that(MessageBgm.track(2)).is_equal(&"intro_rcn_guide")
	assert_that(MessageBgm.track(3)).is_equal(&"intro_select_house")
	assert_that(MessageBgm.track(4)).is_equal(&"intro_select_house2")
	assert_that(MessageBgm.track(0)).is_equal(&"")
	assert_that(MessageBgm.track(6)).is_equal(&"")


func test_nook_call_text_starts_the_rcn_guide_theme() -> void:
	## `0x07DE` carries BGMDELETE ARRIVE + BGMMAKE RCN_GUIDE; applying it swaps the music.
	var call: DialogueData = DialogueCatalog.conversation(&"msg_2014")
	if call == null:
		call = DialogueCatalog.conversation(&"nook_station_call")
	assert_that(call).is_not_null()
	var ops: Array = []
	for key: Variant in call.nodes:
		for ev: Variant in (call.nodes[key] as Dictionary).get("events", []):
			ops.append([String((ev as Dictionary).get("op", "")), int((ev as Dictionary).get("bgm", -1))])
	assert_that(ops.has(["bgm_make", 2])).is_true()


func test_train_smoke_and_steam_effects_follow_decomp() -> void:
	## `eKishaK_ct`: 80 frames from scale 0; `eSteam_ct`: 30 frames rising back.
	var host := Node3D.new()
	add_child(host)
	var smoke: FieldFx = FieldFx.spawn(host, FieldFx.Kind.KISHA_KEMURI, Vector3.ZERO, 0.0)
	var steam: FieldFx = FieldFx.spawn(host, FieldFx.Kind.STEAM, Vector3.ZERO, 0.0)
	assert_int(smoke.timer).is_equal(80)
	assert_float(smoke.scale_gx.x).is_equal(0.0)
	assert_int(steam.timer).is_equal(30)
	assert_float(steam.acc.y).is_equal(0.125)
	assert_float(steam.vel.y).is_less(-1.49)
	host.queue_free()


func test_suspended_dialogue_ignores_input() -> void:
	## The payment's pockets sit over a parked talk: the window must not eat Enter.
	var ui: DialogueOverlay = load("res://scenes/ui/dialogue_overlay.tscn").instantiate()
	add_child(ui)
	ui.set_suspended(true)
	assert_that(ui.is_suspended()).is_true()
	assert_that(ui.visible).is_false()
	assert_that(ui.is_uttering()).is_false()
	ui.set_suspended(false)
	assert_that(ui.visible).is_true()
	ui.queue_free()
