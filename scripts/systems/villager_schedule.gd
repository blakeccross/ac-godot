class_name VillagerSchedule
extends RefCounted

## Runtime schedule slot (`mNPS_schedule_c`). Table comes from looks data.

signal activity_changed(activity: StringName)

var table: ScheduleData
var current: StringName = VillagerActivity.FIELD
var saved: StringName = VillagerActivity.FIELD
var forced: StringName = &""


func bind(p_table: ScheduleData) -> void:
	table = p_table
	forced = &""
	current = VillagerActivity.FIELD
	saved = VillagerActivity.FIELD


func force(activity: StringName) -> void:
	forced = activity
	_publish()


func clear_force() -> void:
	forced = &""
	_publish()


func tick(now_sec: int) -> StringName:
	if table == null:
		saved = VillagerActivity.FIELD
	else:
		saved = table.activity_at_seconds(now_sec)
	_publish()
	return current


func _publish() -> void:
	var next: StringName = forced if forced != &"" else saved
	if next == current:
		return
	current = next
	activity_changed.emit(current)
