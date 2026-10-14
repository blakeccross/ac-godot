extends GdUnitTestSuite

## The calendar (`m_calendar.c`, `m_calendar_ovl.c`).

const Ev := CalendarBook.Ev
const T := CalendarBook.DayType


func _o(y: int, m: int, d: int) -> int:
	return EventDates.ordinal(y, m, d)


func test_holidays_land_on_their_days() -> void:
	var oct: Dictionary = CalendarBook.events_of(2026, 10, 15, Vector2i(10, 1))
	assert_that(oct.get(31)).is_equal([Ev.HALLOWEEN])
	## Explorer's Day: second Monday.
	assert_that(oct.get(12)).is_equal([Ev.EXPLORERS_DAY])
	assert_that(oct.get(1)).is_equal([Ev.PLAYER_BIRTHDAY])
	var nov: Dictionary = CalendarBook.events_of(2026, 11, 15, Vector2i.ZERO)
	## Mayor's Day the day after the first Monday; Harvest Festival the fourth Thursday and
	## the sale the day after; a fishing tourney every Sunday.
	assert_that(nov.get(3)).is_equal([Ev.MAYORS_DAY])
	assert_that(nov.get(26)).is_equal([Ev.HARVEST_FESTIVAL])
	assert_that(nov.get(27)).is_equal([Ev.SALE_DAY])
	assert_that(nov.get(1)).is_equal([Ev.FISHING_TOURNEY_2])
	assert_that(nov.get(29)).is_equal([Ev.FISHING_TOURNEY_2])
	var jul: Dictionary = CalendarBook.events_of(2026, 7, 18, Vector2i.ZERO)
	assert_that(jul.get(4)).is_equal([Ev.FIREWORKS_SHOW])
	assert_that(jul.get(18)).is_equal([Ev.TOWN_DAY])
	assert_str(CalendarBook.event_name(Ev.TOWN_DAY, "Pine")).ends_with("Day")


func test_the_page_grid() -> void:
	var state: Dictionary = CalendarBook.new_state()
	var today: int = _o(2026, 10, 3)
	CalendarBook.played_on(state, _o(2026, 9, 30))
	CalendarBook.played_on(state, _o(2026, 10, 2))
	CalendarBook.event_on(state, _o(2026, 10, 2))
	CalendarBook.played_on(state, today)
	var p: Dictionary = CalendarBook.page(2026, 10, state, today, 15, Vector2i.ZERO)
	## October 2026 starts on a Thursday.
	assert_int(int(p["first"])).is_equal(4)
	var days: Array = p["days"]
	assert_int(int(days[3])).is_equal(0)
	assert_int(int(days[4])).is_equal(1)
	assert_int(int(days[34])).is_equal(31)
	var types: Array = p["types"]
	assert_int(int(types[0])).is_equal(T.NONE)
	assert_int(int(types[4])).is_equal(T.NORMAL)
	assert_int(int(types[7])).is_equal(T.SUNDAY)
	assert_int(int(types[6])).is_equal(T.TODAY)
	assert_int(int(types[34])).is_equal(T.EVENT)
	var icons: Array = p["icons"]
	assert_int(int(icons[5])).is_equal(CalendarBook.ICON_TORTIMER)
	assert_int(int(icons[6])).is_equal(CalendarBook.ICON_PLAYED)
	assert_int(int(icons[4])).is_equal(0)
	var sep: Dictionary = CalendarBook.page(2026, 9, state, today, 15, Vector2i.ZERO)
	assert_int(int((sep["icons"] as Array)[int(sep["first"]) + 29])).is_equal(CalendarBook.ICON_PLAYED)


func test_marks_last_twelve_months() -> void:
	var state: Dictionary = CalendarBook.new_state()
	CalendarBook.played_on(state, _o(2025, 10, 5))
	CalendarBook.played_on(state, _o(2025, 11, 5))
	var today: int = _o(2026, 10, 3)
	assert_int(CalendarBook.icon(state, _o(2025, 11, 5), today)).is_equal(CalendarBook.ICON_PLAYED)
	## A year ago this month has dropped out.
	assert_int(CalendarBook.icon(state, _o(2025, 10, 5), today)).is_equal(0)
	CalendarBook.played_on(state, today)
	assert_bool(CalendarBook.played(state, _o(2025, 10, 5))).is_false()
	assert_bool(CalendarBook.played(state, _o(2025, 11, 5))).is_true()


func test_taking_part_needs_tortimer_or_the_birthday_played() -> void:
	var state: Dictionary = CalendarBook.new_state()
	var today: int = _o(2026, 11, 30)
	CalendarBook.event_on(state, _o(2026, 11, 3))
	CalendarBook.played_on(state, _o(2026, 11, 11))
	CalendarBook.played_on(state, _o(2026, 11, 20))
	var p: Dictionary = CalendarBook.page(2026, 11, state, today, 15, Vector2i(11, 20))
	var first: int = int(p["first"])
	var events: Dictionary = p["events"]
	assert_that(events[first + 2]).is_equal([[Ev.MAYORS_DAY, true]])
	assert_that(events[first + 10]).is_equal([[Ev.OFFICERS_DAY, false]])
	assert_that(events[first + 19]).is_equal([[Ev.PLAYER_BIRTHDAY, true]])


func test_months_either_side() -> void:
	assert_that(CalendarOverlay.month_at(2026, 10, 0)).is_equal(Vector2i(2026, 10))
	assert_that(CalendarOverlay.month_at(2026, 10, 3)).is_equal(Vector2i(2027, 1))
	assert_that(CalendarOverlay.month_at(2026, 10, -11)).is_equal(Vector2i(2025, 11))
