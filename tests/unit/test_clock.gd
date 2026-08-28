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


func test_outdoor_light_lerps_between_windows() -> void:
	## Dawn window 06–08: mid-blend is between the 06:00 and 08:00 snap points.
	Clock.reset_to_default()
	Clock.hour = 6
	Clock.minute = 0
	Clock.second = 0
	var a: Dictionary = Clock.outdoor_light()
	Clock.hour = 7
	Clock.minute = 0
	var mid: Dictionary = Clock.outdoor_light()
	Clock.hour = 8
	Clock.minute = 0
	var b: Dictionary = Clock.outdoor_light()
	assert_that(mid.has("fog")).is_true()
	assert_that(mid.has("moon")).is_true()
	assert_that(mid.has("sun_dir")).is_true()
	var ar: float = (a["sun"] as Color).r
	var br: float = (b["sun"] as Color).r
	var mr: float = (mid["sun"] as Color).r
	assert_float(mr).is_greater(mini(ar, br) - 0.001)
	assert_float(mr).is_less(maxi(ar, br) + 0.001)
	assert_float(mr).is_not_equal(ar)


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


func test_weekday_from_calendar_not_os() -> void:
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 12, "minute": 0 })
	assert_int(Clock.weekday()).is_equal(1)
	assert_str(Clock.weekday_name()).is_equal("Monday")
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 7, "hour": 12, "minute": 0 })
	assert_int(Clock.weekday()).is_equal(0)
	assert_str(Clock.weekday_name()).is_equal("Sunday")


func test_calendar_snapshot_has_fields() -> void:
	Clock.apply_snapshot({ "year": 2001, "month": 6, "day": 15, "hour": 14, "minute": 30 })
	var cal: Dictionary = Clock.calendar()
	assert_int(cal["year"]).is_equal(2001)
	assert_int(cal["month"]).is_equal(6)
	assert_int(cal["day"]).is_equal(15)
	assert_int(cal["hour"]).is_equal(14)
	assert_int(cal["minute"]).is_equal(30)
	assert_that(cal["season"]).is_equal(ClockService.Season.SUMMER)
	assert_int(cal["now_sec"]).is_equal(14 * 3600 + 30 * 60)


func test_hour_window_wraps_midnight() -> void:
	assert_bool(ClockService.hour_in_window(16, 16, 9)).is_true()
	assert_bool(ClockService.hour_in_window(8, 16, 9)).is_true()
	assert_bool(ClockService.hour_in_window(9, 16, 9)).is_false()
	assert_bool(ClockService.hour_in_window(15, 16, 9)).is_false()
	assert_bool(ClockService.hour_in_window(12, 0, 24)).is_true()
	assert_bool(ClockService.hour_in_window(9, 9, 22)).is_true()
	assert_bool(ClockService.hour_in_window(22, 9, 22)).is_false()


func test_field_renew_fires_when_crossing_six() -> void:
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 5, "minute": 0 })
	var box: Array = [0]
	var cb := func(days: int) -> void:
		box[0] = int(box[0]) + days
	Clock.field_renewed.connect(cb)
	Clock.advance_minutes(60)
	assert_int(Clock.hour).is_equal(6)
	assert_int(int(box[0])).is_equal(1)
	Clock.field_renewed.disconnect(cb)


func test_field_renew_counts_skipped_days() -> void:
	var box: Array = [0]
	var cb := func(days: int) -> void:
		box[0] = int(box[0]) + days
	Clock.field_renewed.connect(cb)
	Clock.advance_minutes(60 * 48)
	assert_int(int(box[0])).is_equal(2)
	Clock.field_renewed.disconnect(cb)


func test_apply_snapshot_does_not_renew() -> void:
	var box: Array = [0]
	var cb := func(days: int) -> void:
		box[0] = int(box[0]) + days
	Clock.field_renewed.connect(cb)
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 2, "hour": 7, "minute": 0 })
	assert_int(int(box[0])).is_equal(0)
	Clock.field_renewed.disconnect(cb)


func test_time_of_day_changed_on_dawn() -> void:
	Clock.apply_snapshot({ "year": 2001, "month": 3, "day": 20, "hour": 5, "minute": 0 })
	var seen: Array = []
	var cb := func(tod: ClockService.TimeOfDay) -> void:
		seen.append(tod)
	Clock.time_of_day_changed.connect(cb)
	Clock.advance_minutes(90)
	assert_that(Clock.time_of_day()).is_equal(ClockService.TimeOfDay.DAWN)
	assert_int(seen.size()).is_equal(1)
	assert_that(seen[0]).is_equal(ClockService.TimeOfDay.DAWN)
	Clock.time_of_day_changed.disconnect(cb)


func test_season_changed_signal_on_advance() -> void:
	Clock.apply_snapshot({ "year": 2001, "month": 2, "day": 24, "hour": 12, "minute": 0 })
	var seen: Array = []
	var cb := func(season: ClockService.Season) -> void:
		seen.append(season)
	Clock.season_changed.connect(cb)
	Clock.advance_minutes(60 * 24)
	assert_that(Clock.season()).is_equal(ClockService.Season.SPRING)
	assert_int(seen.size()).is_equal(1)
	Clock.season_changed.disconnect(cb)
