class_name TestFootstepSe
extends GdUnitTestSuite


func test_grass_summer_and_winter() -> void:
	assert_that(FootstepSe.id_for_attr(0, Clock.Season.SUMMER)).is_equal(&"footstep_grass")
	assert_that(FootstepSe.id_for_attr(2, Clock.Season.WINTER)).is_equal(&"footstep_snow")
	## grass3 falls through to soil in `sAdo_Get_WalkLabel`.
	assert_that(FootstepSe.id_for_attr(3, Clock.Season.SUMMER)).is_equal(&"footstep_soil")


func test_named_attrs() -> void:
	assert_that(FootstepSe.id_for_attr(4, Clock.Season.SUMMER)).is_equal(&"footstep_soil")
	assert_that(FootstepSe.id_for_attr(7, Clock.Season.SUMMER)).is_equal(&"footstep_stone")
	assert_that(FootstepSe.id_for_attr(9, Clock.Season.SUMMER)).is_equal(&"footstep_bush")
	assert_that(FootstepSe.id_for_attr(22, Clock.Season.SUMMER)).is_equal(&"footstep_sand")
	assert_that(FootstepSe.id_for_attr(11, Clock.Season.SUMMER)).is_equal(&"footstep_wave")
	assert_that(FootstepSe.id_for_attr(23, Clock.Season.SUMMER)).is_equal(&"footstep_wood")


func test_indoor_and_volume() -> void:
	assert_that(FootstepSe.id_indoors()).is_equal(&"footstep_wood")
	assert_that(FootstepSe.volume_db(PlayerLocomotion.Gait.WALK)).is_equal(linear_to_db(0.6))
	assert_that(FootstepSe.volume_db(PlayerLocomotion.Gait.DASH)).is_equal(0.0)
	assert_that(FootstepSe.volume_db(PlayerLocomotion.Gait.WAIT)).is_less(-40.0)
