class_name ClockService
extends Node

## Game calendar and clock. Behavior from ac-decomp `m_time` / `lb_rtc` / `m_kankyo`.
## Real-time clock unless debug skip (`rtc_override`). Years clamp to 2001–2030.

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
## Daily field reset hour (`mTM_FIELD_RENEW_HOUR`).
const FIELD_RENEW_HOUR := 6

const WEEKDAYS := [
	"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
]
const MONTH_DAYS := [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const SEASON_NAMES := ["Spring", "Summer", "Autumn", "Winter"]
const TIME_OF_DAY_NAMES := ["Night", "Dawn", "Day", "Dusk"]

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
var _last_term: int = -1
var _last_stamp: String = ""


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
	_emit_time()


func sync_from_os() -> void:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	year = clampi(int(dt["year"]), MIN_YEAR, MAX_YEAR)
	month = int(dt["month"])
	day = int(dt["day"])
	hour = int(dt["hour"])
	minute = int(dt["minute"])
	second = int(dt["second"])
	var stamp := "%04d-%02d-%02d-%02d:%02d" % [year, month, day, hour, minute]
	if stamp != _last_stamp:
		_last_stamp = stamp
		_emit_time()


func advance_minutes(amount: int) -> void:
	rtc_override = true
	advance_seconds(amount * 60)


func advance_seconds(amount: int) -> void:
	if amount == 0:
		return
	rtc_override = true
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
	_emit_time()


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
	var unix: int = Time.get_unix_time_from_datetime_dict(_datetime_dict())
	return int(Time.get_date_dict_from_unix_time(unix)["weekday"])


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
	_emit_time()


func _advance_hour() -> void:
	hour += 1
	if hour >= 24:
		hour = 0
		_advance_day()
	hour_changed.emit(hour)


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
	day_changed.emit()


func _days_in_month(y: int, m: int) -> int:
	if m == 2 and _is_leap(y):
		return 29
	return int(MONTH_DAYS[m])


func _is_leap(y: int) -> bool:
	return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)


func _datetime_dict() -> Dictionary:
	return {
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": minute,
		"second": second,
	}


func _emit_time() -> void:
	_last_stamp = "%04d-%02d-%02d-%02d:%02d" % [year, month, day, hour, minute]
	var term: int = term_idx()
	if _last_term != -1 and int(_TERM_SEASON[term]) != int(_TERM_SEASON[_last_term]):
		season_changed.emit(season())
	_last_term = term
	time_changed.emit()
