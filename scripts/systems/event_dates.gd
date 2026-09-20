class_name EventDates
extends RefCounted

## Pure calendar math for the event scheduler (`m_event.c` helpers + `lb_reki.c`).
## Weekdays are 0 = Sunday like `Clock.weekday()`. `md` is `(month << 8) | day`.

## `lbRk_HarvestMoonDay`: lunisolar 8/15, converted from the disc's 8th-month start dates.
const HARVEST_MOON: Dictionary = {
	2001: Vector2i(10, 1), 2002: Vector2i(9, 21), 2003: Vector2i(9, 11), 2004: Vector2i(9, 28),
	2005: Vector2i(9, 18), 2006: Vector2i(10, 6), 2007: Vector2i(9, 25), 2008: Vector2i(9, 14),
	2009: Vector2i(10, 3), 2010: Vector2i(9, 22), 2011: Vector2i(9, 12), 2012: Vector2i(9, 30),
	2013: Vector2i(9, 19), 2014: Vector2i(9, 8), 2015: Vector2i(9, 27), 2016: Vector2i(9, 15),
	2017: Vector2i(10, 4), 2018: Vector2i(9, 24), 2019: Vector2i(9, 13), 2020: Vector2i(10, 1),
	2021: Vector2i(9, 21), 2022: Vector2i(9, 10), 2023: Vector2i(9, 29), 2024: Vector2i(9, 17),
	2025: Vector2i(10, 6), 2026: Vector2i(9, 25), 2027: Vector2i(9, 15), 2028: Vector2i(10, 3),
	2029: Vector2i(9, 22), 2030: Vector2i(9, 12),
}

const MONTH_DAYS := [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]


static func md(month: int, day: int) -> int:
	return (month << 8) | day


static func md_month(value: int) -> int:
	return (value >> 8) & 0xFF


static func md_day(value: int) -> int:
	return value & 0xFF


static func is_leap(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


static func days_in_month(year: int, month: int) -> int:
	if month == 2 and is_leap(year):
		return 29
	return int(MONTH_DAYS[clampi(month, 1, 12)])


## Days since 0001-01-01 (proleptic Gregorian). Monotonic, so hour math can add `* 24`.
static func ordinal(year: int, month: int, day: int) -> int:
	var y: int = year - 1
	var n: int = y * 365 + floori(y / 4.0) - floori(y / 100.0) + floori(y / 400.0)
	for m: int in range(1, month):
		n += days_in_month(year, m)
	return n + day


static func from_ordinal(n: int) -> Vector3i:
	var year: int = maxi(1, int(float(n) / 365.2425))
	while ordinal(year, 1, 1) > n:
		year -= 1
	while ordinal(year + 1, 1, 1) <= n:
		year += 1
	var rest: int = n - ordinal(year, 1, 1) + 1
	var month: int = 1
	while rest > days_in_month(year, month):
		rest -= days_in_month(year, month)
		month += 1
	return Vector3i(year, month, rest)


## 0 = Sunday. Ordinal 1 (0001-01-01) is a Monday.
static func weekday(year: int, month: int, day: int) -> int:
	return posmod(ordinal(year, month, day), 7)


## `after_n_day`: `n` days from a year-less month/day (wraps December → January).
static func after_n_day(year: int, month_day: int, n: int) -> int:
	var base: int = ordinal(year, md_month(month_day), md_day(month_day)) + n
	var d: Vector3i = from_ordinal(base)
	## Year-less: a wrap into the next/previous year keeps only month and day.
	return md(d.y, d.z)


## `check_date_range`: inclusive, and a reversed range wraps over New Year.
static func in_range(date: int, lower: int, upper: int) -> bool:
	if lower > upper:
		return lower <= date or date <= upper
	return lower <= date and date <= upper


## Nth (1..5) `weekday` of `month`.
static func nth_weekday_day(year: int, month: int, nth: int, wd: int) -> int:
	var first: int = weekday(year, month, 1)
	if wd >= first:
		return 1 + (nth - 1) * 7 + (wd - first)
	return 1 + nth * 7 + (wd - first)


static func last_weekday_day(year: int, month: int, wd: int) -> int:
	var last: int = days_in_month(year, month)
	var last_wd: int = weekday(year, month, last)
	return last - posmod(last_wd - wd, 7)


## `lbRk_VernalEquinoxDay` (1980–2099 approximation the game uses).
static func vernal_equinox_day(year: int) -> int:
	var y: int = year - 1980
	return int(20.8431 + 0.242194 * float(y)) - floori(y / 4.0)


## `lbRk_AutumnalEquinoxDay`.
static func autumnal_equinox_day(year: int) -> int:
	var y: int = year - 1980
	return int(23.2488 + 0.242194 * float(y)) - floori(y / 4.0)


static func harvest_moon(year: int) -> Vector2i:
	if HARVEST_MOON.has(year):
		return HARVEST_MOON[year] as Vector2i
	return Vector2i(9, 25)
