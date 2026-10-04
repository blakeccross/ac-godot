class_name Rainbow
extends RefCounted

## The waterfall rainbow (`m_kankyo.c` `mEnv_rainbow_power_calc`, drawn by `ac_fallS` /
## `ac_fallSESW` as `obj_fall*_rainbowT_model`). A day that turns fine after rain or snow
## reserves one (`mEnv_PreRainNowFine_Init`); on that date, in summer, from 9:00 to 15:00
## it fades in over 1800 frames. Outside that it fades out over 108000 frames (30 min).
## Owned by `Game`; only the reservation is saved, like `Save_Get(rainbow_reserved)`.

const TIME_START := 9 * 3600
const TIME_END := 15 * 3600
const FADE_IN := 1.0 / 1800.0
const FADE_OUT := 1.0 / 108000.0

var reserved: bool = false
var month: int = 0
var day: int = 0
## `Common_Get(rainbow_opacity)`, 0-1.
var opacity: float = 0.0


## `mEnv_Rainbow_reserve`.
func reserve(on_month: int, on_day: int) -> void:
	reserved = true
	month = on_month
	day = on_day


## `mEnv_PreRainNowFine_Init`'s test: the day's weather is fine after rain or snow.
static func pre_rain_now_fine(previous: StringName, now: StringName) -> bool:
	var was_wet: bool = previous == &"rain" or previous == &"snow"
	var is_fine: bool = now == &"clear" or now == &"sakura"
	return was_wet and is_fine


## Called when the day's weather is decided: fine after rain or snow reserves today.
func note_weather_change(previous: StringName, now: StringName, on_month: int, on_day: int) -> void:
	if pre_rain_now_fine(previous, now):
		reserve(on_month, on_day)


## One frame of `mEnv_rainbow_power_calc` (field scenes only; the caller checks).
func tick(on_month: int, on_day: int, now_sec: int, summer: bool) -> void:
	if reserved and on_month == month and on_day == day and now_sec >= TIME_START and now_sec < TIME_END and summer:
		## `chase_f` lands exactly on the target and reports it.
		opacity = minf(1.0, opacity + FADE_IN)
		if opacity >= 1.0 - 0.000001:
			opacity = 1.0
			reserved = false
	else:
		opacity = maxf(0.0, opacity - FADE_OUT)


func to_save() -> Dictionary:
	return {"reserved": reserved, "month": month, "day": day}


func apply_snapshot(data: Variant) -> void:
	reserved = false
	opacity = 0.0
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	reserved = bool(d.get("reserved", false))
	month = int(d.get("month", 0))
	day = int(d.get("day", 0))
