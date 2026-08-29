class_name VillagerAction
extends RefCounted

## One reusable activity step. Duration and destination are data; the actor is shared.

const ARRIVE := 0.5

var kind: StringName = ActivityKind.WANDER
var target: Vector3 = Vector3.ZERO
var duration: float = 0.0
var elapsed: float = 0.0
var arrived: bool = false


static func make(
	kind: StringName, target: Vector3 = Vector3.ZERO, duration: float = 0.0
) -> VillagerAction:
	var action := VillagerAction.new()
	action.kind = kind
	action.target = target
	action.duration = duration
	return action


func is_present() -> bool:
	return not ActivityKind.hides_actor(kind)


func is_talkable() -> bool:
	return ActivityKind.is_talkable(kind)


func wants_move() -> bool:
	return ActivityKind.wants_move(kind)


func is_wander() -> bool:
	return kind == ActivityKind.WANDER


func consider_arrive(from: Vector3) -> void:
	if not wants_move() or kind == ActivityKind.WANDER:
		return
	var to: Vector3 = target - from
	to.y = 0.0
	if to.length() <= ARRIVE:
		arrived = true


func tick_time(delta: float) -> void:
	elapsed += delta


func is_finished() -> bool:
	if ActivityKind.loops(kind):
		return false
	if duration > 0.0:
		return elapsed >= duration
	if wants_move():
		return arrived
	return elapsed > 0.0
