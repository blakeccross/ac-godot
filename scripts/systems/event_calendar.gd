class_name EventCalendar
extends RefCounted

## Event scheduler (`m_event.c`): resolves `EventSchedule` rows against a date into per-hour
## active flags, owns the weekly visitor + special-NPC state, and reports starts/ends.
## Owned by `Game`. It never touches the world — presenters listen to the signals.
## Decomp behaviour and field encodings: `docs/decomp_notes/events.md`.

signal event_started(id: StringName)
signal event_ended(id: StringName)

## `special_event_types[]`: exactly one of these is scheduled at a time.
const SPECIAL_POOL: Array[StringName] = [
	&"shop_sale", &"designer", &"broker_sale", &"artist", &"carpet_peddler", &"gypsy"
]
## `get_special_event_end_time`.
const SPECIAL_END_HOUR: Dictionary = {
	&"designer": 5, &"artist": 5, &"carpet_peddler": 5, &"gypsy": 20, &"broker_sale": 17,
	&"shop_sale": 23,
}
## `mFAs_FIELDRANK_SIX`. The rank widens or narrows the gap between special visits; there is
## no town-rating system yet, so `field_rank` stays at a middling constant.
const FIELD_RANK_MAX := 6
const DEFAULT_FIELD_RANK := 3
const SLOT_NAMES: Array[String] = [
	"today", "last_play", "birthday", "special0", "special1", "special2", "weekly", "special3"
]

## Fixed per town (`Save_Get(town_day)`): the July "Town Day" date.
var town_day: int = 15
var town_seed: int = 0
var field_rank: int = DEFAULT_FIELD_RANK
## Player birthday as `md` (0 = unset, so the birthday row never fires).
var birthday_md: int = 0
## `weekly_event`: which weekly visitor owns today, and the date Gulliver was rolled for.
var weekly_type: StringName = &""
var weekly_date: int = 0
## `special_event`: the one scheduled special visit and its dates (`dates[SPECIAL0..3]`).
var special_type: StringName = &""
var special_year: int = 0
var special_dates: Dictionary = {"special0": 0, "special1": 0, "special2": 0, "special3": 6}

var _forced: Dictionary = {}
var _hours: Dictionary = {}
var _active: Dictionary = {}
var _day_key: String = ""
var _primed: bool = false


func clear() -> void:
	town_day = 15
	town_seed = 0
	field_rank = DEFAULT_FIELD_RANK
	birthday_md = 0
	weekly_type = &""
	weekly_date = 0
	special_type = &""
	special_year = 0
	special_dates = {"special0": 0, "special1": 0, "special2": 0, "special3": 6}
	_forced.clear()
	_hours.clear()
	_active.clear()
	_day_key = ""
	_primed = false


## New town: the seed fixes `town_day` and the special-visit rolls. Keeps any other state.
func assign_town(seed_value: int) -> void:
	town_seed = seed_value
	town_day = 1 + posmod(seed_value, 28)


static func date_from_clock() -> Dictionary:
	return make_date(Clock.year, Clock.month, Clock.day, Clock.hour)


static func make_date(year: int, month: int, day: int, hour: int) -> Dictionary:
	return {
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"weekday": EventDates.weekday(year, month, day),
	}


# --- queries -------------------------------------------------------------------------


## Active this hour (scheduled or forced).
func is_active(id: StringName) -> bool:
	return _active.has(id)


## Scheduled for any hour today.
func is_today(id: StringName) -> bool:
	return int(_hours.get(id, 0)) != 0 or _forced.has(id)


func active_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in _active:
		out.append(id as StringName)
	out.sort()
	return out


func today_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in _hours:
		if int(_hours[id]) != 0:
			out.append(id as StringName)
	out.sort()
	return out


## `mEv_spread_rumor`: rumor / talk ids villagers can bring up right now.
func active_rumors() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in active_ids():
		if EventSchedule.is_rumor(id):
			out.append(id)
	return out


## `mEv_GetEventWeather`: `clear`, `snow`, or `&""` for no override.
func weather_override() -> StringName:
	if is_active(&"weather_clear"):
		return &"clear"
	if is_active(&"weather_snow"):
		return &"snow"
	if is_active(&"weather_sports_fair"):
		return &"clear"
	return &""


func forced_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in _forced:
		out.append(id as StringName)
	out.sort()
	return out


## Human-readable summary for the debug console.
func describe() -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append("Active: %s" % _join(active_ids()))
	var later: Array[StringName] = []
	for id: StringName in today_ids():
		if not is_active(id):
			later.append(id)
	lines.append("Later today: %s" % _join(later))
	lines.append("Weekly visitor: %s" % (String(weekly_type) if weekly_type != &"" else "-"))
	lines.append("Special visit: %s" % _describe_special())
	if not _forced.is_empty():
		lines.append("Forced: %s" % _join(forced_ids()))
	return lines


# --- debug controls ------------------------------------------------------------------


func force(id: StringName) -> void:
	_forced[id] = true


func unforce(id: StringName) -> void:
	_forced.erase(id)


func clear_forced() -> void:
	_forced.clear()


## Make `id` (one of `SPECIAL_POOL`) the scheduled special visit and force it on now (the
## table's own start hours, e.g. Redd at 18:00, would otherwise make you wait).
func schedule_special(id: StringName, now: Dictionary) -> bool:
	if id not in SPECIAL_POOL:
		return false
	var today: int = EventDates.md(int(now["month"]), int(now["day"]))
	special_type = id
	special_year = int(now["year"])
	special_dates["special0"] = today
	special_dates["special1"] = today
	special_dates["special2"] = EventDates.after_n_day(
		special_year, today, 0 if id == &"shop_sale" else 1
	)
	special_dates["special3"] = int(now["hour"])
	_day_key = ""
	force(id)
	return true


## First start at/after `now` for a date-driven event, or `{}` (state-driven events such as
## the special visits are not predictable from the calendar alone).
func next_start(id: StringName, now: Dictionary, max_days: int = 400) -> Dictionary:
	if id in SPECIAL_POOL or String(id).begins_with("handbill_"):
		return {}
	var base: int = EventDates.ordinal(int(now["year"]), int(now["month"]), int(now["day"]))
	for offset: int in max_days + 1:
		var ymd: Vector3i = EventDates.from_ordinal(base + offset)
		if ymd.x > Clock.MAX_YEAR:
			return {}
		var probe: Dictionary = make_date(ymd.x, ymd.y, ymd.z, 0)
		var mask: int = int(resolve_day(probe, false).get(id, 0))
		if mask == 0:
			continue
		var from_hour: int = int(now["hour"]) if offset == 0 else 0
		for h: int in range(from_hour, 24):
			if (mask >> h) & 1:
				probe["hour"] = h
				return probe
	return {}


# --- ticking -------------------------------------------------------------------------


## Bring the calendar to `now`. Emits `event_started` / `event_ended` for changes, except on
## the first call after `clear` / `apply_snapshot`, which just adopts the current state.
func sync(now: Dictionary) -> void:
	var key: String = "%d-%d-%d" % [int(now["year"]), int(now["month"]), int(now["day"])]
	var new_day: bool = key != _day_key
	if new_day:
		_day_key = key
		_init_weekly(now)
	var special_changed: bool = _init_special(now)
	if new_day or special_changed:
		_hours = resolve_day(now, true)
	_refresh_active(int(now["hour"]))


func _refresh_active(hour: int) -> void:
	var next: Dictionary = {}
	for id: Variant in _hours:
		if (int(_hours[id]) >> hour) & 1:
			next[id] = true
	for id: Variant in _forced:
		next[id] = true
	var started: Array[StringName] = []
	var ended: Array[StringName] = []
	for id: Variant in next:
		if not _active.has(id):
			started.append(id as StringName)
	for id: Variant in _active:
		if not next.has(id):
			ended.append(id as StringName)
	_active = next
	var announce: bool = _primed
	_primed = true
	if not announce:
		return
	started.sort()
	ended.sort()
	for id: StringName in ended:
		event_ended.emit(id)
	for id: StringName in started:
		event_started.emit(id)


# --- schedule resolution ---------------------------------------------------------------


## `update_schedule_today`: `id -> 24-bit active-hours mask` for `now`'s date. With
## `gated` false the weekly / special / unsupported gates are skipped (for `next_start`).
func resolve_day(now: Dictionary, gated: bool = true) -> Dictionary:
	var year: int = int(now["year"])
	var today: int = EventDates.md(int(now["month"]), int(now["day"]))
	var out: Dictionary = {}
	var soncho_claimed: bool = false
	var equinox_day: int = 0
	for row: Dictionary in EventSchedule.rows():
		var id: StringName = StringName(String(row["id"]))
		if gated and _row_gated_off(id):
			continue
		if id in [&"soncho_fishing_tourney_1", &"soncho_fishing_tourney_2"] and soncho_claimed:
			continue
		var begin: int = _decode(row["begin"] as Dictionary, now)
		var end: int = _decode(row["end"] as Dictionary, now)
		var span: Vector2i = _patch(id, begin, end, now, equinox_day)
		if span.x < 0:
			continue
		begin = span.x
		end = span.y
		if id in [&"spring_equinox", &"autumn_equinox"]:
			equinox_day = EventDates.md_day(begin)
		if begin == 0 or not EventDates.in_range(today, begin, end):
			continue
		if id in [&"soncho_fathers_day", &"soncho_officers_day"]:
			soncho_claimed = true
		var b_hour: int = _hour(row["begin"] as Dictionary)
		var e_hour: int = _hour(row["end"] as Dictionary)
		if row.get("multiday", false):
			if today != begin:
				b_hour = 0
			if today != end:
				e_hour = 23
		var mask: int = 0
		for h: int in 24:
			if b_hour <= h and h <= e_hour:
				mask |= 1 << h
		out[id] = int(out.get(id, 0)) | mask
	return out


func _row_gated_off(id: StringName) -> bool:
	if id in EventSchedule.UNSUPPORTED:
		return true
	if id in SPECIAL_POOL:
		return id != special_type
	if id == &"handbill_shop_sale":
		return special_type != &"shop_sale"
	if id == &"handbill_broker":
		return special_type != &"broker_sale"
	if id == &"kk_slider" or id == &"kabu_peddler" or id == &"dozaemon":
		return weekly_type != id
	return false


## Per-event date patches (`update_sports_fair`, `update_event_rumor`, summer camper).
## Returns the adjusted `(begin, end)` or `Vector2i(-1, -1)` to drop the row today.
func _patch(id: StringName, begin: int, end: int, now: Dictionary, equinox_day: int) -> Vector2i:
	var year: int = int(now["year"])
	var today: int = EventDates.md(int(now["month"]), int(now["day"]))
	match id:
		&"spring_equinox", &"soncho_spring_sports_fair":
			var vernal: int = EventDates.vernal_equinox_day(year)
			if int(now["month"]) != 3 or int(now["day"]) != vernal:
				return Vector2i(-1, -1)
			return Vector2i(EventDates.md(3, vernal), EventDates.md(3, vernal))
		&"autumn_equinox", &"soncho_fall_sports_fair":
			var autumnal: int = EventDates.autumnal_equinox_day(year)
			if int(now["month"]) != 9 or int(now["day"]) != autumnal:
				return Vector2i(-1, -1)
			return Vector2i(EventDates.md(9, autumnal), EventDates.md(9, autumnal))
		&"sports_fair_ball_toss", &"sports_fair_aerobics", &"sports_fair_tug_of_war", \
		&"sports_fair_foot_race", &"sports_fair", &"weather_sports_fair":
			if equinox_day == 0:
				return Vector2i(-1, -1)
			return Vector2i(
				EventDates.md(EventDates.md_month(begin), equinox_day),
				EventDates.md(EventDates.md_month(end), equinox_day)
			)
		&"rumor_spring_sports_fair":
			var v: int = EventDates.vernal_equinox_day(year)
			return Vector2i(EventDates.md(3, v - 10), EventDates.md(3, v - 1))
		&"rumor_fall_sports_fair":
			var a: int = EventDates.autumnal_equinox_day(year)
			return Vector2i(EventDates.md(9, a - 10), EventDates.md(9, a - 1))
		&"rumor_harvest_moon_day":
			var moon: Vector2i = EventDates.harvest_moon(year)
			var moon_md: int = EventDates.md(moon.x, moon.y)
			return Vector2i(
				EventDates.after_n_day(year, moon_md, -7), EventDates.after_n_day(year, moon_md, -1)
			)
		&"summer_camper":
			return _camper_span(now)
	return Vector2i(begin, end)


## The camper pitches a tent from Saturday morning to Sunday afternoon, all summer.
func _camper_span(now: Dictionary) -> Vector2i:
	var month: int = int(now["month"])
	if month < 6 or month > 8:
		return Vector2i(-1, -1)
	var year: int = int(now["year"])
	var start: int = _decode(
		{"month": month, "day": {"nth": "every", "weekday": 6}, "hour": 0}, now
	)
	if int(now["weekday"]) == 0:
		start = EventDates.after_n_day(year, start, -7)
	return Vector2i(start, EventDates.after_n_day(year, start, 1))


## `decode_date` for one begin/end field → `md`.
func _decode(field: Dictionary, now: Dictionary) -> int:
	var year: int = int(now["year"])
	var month_spec: Variant = field["month"]
	var day_spec: Variant = field["day"]
	var month: int = 0
	if typeof(month_spec) == TYPE_STRING:
		var text: String = String(month_spec)
		if text.begins_with("save:"):
			return _saved_md(text.substr(5), now)
		if text == "moon":
			var moon: Vector2i = EventDates.harvest_moon(year)
			return EventDates.md(moon.x, moon.y)
		month = int(now["month"])
	else:
		month = int(month_spec)
	if typeof(day_spec) == TYPE_DICTIONARY:
		var spec: Dictionary = day_spec as Dictionary
		var day: int = _weekday_day(year, month, spec, now)
		var value: int = EventDates.md(month, day)
		if spec.get("after", false):
			value = EventDates.after_n_day(year, value, 1)
		return value
	if typeof(day_spec) == TYPE_STRING:
		if String(day_spec) == "town_day":
			return EventDates.md(month, town_day)
		return EventDates.md(month, EventDates.days_in_month(year, month))
	return EventDates.md(month, int(day_spec))


## `m_weekday2day`: Nth / last / this-week's `weekday`.
func _weekday_day(year: int, month: int, spec: Dictionary, now: Dictionary) -> int:
	var wd: int = int(spec["weekday"])
	var nth: Variant = spec["nth"]
	if typeof(nth) == TYPE_STRING:
		if String(nth) == "last":
			return EventDates.last_weekday_day(year, month, wd)
		## "every": the occurrence in the current week, or the edge of another month.
		if month > int(now["month"]):
			return EventDates.nth_weekday_day(year, month, 1, wd)
		if month < int(now["month"]):
			return EventDates.last_weekday_day(year, month, wd)
		var day: int = int(now["day"]) - (int(now["weekday"]) - wd)
		if day < 1 or day > EventDates.days_in_month(year, month):
			return EventDates.last_weekday_day(year, month, wd)
		return day
	return EventDates.nth_weekday_day(year, month, int(nth), wd)


func _hour(field: Dictionary) -> int:
	var spec: Variant = field["hour"]
	if typeof(spec) == TYPE_STRING and String(spec).begins_with("save:"):
		return int(special_dates.get(String(spec).substr(5), 0))
	return int(spec)


func _saved_md(slot: String, now: Dictionary) -> int:
	match slot:
		"today":
			return EventDates.md(int(now["month"]), int(now["day"]))
		"birthday":
			return birthday_md
		"weekly":
			return weekly_date
	return int(special_dates.get(slot, 0))


# --- weekly visitor ------------------------------------------------------------------


## `init_weekly_event`: Joan on Sunday, K.K. on Saturday, Gulliver once Monday–Friday. The
## bridge, Blanca and the wisp are not modelled yet.
func _init_weekly(now: Dictionary) -> void:
	var year: int = int(now["year"])
	var wd: int = int(now["weekday"])
	var today: int = EventDates.md(int(now["month"]), int(now["day"]))
	match wd:
		0:
			if today != weekly_date:
				weekly_date = today
				weekly_type = &"kabu_peddler"
		6:
			if today != weekly_date:
				weekly_date = today
				weekly_type = &"kk_slider"
		_:
			var monday: int = EventDates.after_n_day(year, today, 1 - wd)
			var friday: int = EventDates.after_n_day(year, today, 5 - wd)
			if weekly_date == 0 or not EventDates.in_range(weekly_date, monday, friday):
				var offset: int = 1 + (today + int(now["hour"])) % 5
				weekly_date = EventDates.after_n_day(year, today, offset - wd)
				weekly_type = &"dozaemon"


# --- special NPC visit -----------------------------------------------------------------


## `init_special_event`: keep the scheduled visit until its window ends, then roll the next.
## Returns true when a new visit was scheduled.
func _init_special(now: Dictionary) -> bool:
	var year: int = int(now["year"])
	if special_type != &"" and _in_special_window(now):
		return false
	return _roll_special(now, year)


func _in_special_window(now: Dictionary) -> bool:
	var s0: int = int(special_dates["special0"])
	var s2: int = int(special_dates["special2"])
	var begin: int = EventDates.ordinal(special_year, EventDates.md_month(s0), EventDates.md_day(s0)) * 24
	var end_year: int = special_year + (1 if s0 > s2 else 0)
	var end: int = (
		EventDates.ordinal(end_year, EventDates.md_month(s2), EventDates.md_day(s2)) * 24
		+ int(SPECIAL_END_HOUR.get(special_type, 0))
	)
	var at: int = (
		EventDates.ordinal(int(now["year"]), int(now["month"]), int(now["day"])) * 24
		+ int(now["hour"])
	)
	return begin <= at and at <= end


func _roll_special(now: Dictionary, year: int) -> bool:
	var month: int = int(now["month"])
	var day: int = int(now["day"])
	var today: int = EventDates.md(month, day)
	var seed_value: int = (
		(town_seed & 0x00FFFFFF) + 1 + (year - month) + day + int(now["hour"])
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	## Sale Day: the day after the 4th Thursday of November.
	var sale_day: int = EventDates.after_n_day(
		year, EventDates.md(11, EventDates.nth_weekday_day(year, 11, 4, 4)), 1
	)
	var pick: StringName = &""
	var start: int = today
	var start_hour: int = 6
	for _attempt: int in 64:
		pick = SPECIAL_POOL[posmod(seed_value, SPECIAL_POOL.size())]
		seed_value += 1
		if pick == special_type:
			continue
		var gap: int = 1 + (day + month * (town_seed % 60)) % ((FIELD_RANK_MAX + 1) - field_rank)
		if gap == 1:
			gap = 2
		start = EventDates.after_n_day(year, today, gap)
		if start == EventDates.md(12, 31):
			start = EventDates.after_n_day(year, start, 1)
		if today <= sale_day and sale_day <= start:
			start = sale_day
			pick = &"broker_sale"
		start_hour = 6
		match pick:
			&"shop_sale":
				var last: int = EventDates.days_in_month(year, EventDates.md_month(start))
				var early_jan: bool = start >= EventDates.md(1, 1) and start <= EventDates.md(1, 3)
				if EventDates.md_day(start) != last and not early_jan:
					start_hour = 12 + rng.randi_range(0, 7)
					break
				continue
			&"broker_sale":
				if start != EventDates.md(7, 4):
					start_hour = 18
					break
				continue
			&"gypsy":
				if start != EventDates.md(12, 31):
					start_hour = 21
					break
				continue
		break
	special_type = pick
	special_year = year
	special_dates["special0"] = today
	special_dates["special1"] = start
	special_dates["special2"] = EventDates.after_n_day(year, start, 0 if pick == &"shop_sale" else 1)
	special_dates["special3"] = start_hour
	return true


func _describe_special() -> String:
	if special_type == &"":
		return "-"
	var start: int = int(special_dates["special1"])
	return "%s (starts %d/%d at %d:00)" % [
		EventSchedule.label(special_type), EventDates.md_month(start), EventDates.md_day(start),
		int(special_dates["special3"]),
	]


func _join(ids: Array[StringName]) -> String:
	if ids.is_empty():
		return "-"
	var names: PackedStringArray = []
	for id: StringName in ids:
		names.append(String(id))
	return ", ".join(names)


# --- save ------------------------------------------------------------------------------


func to_save() -> Dictionary:
	return {
		"town_day": town_day,
		"town_seed": town_seed,
		"birthday": birthday_md,
		"weekly_type": String(weekly_type),
		"weekly_date": weekly_date,
		"special_type": String(special_type),
		"special_year": special_year,
		"special_dates": special_dates.duplicate(),
	}


func apply_snapshot(data: Dictionary) -> void:
	clear()
	town_day = clampi(int(data.get("town_day", 15)), 1, 28)
	town_seed = int(data.get("town_seed", 0))
	birthday_md = int(data.get("birthday", 0))
	weekly_type = StringName(String(data.get("weekly_type", "")))
	weekly_date = int(data.get("weekly_date", 0))
	special_type = StringName(String(data.get("special_type", "")))
	special_year = int(data.get("special_year", 0))
	var dates: Variant = data.get("special_dates", {})
	if typeof(dates) == TYPE_DICTIONARY:
		for slot: String in ["special0", "special1", "special2", "special3"]:
			special_dates[slot] = int((dates as Dictionary).get(slot, special_dates[slot]))
