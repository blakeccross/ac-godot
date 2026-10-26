class_name TestPlayerSe
extends GdUnitTestSuite


func test_clip_marks_cover_core_actions() -> void:
	assert_that(PlayerSe.CLIP_MARKS.has(&"ply_1_axe_swing1")).is_true()
	## The rod's stroke is `cast_rod`'s or `air_rod`'s, chosen at the frame-10 water check
	## (`PlayerSe.rod_stroke`), so `ready_rod`'s clip carries none.
	assert_that(PlayerSe.CLIP_MARKS.has(&"ply_1_sao_swing1")).is_false()
	assert_that(PlayerSe.CLIP_MARKS.has(&"ply_1_pickup1")).is_true()
	## Dig scoop is outcome-driven, not on every dig1.
	assert_that(PlayerSe.CLIP_MARKS.has(&"ply_1_dig1")).is_false()
	## The net's whoosh / get / hit follow `NetSwing` events (the clip is re-seeked each
	## tick), and `GET_M1` has no `AMI_HIT` of its own.
	assert_that(PlayerSe.CLIP_MARKS.has(&"ply_1_net_swing1")).is_false()
	assert_that(PlayerSe.CLIP_MARKS.has(&"ply_1_get_m1")).is_false()


func test_rain_syslev_ids() -> void:
	## `aWeather_ChangeEnvSE`: level 1/2/3 → 7/8/9, under an umbrella 0x12/0x13/0x14.
	assert_int(Weather.rain_syslev_id(Weather.Kind.RAIN, 1)).is_equal(7)
	assert_int(Weather.rain_syslev_id(Weather.Kind.RAIN, 3)).is_equal(9)
	assert_int(Weather.rain_syslev_id(Weather.Kind.RAIN, 2, true)).is_equal(0x13)
	assert_int(Weather.rain_syslev_id(Weather.Kind.RAIN, 0)).is_equal(0)
	assert_int(Weather.rain_syslev_id(Weather.Kind.SNOW, 2)).is_equal(0)


func test_rain_is_quieter_indoors() -> void:
	## `Na_SysLevStart`: 7/8/9 at 0.4 in room / museum / lighthouse scene modes.
	assert_float(Weather.syslev_volume(8, true)).is_equal_approx(0.4, 0.0001)
	assert_float(Weather.syslev_volume(8, false)).is_equal(1.0)
	assert_float(Weather.syslev_volume(0x13, true)).is_equal(1.0)


func test_level_ramps_one_step_at_a_time() -> void:
	assert_int(Weather.step_level(1, 3)).is_equal(2)
	assert_int(Weather.step_level(3, 1)).is_equal(2)
	assert_int(Weather.step_level(2, 2)).is_equal(2)
	assert_int(Weather.LEVEL_STEP_FRAMES).is_equal(180)


func test_rain_plays_the_level_se_not_the_door_se() -> void:
	if not SeCatalog.has_id(&"lev_9"):
		## Audio pipeline not run on this machine.
		return
	var was_demo: bool = Game.title_demo_active
	Game.title_demo_active = false
	Audio.sync_rain_syslev(Weather.Kind.RAIN, 3, false)
	assert_int(Audio.syslev_id()).is_equal(9)
	assert_float(Audio.syslev_volume_db()).is_equal_approx(0.0, 0.001)
	## Indoors: still raining, at 0.4.
	Audio.sync_rain_syslev(Weather.Kind.RAIN, 3, true)
	assert_int(Audio.syslev_id()).is_equal(9)
	assert_float(Audio.syslev_volume_db()).is_equal_approx(linear_to_db(0.4), 0.001)
	## The basement and the title demo are silent.
	Audio.sync_rain_syslev(Weather.Kind.RAIN, 3, true, true)
	assert_int(Audio.syslev_id()).is_equal(0)
	Game.title_demo_active = true
	Audio.sync_rain_syslev(Weather.Kind.RAIN, 3, false)
	assert_int(Audio.syslev_id()).is_equal(0)
	Game.title_demo_active = was_demo
	Audio.sync_rain_syslev(Weather.Kind.CLEAR, 0, false)
	assert_int(Audio.syslev_id()).is_equal(0)


func test_the_players_clips_carry_their_marks_as_event_tracks() -> void:
	var player: Player = auto_free(load("res://features/player/player.tscn").instantiate()) as Player
	add_child(player)
	await get_tree().process_frame
	var anim: BodyAnimator = player.animation_player()
	if anim == null:
		return  ## player model not generated (no disc)
	var keys := func(clip: StringName) -> Array:
		var out: Array = []
		var a: Animation = anim.get_animation(clip)
		for t: int in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_METHOD:
				continue
			for k: int in a.track_get_key_count(t):
				out.append([roundi(a.track_get_key_time(t, k) * DecompTime.FRAME_HZ), a.method_track_get_params(t, k)[1]])
		return out
	assert_array(keys.call(&"ply_1_pickup1")).is_equal([[10, &"item_get"], [20, &"gasagoso"]])
	## The tumble is 16 frames long, so frame 17 (counted from 1) is its last: the body
	## print lands as the clip ends. The old frame check never reached it.
	assert_array(keys.call(&"ply_1_kokeru1")).is_equal(
		[[10, &"tumble_rumble"], [15, &"tumble_dust"], [16, &"tumble_print"]]
	)
	assert_bool(anim.clip_event.is_connected(player._on_clip_event)).is_true()
