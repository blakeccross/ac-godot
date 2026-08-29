class_name VillagerAI
extends RefCounted

## Runs a queue of reusable activities. Schedule type still comes from looks tables.
## Talk is an interrupt: it holds the current step until `end_talk`, then resumes
## (or `sync` rebuilds if the clock slot changed while they were talking).

signal action_changed(kind: StringName)

var schedule_type: StringName = &""
var previous_type: StringName = &""
var current: VillagerAction
var _queue: Array[VillagerAction] = []
var _held: VillagerAction


func sync(schedule_type_now: StringName, hints: Dictionary) -> void:
	if is_talking():
		return
	if schedule_type_now == schedule_type and current != null:
		return
	previous_type = schedule_type
	schedule_type = schedule_type_now
	var queue: Array[VillagerAction] = VillagerPlan.build(schedule_type, previous_type, hints)
	_load(queue)


func begin_talk() -> void:
	if is_talking():
		return
	_held = current
	current = VillagerAction.make(ActivityKind.TALK)
	action_changed.emit(ActivityKind.TALK)


func end_talk() -> void:
	if not is_talking():
		return
	current = _held
	_held = null
	action_changed.emit(current.kind if current != null else &"")


func is_talking() -> bool:
	return current != null and current.kind == ActivityKind.TALK


func kind() -> StringName:
	if current == null:
		return &""
	return current.kind


func is_present() -> bool:
	if current != null:
		return current.is_present()
	return VillagerActivity.is_present(schedule_type)


func is_talkable() -> bool:
	if current != null:
		return current.is_talkable()
	return VillagerActivity.is_talkable(schedule_type)


func wants_move() -> bool:
	return current != null and current.wants_move()


func is_wandering() -> bool:
	return current != null and current.is_wander()


func destination() -> Vector3:
	if current == null:
		return Vector3.ZERO
	return current.target


func consider_arrive(from: Vector3) -> void:
	if current != null:
		current.consider_arrive(from)


func step(delta: float) -> void:
	if current == null:
		return
	current.tick_time(delta)
	if current.is_finished():
		_advance()


func _load(queue: Array[VillagerAction]) -> void:
	_queue = queue
	_advance()


func _advance() -> void:
	if _queue.is_empty():
		current = null
		action_changed.emit(&"")
		return
	current = _queue.pop_front()
	action_changed.emit(current.kind)
