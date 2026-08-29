class_name VillagerPersonality
extends Resource

## Looks group (`mNpc_LOOKS_*`). Selects a daily table; villagers do not get custom AI.

enum Looks { NORMAL, PEPPY, LAZY, JOCK, CRANKY, SNOOTY }

@export var id: StringName = &""
@export var display_name: String = ""
@export var looks: Looks = Looks.LAZY
## Daily `{type, end_time}` table for this looks group.
@export var schedule: ScheduleData
@export var placeholder_color: Color = Color(0.85, 0.55, 0.4, 1)
## Yard walk speed in m/s. Not a C actor overlay speed.
@export var walk_speed: float = 1.6
@export var wander_radius: float = 6.0


func schedule_table() -> ScheduleData:
	return schedule
