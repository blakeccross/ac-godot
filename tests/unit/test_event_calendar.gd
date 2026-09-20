class_name TestEventCalendar
extends GdUnitTestSuite

## `EventCalendar` / `EventDates` against dates worked out from `m_event_schedule.c_inc`.


func _cal() -> EventCalendar:
	var cal := EventCalendar.new()
	cal.assign_town(1234)
	return cal


func _at(cal: EventCalendar, y: int, m: int, d: int, h: int) -> EventCalendar:
	cal.sync(EventCalendar.make_date(y, m, d, h))
	return cal


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()


func after_test() -> void:
	Clock.reset_to_default()
	Clock.paused = false
	Game.reset_session()


func test_weekday_matches_clock() -> void:
	for ymd: Vector3i in [Vector3i(2001, 1, 1), Vector3i(2004, 3, 1), Vector3i(2026, 9, 19)]:
		Clock.set_datetime(ymd.x, ymd.y, ymd.z, 12)
		assert_int(EventDates.weekday(ymd.x, ymd.y, ymd.z)).is_equal(Clock.weekday())


func test_ordinal_round_trip() -> void:
	for ymd: Vector3i in [Vector3i(2001, 1, 1), Vector3i(2004, 12, 31), Vector3i(2030, 6, 15)]:
		var n: int = EventDates.ordinal(ymd.x, ymd.y, ymd.z)
		assert_that(EventDates.from_ordinal(n)).is_equal(ymd)


func test_equinox_and_harvest_moon() -> void:
	assert_int(EventDates.vernal_equinox_day(2001)).is_equal(20)
	assert_int(EventDates.autumnal_equinox_day(2001)).is_equal(23)
	assert_that(EventDates.harvest_moon(2020)).is_equal(Vector2i(10, 1))
	assert_that(EventDates.harvest_moon(2025)).is_equal(Vector2i(10, 6))


func test_halloween_spans_midnight() -> void:
	var cal := _cal()
	assert_bool(_at(cal, 2001, 10, 31, 17).is_active(&"halloween")).is_false()
	assert_bool(_at(cal, 2001, 10, 31, 18).is_active(&"halloween")).is_true()
	assert_bool(_at(cal, 2001, 10, 31, 23).is_active(&"halloween")).is_true()
	assert_bool(_at(cal, 2001, 11, 1, 0).is_active(&"halloween")).is_true()
	assert_bool(_at(cal, 2001, 11, 1, 1).is_active(&"halloween")).is_false()


func test_nth_weekday_events() -> void:
	var cal := _cal()
	## Nov 2001: the 1st is a Thursday, so the 4th Thursday is the 22nd (Harvest Festival,
	## 15–20) and Sale Day the 23rd. Mayor's Day is the day after the 1st Monday (Nov 6).
	assert_bool(_at(cal, 2001, 11, 22, 14).is_active(&"harvest_festival")).is_false()
	assert_bool(_at(cal, 2001, 11, 22, 15).is_active(&"harvest_festival")).is_true()
	assert_bool(_at(cal, 2001, 11, 23, 12).is_active(&"sale_day")).is_true()
	assert_bool(_at(cal, 2001, 11, 6, 10).is_active(&"mayors_day")).is_true()
	assert_bool(_at(cal, 2001, 11, 5, 10).is_active(&"mayors_day")).is_false()


func test_weather_overrides() -> void:
	var cal := _cal()
	assert_that(_at(cal, 2001, 7, 4, 12).weather_override()).is_equal(&"clear")
	assert_that(_at(cal, 2001, 12, 24, 9).weather_override()).is_equal(&"snow")
	assert_that(_at(cal, 2001, 3, 3, 9).weather_override()).is_equal(&"")


func test_sports_fair_only_on_equinox() -> void:
	var cal := _cal()
	assert_bool(_at(cal, 2001, 3, 19, 9).is_active(&"sports_fair_aerobics")).is_false()
	assert_bool(_at(cal, 2001, 3, 20, 9).is_active(&"sports_fair_aerobics")).is_true()
	assert_bool(_at(cal, 2001, 3, 20, 11).is_active(&"sports_fair_foot_race")).is_true()
	assert_bool(_at(cal, 2001, 9, 23, 13).is_active(&"sports_fair_ball_toss")).is_true()


func test_harvest_moon_follows_lunar_date() -> void:
	var cal := _cal()
	assert_bool(_at(cal, 2001, 10, 1, 18).is_active(&"harvest_moon_festival")).is_true()
	assert_bool(_at(cal, 2001, 9, 30, 18).is_active(&"harvest_moon_festival")).is_false()
	assert_bool(_at(cal, 2001, 9, 24, 12).is_active(&"rumor_harvest_moon_day")).is_true()


func test_year_wrap_range() -> void:
	var cal := _cal()
	## Snowman season runs Dec 25 → Feb 17.
	assert_bool(_at(cal, 2001, 12, 25, 12).is_active(&"snowman_season")).is_true()
	assert_bool(_at(cal, 2001, 2, 17, 12).is_active(&"snowman_season")).is_true()
	assert_bool(_at(cal, 2001, 2, 18, 12).is_active(&"snowman_season")).is_false()
	assert_bool(_at(cal, 2001, 6, 1, 12).is_active(&"snowman_season")).is_false()


func test_weekly_visitors() -> void:
	## 2001-01-07 is a Sunday.
	var cal := _cal()
	assert_bool(_at(cal, 2001, 1, 7, 5).is_active(&"kabu_peddler")).is_false()
	assert_bool(_at(cal, 2001, 1, 7, 6).is_active(&"kabu_peddler")).is_true()
	assert_bool(_at(cal, 2001, 1, 7, 12).is_active(&"kabu_peddler")).is_false()
	assert_bool(_at(cal, 2001, 1, 6, 20).is_active(&"kk_slider")).is_true()
	assert_bool(_at(cal, 2001, 1, 6, 19).is_active(&"kk_slider")).is_false()


func test_gulliver_once_a_week() -> void:
	var cal := _cal()
	var days: int = 0
	for day: int in range(8, 13):
		cal.sync(EventCalendar.make_date(2001, 1, day, 6))
		if cal.is_today(&"dozaemon"):
			days += 1
	assert_int(days).is_equal(1)


func test_special_visit_is_unique_and_stable() -> void:
	var cal := _cal()
	_at(cal, 2001, 5, 10, 8)
	assert_bool(cal.special_type in EventCalendar.SPECIAL_POOL).is_true()
	var first: StringName = cal.special_type
	var start: int = int(cal.special_dates["special1"])
	## Same visit for every later hour of the window.
	_at(cal, 2001, 5, 10, 20)
	assert_that(cal.special_type).is_equal(first)
	assert_int(int(cal.special_dates["special1"])).is_equal(start)
	## Only the scheduled visit's row ever lights up.
	for id: StringName in EventCalendar.SPECIAL_POOL:
		if id != first:
			assert_bool(cal.is_today(id)).is_false()


func test_special_visit_rolls_again_after_window() -> void:
	var cal := _cal()
	_at(cal, 2001, 5, 10, 8)
	var first: StringName = cal.special_type
	var end_md: int = int(cal.special_dates["special2"])
	## A week after the window closes a different visit is scheduled.
	cal.sync(EventCalendar.make_date(2001, EventDates.md_month(end_md) + 1, 20, 12))
	assert_bool(cal.special_type != first).is_true()


func test_sale_day_forces_redd() -> void:
	var cal := _cal()
	## Nov 21 2001: the next visit would land on/after Sale Day (Nov 23), so it becomes Redd.
	_at(cal, 2001, 11, 21, 8)
	assert_that(cal.special_type).is_equal(&"broker_sale")
	assert_int(int(cal.special_dates["special1"])).is_equal(EventDates.md(11, 23))
	assert_int(int(cal.special_dates["special3"])).is_equal(18)


func test_schedule_special_starts_now() -> void:
	var cal := _cal()
	var now: Dictionary = EventCalendar.make_date(2001, 5, 10, 13)
	assert_bool(cal.schedule_special(&"gypsy", now)).is_true()
	cal.sync(now)
	assert_bool(cal.is_active(&"gypsy")).is_true()
	assert_bool(cal.schedule_special(&"halloween", now)).is_false()


func test_next_start_scans_forward() -> void:
	var cal := _cal()
	var hit: Dictionary = cal.next_start(&"harvest_moon_festival", EventCalendar.make_date(2001, 1, 1, 0))
	assert_int(int(hit["month"])).is_equal(10)
	assert_int(int(hit["day"])).is_equal(1)
	assert_int(int(hit["hour"])).is_equal(18)
	## Weekly visitors work off the raw calendar: from a Monday the next K.K. is Saturday.
	var kk: Dictionary = cal.next_start(&"kk_slider", EventCalendar.make_date(2001, 1, 8, 0))
	assert_int(int(kk["day"])).is_equal(13)
	assert_int(int(kk["hour"])).is_equal(20)
	assert_bool(cal.next_start(&"gypsy", EventCalendar.make_date(2001, 1, 1, 0)).is_empty()).is_true()


func test_forced_event_emits_once() -> void:
	var cal := _cal()
	var started: Array[StringName] = []
	cal.event_started.connect(func(id: StringName) -> void: started.append(id))
	_at(cal, 2001, 3, 3, 9)
	assert_bool(started.is_empty()).is_true()
	cal.force(&"halloween")
	_at(cal, 2001, 3, 3, 9)
	_at(cal, 2001, 3, 3, 10)
	assert_int(started.count(&"halloween")).is_equal(1)
	cal.unforce(&"halloween")
	_at(cal, 2001, 3, 3, 11)
	assert_bool(cal.is_active(&"halloween")).is_false()


func test_first_sync_is_silent() -> void:
	var cal := _cal()
	var started: Array[StringName] = []
	cal.event_started.connect(func(id: StringName) -> void: started.append(id))
	_at(cal, 2001, 10, 31, 20)
	assert_bool(started.is_empty()).is_true()
	assert_bool(cal.is_active(&"halloween")).is_true()


func test_save_round_trip() -> void:
	var cal := _cal()
	_at(cal, 2001, 5, 10, 8)
	var copy := EventCalendar.new()
	copy.apply_snapshot(cal.to_save())
	assert_that(copy.special_type).is_equal(cal.special_type)
	assert_that(copy.weekly_type).is_equal(cal.weekly_type)
	assert_int(copy.town_day).is_equal(cal.town_day)
	assert_int(int(copy.special_dates["special1"])).is_equal(int(cal.special_dates["special1"]))


func test_console_start_and_goto() -> void:
	var console := DebugConsole.new()
	Clock.set_datetime(2001, 3, 3, 9)
	assert_str(console.execute("event start halloween")).contains("Halloween")
	assert_bool(Game.events.is_active(&"halloween")).is_true()
	console.execute("event stop")
	assert_bool(Game.events.is_active(&"halloween")).is_false()
	assert_str(console.execute("event goto halloween")).contains("Halloween")
	assert_int(Clock.month).is_equal(10)
	assert_int(Clock.day).is_equal(31)
	assert_int(Clock.hour).is_equal(18)
	assert_str(console.execute("event start nonsense")).contains("Unknown event")
