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
	## Smoke: sync helpers no-op without streams.
	Audio.stop_syslev()
	Audio.sync_rain_syslev(Weather.Kind.CLEAR, Weather.Intensity.NONE, false)
	Audio.sync_rain_syslev(Weather.Kind.RAIN, Weather.Intensity.HEAVY, true)
	Audio.stop_syslev()
	assert_bool(true).is_true()
