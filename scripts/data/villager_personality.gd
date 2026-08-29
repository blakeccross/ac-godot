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
## Field walk in m/s. Same for every looks (`aNPC_spd_data` walk 1.0 GX/frame).
@export var walk_speed: float = 1.5
@export var wander_radius: float = 6.0
## Field action ids (`ActivityKind`). Empty → looks defaults.
@export var field_actions: PackedStringArray = PackedStringArray()


func schedule_table() -> ScheduleData:
	return schedule


func field_activity_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry: String in field_actions:
		if entry != "":
			out.append(StringName(entry))
	if not out.is_empty():
		return out
	match looks:
		Looks.NORMAL:
			return [ActivityKind.SHOP, ActivityKind.SIT, ActivityKind.WANDER]
		Looks.PEPPY:
			return [ActivityKind.SHOP, ActivityKind.WANDER]
		Looks.LAZY:
			return [ActivityKind.WANDER, ActivityKind.SIT, ActivityKind.FISH]
		Looks.JOCK:
			return [ActivityKind.FISH, ActivityKind.WANDER]
		Looks.CRANKY:
			return [ActivityKind.SIT, ActivityKind.WANDER]
		Looks.SNOOTY:
			return [ActivityKind.SHOP, ActivityKind.SIT]
		_:
			return [ActivityKind.WANDER]
