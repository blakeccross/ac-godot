class_name TestClock
extends GdUnitTestSuite


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true


func after_test() -> void:
	Clock.reset_to_default()
	Clock.paused = false


func test_default_is_clamped_rtc_fallback() -> void:
	assert_int(Clock.year).is_equal(2001)
	assert_int(Clock.month).is_equal(1)
	assert_int(Clock.day).is_equal(1)
	assert_int(Clock.hour).is_equal(12)
	assert_that(Clock.season()).is_equal(ClockService.Season.WINTER)
	assert_that(Clock.time_of_day()).is_equal(ClockService.TimeOfDay.DAY)
	assert_int(Clock.term_idx()).is_equal(0)


func test_advance_minutes_rolls_hour() -> void:
	Clock.advance_minutes(60)
	assert_int(Clock.hour).is_equal(13)
	assert_int(Clock.minute).is_equal(0)


func test_advance_wraps_day_and_month() -> void:
	Clock.apply_snapshot({ "year": 2001, "month": 3, "day": 31, "hour": 23, "minute": 50 })
	Clock.advance_minutes(20)
	assert_int(Clock.month).is_equal(4)
	assert_int(Clock.day).is_equal(1)
	assert_int(Clock.hour).is_equal(0)
	assert_int(Clock.minute).is_equal(10)


func test_season_terms_from_m_time() -> void:
	Clock.apply_snapshot({ "year": 2001, "month": 2, "day": 24, "hour": 12, "minute": 0 })
	assert_that(Clock.season()).is_equal(ClockService.Season.WINTER)
	Clock.apply_snapshot({ "year": 2001, "month": 2, "day": 25, "hour": 12, "minute": 0 })
	assert_that(Clock.season()).is_equal(ClockService.Season.SPRING)
	Clock.apply_snapshot({ "year": 2001, "month": 5, "day": 25, "hour": 12, "minute": 0 })
	assert_that(Clock.season()).is_equal(ClockService.Season.SPRING)
	Clock.apply_snapshot({ "year": 2001, "month": 5, "day": 26, "hour": 12, "minute": 0 })
	assert_that(Clock.season()).is_equal(ClockService.Season.SUMMER)
	Clock.apply_snapshot({ "year": 2001, "month": 9, "day": 15, "hour": 12, "minute": 0 })
	assert_that(Clock.season()).is_equal(ClockService.Season.SUMMER)
	Clock.apply_snapshot({ "year": 2001, "month": 9, "day": 16, "hour": 12, "minute": 0 })
	assert_that(Clock.season()).is_equal(ClockService.Season.AUTUMN)
	Clock.apply_snapshot({ "year": 2001, "month": 12, "day": 9, "hour": 12, "minute": 0 })
	assert_that(Clock.season()).is_equal(ClockService.Season.AUTUMN)
	Clock.apply_snapshot({ "year": 2001, "month": 12, "day": 10, "hour": 12, "minute": 0 })
	assert_that(Clock.season()).is_equal(ClockService.Season.WINTER)


func test_light_terms_from_m_kankyo() -> void:
	Clock.apply_snapshot({ "year": 2001, "month": 3, "day": 20, "hour": 22, "minute": 0 })
	assert_int(Clock.light_term()).is_equal(7)
	assert_that(Clock.time_of_day()).is_equal(ClockService.TimeOfDay.NIGHT)
	Clock.apply_snapshot({ "year": 2001, "month": 3, "day": 20, "hour": 6, "minute": 30 })
	assert_int(Clock.light_term()).is_equal(2)
	assert_that(Clock.time_of_day()).is_equal(ClockService.TimeOfDay.DAWN)


func test_year_clamp() -> void:
	Clock.apply_snapshot({ "year": 1999, "month": 1, "day": 1, "hour": 12, "minute": 0 })
	assert_int(Clock.year).is_equal(2001)
	Clock.apply_snapshot({ "year": 2040, "month": 1, "day": 1, "hour": 12, "minute": 0 })
	assert_int(Clock.year).is_equal(2030)


func test_snapshot_round_trip() -> void:
	Clock.advance_minutes(90)
	var snap: Dictionary = Clock.to_dict()
	Clock.reset_to_default()
	Clock.apply_snapshot(snap)
	assert_int(Clock.hour).is_equal(13)
	assert_int(Clock.minute).is_equal(30)
