class_name BugData
extends ItemData

## Catchable bug. Months are 1–12; hours use [hour_start, hour_end) in 24h.

@export var months: PackedInt32Array = PackedInt32Array()
@export var hour_start: int = 0
@export var hour_end: int = 24


func _init() -> void:
	category = Category.BUG
