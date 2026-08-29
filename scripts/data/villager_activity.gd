class_name VillagerActivity
extends RefCounted

## Daily schedule types (`mNPS_SCHED_*`). Looked up from data; not per-villager scripts.

const FIELD := &"field"
const IN_HOUSE := &"in_house"
const SLEEP := &"sleep"
const STAND := &"stand"
const WANDER := &"wander"
const WALK_WANDER := &"walk_wander"

const ALL: Array[StringName] = [FIELD, IN_HOUSE, SLEEP, STAND, WANDER, WALK_WANDER]


static func is_known(activity: StringName) -> bool:
	return activity in ALL


## Outdoor actor is spawned / visible.
static func is_present(activity: StringName) -> bool:
	return not hides_actor(activity)


## Asleep or indoors — the field actor is not on the acre.
static func hides_actor(activity: StringName) -> bool:
	return activity == SLEEP or activity == IN_HOUSE


static func is_talkable(activity: StringName) -> bool:
	return is_present(activity)


## Outdoor actor is on the field. FIELD / WANDER / WALK_WANDER roam goal acres.
static func is_wandering(activity: StringName) -> bool:
	return activity == FIELD or activity == WANDER or activity == WALK_WANDER
