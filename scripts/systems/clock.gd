class_name ClockService
extends Node

## Time system (autoload `Clock`). Source of truth for calendar, day/night, and
## the 06:00 daily renew. Other systems subscribe to signals; they must not call
## `Time.get_datetime_dict_from_system()` or derive season/weekday themselves.
## Behavior from ac-decomp `m_time` / `lb_rtc` / `m_kankyo`.

enum Season { SPRING, SUMMER, AUTUMN, WINTER }
enum TimeOfDay { NIGHT, DAWN, DAY, DUSK }

const MIN_YEAR := 2001
const MAX_YEAR := 2030
## `mTM_rtcTime_default_code` is 2000-01-01 12:00; `mTM_rtcTime_limit_check` raises the year to 2001.
const DEFAULT_YEAR := 2001
const DEFAULT_MONTH := 1
const DEFAULT_DAY := 1
const DEFAULT_HOUR := 12
const DEFAULT_MINUTE := 0
const DEFAULT_SECOND := 0
## Daily field reset hour (`mTM_FIELD_RENEW_HOUR`). Growth, shops, weather, schedules.
const FIELD_RENEW_HOUR := 6

const WEEKDAYS := [
	"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
]
const MONTH_DAYS := [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const SEASON_NAMES := ["Spring", "Summer", "Autumn", "Winter"]
const TIME_OF_DAY_NAMES := ["Night", "Dawn", "Day", "Dusk"]
## Sakamoto weekday offsets; 0 = Sunday.
const _SAKAMOTO := [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]

## Inclusive end of each of 18 calendar terms (`mTM_calender` in m_time.c).
const _TERM_MONTH := [2, 2, 2, 3, 4, 5, 7, 8, 9, 9, 10, 10, 11, 11, 12, 12, 12, 12]
const _TERM_DAY := [3, 17, 24, 31, 8, 25, 22, 31, 15, 30, 15, 29, 12, 28, 9, 17, 25, 31]
const _TERM_SEASON := [
	3, 3, 3,
	0, 0, 0,
	1, 1, 1,
	2, 2, 2, 2, 2, 2,
	3, 3, 3,
]

## Lighting windows (`klight_chg_tim` in m_kankyo.c), hours.
const LIGHT_TERM_HOURS := [0, 4, 6, 8, 12, 16, 18, 20, 24]

signal time_changed
signal hour_changed(hour: int)
signal day_changed
signal season_changed(season: Season)
signal term_changed(term: int)
signal time_of_day_changed(tod: TimeOfDay)
## Days of 06:00 renew that were crossed. Plants, shops, weather subscribe here.
signal field_renewed(days: int)

var year: int = DEFAULT_YEAR
var month: int = DEFAULT_MONTH
var day: int = DEFAULT_DAY
var hour: int = DEFAULT_HOUR
var minute: int = DEFAULT_MINUTE
var second: int = DEFAULT_SECOND
## Game-seconds per real second when `rtc_override` is on. 1.0 is real-time.
var time_scale: float = 1.0
var paused: bool = false
## True after debug skip / loaded save; matches `time.rtc_crashed` (stop following hardware RTC).
var rtc_override: bool = false

var _accum: float = 0.0
var _last_stamp: String = ""
var _seeded: bool = false
var _os_follow_seeded: bool = false
var _prev_hour: int = DEFAULT_HOUR
var _prev_renew: int = 0
var _prev_day_key: String = ""
var _prev_term: int = 0
var _prev_season: Season = Season.WINTER
var _prev_tod: TimeOfDay = TimeOfDay.DAY


func _ready() -> void:
	sync_from_os()


func _process(delta: float) -> void:
	if paused:
		return
	if not rtc_override:
		sync_from_os()
		return
	if time_scale <= 0.0:
		return
	_accum += delta * time_scale
	while _accum >= 1.0:
		_accum -= 1.0
		advance_seconds(1)


func reset_to_default() -> void:
	year = DEFAULT_YEAR
	month = DEFAULT_MONTH
	day = DEFAULT_DAY
	hour = DEFAULT_HOUR
	minute = DEFAULT_MINUTE
	second = DEFAULT_SECOND
	_accum = 0.0
	rtc_override = true
	_os_follow_seeded = false
	_emit_time(false)


func sync_from_os() -> void:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	year = clampi(int(dt["year"]), MIN_YEAR, MAX_YEAR)
	month = int(dt["month"])
	day = int(dt["day"])
	hour = int(dt["hour"])
	minute = int(dt["minute"])
	second = int(dt["second"])
	var stamp := _minute_stamp()
	if stamp == _last_stamp and _seeded:
		return
	var track: bool = _os_follow_seeded
	_os_follow_seeded = true
	_emit_time(track)


func advance_minutes(amount: int) -> void:
	rtc_override = true
	_os_follow_seeded = false
	advance_seconds(amount * 60)


func advance_seconds(amount: int) -> void:
	if amount == 0:
		return
	rtc_override = true
	_os_follow_seeded = false
	var remaining: int = amount
	while remaining > 0:
		var step: int = mini(remaining, 60 - second)
		second += step
		remaining -= step
		if second >= 60:
			second = 0
			minute += 1
			if minute >= 60:
				minute = 0
				_advance_hour()
	_emit_time(true)


func now_sec() -> int:
	return hour * 3600 + minute * 60 + second


func term_idx() -> int:
	for i: int in _TERM_MONTH.size():
		if month < int(_TERM_MONTH[i]) or (month == int(_TERM_MONTH[i]) and day <= int(_TERM_DAY[i])):
			return i
	return _TERM_MONTH.size() - 1


func season() -> Season:
	return int(_TERM_SEASON[term_idx()]) as Season


func light_term() -> int:
	var sec: int = now_sec()
	for i: int in range(LIGHT_TERM_HOURS.size() - 1):
		var start: int = int(LIGHT_TERM_HOURS[i]) * 3600
		var end_s: int = int(LIGHT_TERM_HOURS[i + 1]) * 3600
		if sec >= start and sec < end_s:
			return i
	return LIGHT_TERM_HOURS.size() - 2


func time_of_day() -> TimeOfDay:
	match light_term():
		2:
			return TimeOfDay.DAWN
		3, 4, 5:
			return TimeOfDay.DAY
		6:
			return TimeOfDay.DUSK
		_:
			return TimeOfDay.NIGHT


func outdoor_light() -> Dictionary:
	## Fine-weather kcolor (`l_mEnv_kcolor_fine_data`): ambient, sun, background.
	var palettes: Array[Dictionary] = [
		{ "ambient": Color8(20, 10, 120), "sun": Color8(0, 0, 0), "bg": Color8(28, 32, 92), "energy": 0.08 },
		{ "ambient": Color8(0, 10, 120), "sun": Color8(0, 20, 40), "bg": Color8(44, 52, 112), "energy": 0.15 },
		{ "ambient": Color8(60, 60, 120), "sun": Color8(255, 255, 200), "bg": Color8(60, 76, 120), "energy": 0.55 },
		{ "ambient": Color8(80, 80, 150), "sun": Color8(180, 220, 220), "bg": Color8(56, 72, 140), "energy": 0.85 },
		{ "ambient": Color8(80, 80, 150), "sun": Color8(200, 240, 240), "bg": Color8(52, 78, 144), "energy": 1.0 },
		{ "ambient": Color8(80, 80, 150), "sun": Color8(200, 240, 240), "bg": Color8(48, 72, 140), "energy": 0.95 },
		{ "ambient": Color8(60, 60, 150), "sun": Color8(200, 120, 0), "bg": Color8(32, 32, 92), "energy": 0.4 },
		{ "ambient": Color8(30, 30, 120), "sun": Color8(60, 60, 0), "bg": Color8(28, 28, 92), "energy": 0.12 },
	]
	return palettes[light_term()]


func weekday() -> int:
	var y: int = year
	var m: int = month
	if m < 3:
		y -= 1
	return posmod(
		y + int(y / 4.0) - int(y / 100.0) + int(y / 400.0) + int(_SAKAMOTO[m - 1]) + day,
		7
	)


func weekday_name() -> String:
	return String(WEEKDAYS[weekday()])


func season_name() -> String:
	return String(SEASON_NAMES[season()])


func time_of_day_name() -> String:
	return String(TIME_OF_DAY_NAMES[time_of_day()])


func format_clock() -> String:
	return "%s %04d-%02d-%02d  %02d:%02d  %s  %s" % [
		weekday_name(), year, month, day, hour, minute, season_name(), time_of_day_name()
	]


## Snapshot other systems should read instead of storing their own clock.
func calendar() -> Dictionary:
	return {
		"year": year,
		"month": month,
		"day": day,
		"weekday": weekday(),
		"hour": hour,
		"minute": minute,
		"second": second,
		"season": season(),
		"term": term_idx(),
		"time_of_day": time_of_day(),
		"now_sec": now_sec(),
	}


## `[start_hour, end_hour)` in 24h. `end_hour` 24 means midnight. Start > end wraps past midnight.
static func hour_in_window(p_hour: int, start_hour: int, end_hour: int) -> bool:
	var h: int = posmod(p_hour, 24)
	if end_hour >= 24:
		return h >= posmod(start_hour, 24)
	if start_hour == end_hour:
		return true
	if start_hour < end_hour:
		return h >= start_hour and h < end_hour
	return h >= start_hour or h < end_hour


func in_hour_window(start_hour: int, end_hour: int) -> bool:
	return hour_in_window(hour, start_hour, end_hour)


func in_months(months: PackedInt32Array) -> bool:
	if months.is_empty():
		return true
	return month in months


## Fish / bug spawn tables ask the clock; they do not read the OS.
func is_listed_now(months: PackedInt32Array, hour_start: int, hour_end: int) -> bool:
	return in_months(months) and in_hour_window(hour_start, hour_end)


func to_dict() -> Dictionary:
	return {
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": minute,
		"second": second,
	}


func apply_snapshot(data: Dictionary) -> void:
	year = clampi(int(data.get("year", DEFAULT_YEAR)), MIN_YEAR, MAX_YEAR)
	month = int(data.get("month", DEFAULT_MONTH))
	day = int(data.get("day", DEFAULT_DAY))
	hour = int(data.get("hour", DEFAULT_HOUR))
	minute = int(data.get("minute", DEFAULT_MINUTE))
	second = int(data.get("second", DEFAULT_SECOND))
	_accum = 0.0
	rtc_override = true
	_os_follow_seeded = false
	_emit_time(false)


func _advance_hour() -> void:
	hour += 1
	if hour >= 24:
		hour = 0
		_advance_day()


func _advance_day() -> void:
	day += 1
	var dim: int = _days_in_month(year, month)
	if day > dim:
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1
			year = clampi(year, MIN_YEAR, MAX_YEAR)


func _days_in_month(y: int, m: int) -> int:
	if m == 2 and _is_leap(y):
		return 29
	return int(MONTH_DAYS[m])


func _is_leap(y: int) -> bool:
	return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)


func _day_number(y: int, m: int, d: int) -> int:
	var n: int = 0
	for yy: int in range(MIN_YEAR, y):
		n += 366 if _is_leap(yy) else 365
	for mm: int in range(1, m):
		n += _days_in_month(y, mm)
	return n + d


func _renew_id(y: int, m: int, d: int, h: int, _mi: int, _s: int) -> int:
	var day_n: int = _day_number(y, m, d)
	if h < FIELD_RENEW_HOUR:
		return day_n - 1
	return day_n


func _minute_stamp() -> String:
	return "%04d-%02d-%02d-%02d:%02d" % [year, month, day, hour, minute]


func _emit_time(track_crossings: bool) -> void:
	var new_tod: TimeOfDay = time_of_day()
	var new_term: int = term_idx()
	var new_season: Season = season()
	var new_renew: int = _renew_id(year, month, day, hour, minute, second)
	var new_day_key: String = "%04d-%02d-%02d" % [year, month, day]
	_last_stamp = _minute_stamp()

	if _seeded and track_crossings:
		if new_renew > _prev_renew:
			field_renewed.emit(new_renew - _prev_renew)
		if hour != _prev_hour:
			hour_changed.emit(hour)
		if new_day_key != _prev_day_key:
			day_changed.emit()
		if new_term != _prev_term:
			term_changed.emit(new_term)
		if int(new_season) != int(_prev_season):
			season_changed.emit(new_season)
		if int(new_tod) != int(_prev_tod):
			time_of_day_changed.emit(new_tod)

	_seeded = true
	_prev_hour = hour
	_prev_renew = new_renew
	_prev_day_key = new_day_key
	_prev_term = new_term
	_prev_season = new_season
	_prev_tod = new_tod
	time_changed.emit()
