class_name EventPresenter
extends RefCounted

## One row of `ac_event_manager`'s `schedule_event[]`: what an active event puts in town.
## `start()` places its actors through `EventManager` (true = done, false = retry at the next
## check); `stop()` takes them away. Most presenters are one NPC scene at one spot.

var id: StringName = &""
var mgr: EventManager


func start() -> bool:
	return true


func stop() -> void:
	mgr.despawn(id)


## Called every physics frame while the event runs (festival choreography, timers).
func tick(_delta: float) -> void:
	pass
