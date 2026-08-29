class_name DialogueData
extends Resource

## One conversation. A UI scene plays `lines`; this resource does not run dialogue.

@export var id: StringName = &""
@export var speaker_id: StringName = &""
@export var lines: PackedStringArray = PackedStringArray()
## Repeat greeting after a talk the same calendar day.
@export var already_talked: String = ""
@export var night: String = ""
@export var dawn: String = ""
@export var day: String = ""
@export var dusk: String = ""


func line_for_time(tod: ClockService.TimeOfDay) -> String:
	match tod:
		ClockService.TimeOfDay.NIGHT:
			return night
		ClockService.TimeOfDay.DAWN:
			return dawn
		ClockService.TimeOfDay.DAY:
			return day
		ClockService.TimeOfDay.DUSK:
			return dusk
		_:
			return ""
