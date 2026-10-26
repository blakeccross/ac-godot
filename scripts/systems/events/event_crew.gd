class_name EventCrew
extends Node

## State that one event's participants share, the way an `*_control` actor does in the decomp
## (`ac_tokyoso_control`, `ac_tunahiki_control`, `ac_hatumode_control`): the race, the rope,
## the queue. Each participant `gather`s it under their common parent and `leave`s it; the last
## to leave frees it, so it lives exactly as long as the event's crowd.

var _members: int = 0


## The crew called `crew_name` under `host`, made by `make` on first use. Pair with `leave`.
static func gather(host: Node, crew_name: StringName, make: Callable) -> EventCrew:
	var crew := host.get_node_or_null(NodePath(String(crew_name))) as EventCrew
	if crew == null:
		crew = make.call() as EventCrew
		crew.name = crew_name
		host.add_child(crew)
	crew._members += 1
	return crew


## Participants still in it.
func members() -> int:
	return _members


func leave() -> void:
	_members -= 1
	if _members <= 0:
		queue_free()
