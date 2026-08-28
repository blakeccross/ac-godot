class_name BugData
extends ItemData

## Catchable bug. Months are 1–12; hours use [hour_start, hour_end) in 24h.

@export var months: PackedInt32Array = PackedInt32Array()
@export var hour_start: int = 0
@export var hour_end: int = 24


func _init() -> void:
	category = Category.BUG


func is_available(p_month: int, p_hour: int) -> bool:
	if not months.is_empty() and not (p_month in months):
		return false
	return ClockService.hour_in_window(p_hour, hour_start, hour_end)


func is_available_now() -> bool:
	return Clock.is_listed_now(months, hour_start, hour_end)
