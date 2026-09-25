class_name TestPlayerSe
extends GdUnitTestSuite


func test_clip_marks_cover_core_actions() -> void:
	assert_that(PlayerSe.CLIP_MARKS.has(&"ply_1_axe_swing1")).is_true()
	assert_that(PlayerSe.CLIP_MARKS.has(&"ply_1_sao_swing1")).is_true()
	assert_that(PlayerSe.CLIP_MARKS.has(&"ply_1_net_swing1")).is_true()
	assert_that(PlayerSe.CLIP_MARKS.has(&"ply_1_pickup1")).is_true()
	## Dig scoop is outcome-driven, not on every dig1.
	assert_that(PlayerSe.CLIP_MARKS.has(&"ply_1_dig1")).is_false()


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
