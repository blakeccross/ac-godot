class_name ActivityKind
extends RefCounted

## Reusable villager actions. Not `mNPS_SCHED_*` (those stay on VillagerActivity).

const WAKE := &"wake"
const LEAVE_HOME := &"leave_home"
const WALK_TO := &"walk_to"
const WANDER := &"wander"
const SIT := &"sit"
const FISH := &"fish"
const SHOP := &"shop"
const TALK := &"talk"
const GO_HOME := &"go_home"
const SLEEP := &"sleep"

const ALL: Array[StringName] = [
	WAKE, LEAVE_HOME, WALK_TO, WANDER, SIT, FISH, SHOP, TALK, GO_HOME, SLEEP
]

const SIT_SECONDS := 8.0
const FISH_SECONDS := 12.0
const SHOP_SECONDS := 10.0
const TALK_SECONDS := 6.0
const YARD_OFFSET := Vector3(0.0, 0.0, 2.2)


static func is_known(kind: StringName) -> bool:
	return kind in ALL


static func hides_actor(kind: StringName) -> bool:
	return kind == SLEEP or kind == WAKE


static func is_talkable(kind: StringName) -> bool:
	return not hides_actor(kind)


static func wants_move(kind: StringName) -> bool:
	return kind == WALK_TO or kind == WANDER or kind == GO_HOME or kind == LEAVE_HOME


static func loops(kind: StringName) -> bool:
	return kind == WANDER or kind == SLEEP or kind == WAKE
