class_name ScheduleSlot
extends Resource

## One window that lasts until `end_hour` (24h, 19.5 = 19:30).
## Activities match `mNPS_SCHED_*`: sleep, in_house, field.

@export var end_hour: float = 24.0
@export var activity: StringName = &"sleep"


func end_seconds() -> int:
	var whole: int = int(end_hour)
	var mins: int = int(round((end_hour - float(whole)) * 60.0))
	return whole * 3600 + mins * 60
