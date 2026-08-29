class_name ScheduleData
extends Resource

## Daily routine. First slot whose end is still in the future wins (`mNPS_schedule_manager_sub`).

@export var slots: Array[ScheduleSlot] = []


func activity_at(hour: int) -> StringName:
	return activity_at_seconds(posmod(hour, 24) * 3600)


func activity_now() -> StringName:
	return activity_at_seconds(Clock.now_sec())


func activity_at_seconds(now_sec: int) -> StringName:
	if slots.is_empty():
		return VillagerActivity.SLEEP
	var wrapped: int = posmod(now_sec, 86400)
	for slot: ScheduleSlot in slots:
		if slot.end_seconds() > wrapped:
			return slot.activity
	return slots[slots.size() - 1].activity
