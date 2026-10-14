class_name CalendarBook
extends RefCounted

## The player's calendar (`m_calendar.c`, `m_calendar_ovl.c`). Two things are remembered for
## the last twelve months: the days the player played (`mCD_calendar_wellcome_on`, at game
## start and each new day) and the holidays where they talked to Tortimer
## (`mCD_calendar_event_on`). The calendar page marks played days with a footprint and
## Tortimer days with a red one, lists each day's events (`mSC_EVENT_*`) with a fish badge
## on the ones the player took part in, and colours the boxes by day type.
##
## The original keeps one bitfield per month plus flags for a few events and wipes the
## months it skips; here they are day numbers (`EventDates.ordinal`) trimmed to the window.

enum DayType { NONE, NORMAL, SUNDAY, EVENT, TODAY }

const CELLS := 37
const WEEK := 7
## `mCD_make_icon`: marks show for this many months back, this month included.
const WINDOW_MONTHS := 12
## Icons: played, Tortimer.
const ICON_PLAYED := 1
const ICON_TORTIMER := 2
## `mSC_EVENT_*` (the same order as `TortimerHoliday.EVENTS`) and the birthday after them.
enum Ev {
	NEW_YEARS_DAY, FOUNDERS_DAY, GRADUATION_DAY, APRILFOOLS_DAY, TOWN_DAY, MOTHERS_DAY, SALE_DAY,
	CHERRY_BLOSSOM_FESTIVAL, SPRING_SPORTS_FAIR, NATURE_DAY, SPRING_CLEANING, FATHERS_DAY,
	FISHING_TOURNEY_1, GROUNDHOG_DAY, EXPLORERS_DAY, FIREWORKS_SHOW, METEOR_SHOWER,
	HARVEST_MOON_FESTIVAL, MAYORS_DAY, OFFICERS_DAY, FALL_SPORTS_FAIR, HALLOWEEN, FISHING_TOURNEY_2,
	SNOW_DAY, LABOR_DAY, TOY_DAY, NEW_YEARS_EVE_COUNTDOWN, HARVEST_FESTIVAL, PLAYER_BIRTHDAY,
}
## `mCD_make_calendar_data_fixed_day_event`: [month, day, event].
const FIXED: Array = [
	[1, 1, Ev.NEW_YEARS_DAY], [2, 2, Ev.GROUNDHOG_DAY], [4, 1, Ev.APRILFOOLS_DAY],
	[4, 5, Ev.CHERRY_BLOSSOM_FESTIVAL], [4, 6, Ev.CHERRY_BLOSSOM_FESTIVAL], [4, 7, Ev.CHERRY_BLOSSOM_FESTIVAL],
	[4, 22, Ev.NATURE_DAY], [5, 1, Ev.SPRING_CLEANING], [7, 4, Ev.FIREWORKS_SHOW], [8, 12, Ev.METEOR_SHOWER],
	[8, 21, Ev.FOUNDERS_DAY], [10, 31, Ev.HALLOWEEN], [11, 11, Ev.OFFICERS_DAY], [12, 1, Ev.SNOW_DAY],
	[12, 23, Ev.TOY_DAY], [12, 31, Ev.NEW_YEARS_EVE_COUNTDOWN],
]
## `mCD_make_calendar_data_unfixed_day_event`: [month, nth, weekday, days after, event].
const BY_WEEKDAY: Array = [
	[5, 2, 0, 0, Ev.MOTHERS_DAY], [6, 2, 5, 0, Ev.GRADUATION_DAY], [6, 3, 0, 0, Ev.FATHERS_DAY],
	[9, 1, 1, 0, Ev.LABOR_DAY], [10, 2, 1, 0, Ev.EXPLORERS_DAY], [11, 1, 1, 1, Ev.MAYORS_DAY],
	[11, 4, 4, 0, Ev.HARVEST_FESTIVAL], [11, 4, 4, 1, Ev.SALE_DAY],
]
## `chg_string_idx`: the event's name in the ROM strings from 0x6F8.
const NAME_STRING := 0x6F8
const NAME_INDEX: Array[int] = [0, 14, 8, 3, 11, 7, 24, 4, 2, 5, 6, 9, 10, 1, 18, 12, 13, 17, 20, 21, 16, 19,
	22, 25, 15, 26, 27, 23, 28]


static func new_state() -> Dictionary:
	return {"played": [], "events": []}


static func _months_back(today: int, ordinal: int) -> int:
	var a: Vector3i = EventDates.from_ordinal(today)
	var b: Vector3i = EventDates.from_ordinal(ordinal)
	return (a.x - b.x) * 12 + (a.y - b.y)


## Drop what has left the window (`mCD_calendar_check_delete`): older months, and anything
## after today (a clock set back).
static func trim(state: Dictionary, today: int) -> void:
	for key: String in ["played", "events"]:
		var kept: Array = []
		for n: Variant in state.get(key, []):
			var back: int = _months_back(today, int(n))
			if int(n) <= today and back >= 0 and back < WINDOW_MONTHS:
				kept.append(int(n))
		state[key] = kept


static func _mark(state: Dictionary, key: String, today: int) -> void:
	trim(state, today)
	var days: Array = state[key]
	if not days.has(today):
		days.append(today)


## `mCD_calendar_wellcome_on`.
static func played_on(state: Dictionary, today: int) -> void:
	_mark(state, "played", today)


## `mCD_calendar_event_on`: Tortimer was spoken to on a holiday.
static func event_on(state: Dictionary, today: int) -> void:
	_mark(state, "events", today)


static func played(state: Dictionary, ordinal: int) -> bool:
	return (state.get("played", []) as Array).has(ordinal)


static func attended(state: Dictionary, ordinal: int) -> bool:
	return (state.get("events", []) as Array).has(ordinal)


## `mCD_make_icon`: 2 Tortimer, 1 played, 0 nothing (or out of the window).
static func icon(state: Dictionary, ordinal: int, today: int) -> int:
	var back: int = _months_back(today, ordinal)
	if back < 0 or back >= WINDOW_MONTHS:
		return 0
	if attended(state, ordinal):
		return ICON_TORTIMER
	if played(state, ordinal):
		return ICON_PLAYED
	return 0


## The month's holidays as {day: [event, …]} (`mCD_make_calendar_data_year`).
static func events_of(year: int, month: int, town_day: int, birthday: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	var add := func(day: int, ev: int) -> void:
		if day < 1:
			return
		if not out.has(day):
			out[day] = []
		(out[day] as Array).append(ev)
	for row: Array in FIXED:
		if int(row[0]) == month:
			add.call(int(row[1]), int(row[2]))
	for row: Array in BY_WEEKDAY:
		if int(row[0]) == month:
			add.call(EventDates.nth_weekday_day(year, month, int(row[1]), int(row[2])) + int(row[3]), int(row[4]))
	if month == 6 or month == 11:
		var sunday: int = EventDates.nth_weekday_day(year, month, 1, 0)
		while sunday <= EventDates.days_in_month(year, month):
			add.call(sunday, Ev.FISHING_TOURNEY_1 if month == 6 else Ev.FISHING_TOURNEY_2)
			sunday += WEEK
	if month == 3:
		add.call(EventDates.vernal_equinox_day(year), Ev.SPRING_SPORTS_FAIR)
	if month == 9:
		add.call(EventDates.autumnal_equinox_day(year), Ev.FALL_SPORTS_FAIR)
	if month == 7:
		add.call(town_day, Ev.TOWN_DAY)
	var moon: Vector2i = EventDates.harvest_moon(year)
	if moon.x == month:
		add.call(moon.y, Ev.HARVEST_MOON_FESTIVAL)
	if birthday.x == month:
		add.call(birthday.y, Ev.PLAYER_BIRTHDAY)
	return out


## One month's page: `days` (day number per cell, 0 empty), `types` (`DayType`), `icons`
## and `events` (cell → [[event, attended], …]). `today` marks the current day's cell.
static func page(year: int, month: int, state: Dictionary, today: int, town_day: int, birthday: Vector2i) -> Dictionary:
	var days: Array[int] = []
	var types: Array[int] = []
	var icons: Array[int] = []
	days.resize(CELLS)
	types.resize(CELLS)
	icons.resize(CELLS)
	var first: int = EventDates.weekday(year, month, 1)
	var count: int = EventDates.days_in_month(year, month)
	for d: int in range(1, count + 1):
		var cell: int = first + d - 1
		days[cell] = d
		types[cell] = DayType.SUNDAY if cell % WEEK == 0 else DayType.NORMAL
		icons[cell] = icon(state, EventDates.ordinal(year, month, d), today)
	var events: Dictionary = {}
	var by_day: Dictionary = events_of(year, month, town_day, birthday)
	for d: Variant in by_day:
		var cell: int = first + int(d) - 1
		var ordinal: int = EventDates.ordinal(year, month, int(d))
		var list: Array = []
		for ev: Variant in by_day[d]:
			if int(ev) != Ev.PLAYER_BIRTHDAY:
				types[cell] = DayType.EVENT
			## `mCD_make_calendar_event_sanka_check`: the birthday counts when played.
			var took_part: bool = (
				played(state, ordinal) if int(ev) == Ev.PLAYER_BIRTHDAY else attended(state, ordinal)
			) and icon(state, ordinal, today) != 0
			list.append([int(ev), took_part])
		events[cell] = list
	var now: Vector3i = EventDates.from_ordinal(today)
	if now.x == year and now.y == month:
		types[first + now.z - 1] = DayType.TODAY
	return {"days": days, "types": types, "icons": icons, "events": events, "first": first}


## `mSC_get_event_name_str` (Town Day leads with the town's name).
static func event_name(ev: int, town: String) -> String:
	var n: String = DialogueCatalog.rom_string(NAME_STRING + NAME_INDEX[clampi(ev, 0, NAME_INDEX.size() - 1)])
	if ev == Ev.TOWN_DAY:
		return town + " " + n
	return n
