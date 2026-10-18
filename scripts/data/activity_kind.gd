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
## Brief visible hold at the door after `GO_HOME` arrives, before hiding —
## `aNPC_act_into_house`'s `STEP_INTO`/`OPEN_DOOR` beat. Without it the actor
## pops out of view mid-stride instead of settling at the door first.
const AT_DOOR := &"at_door"

const ALL: Array[StringName] = [
	WAKE, LEAVE_HOME, WALK_TO, WANDER, SIT, FISH, SHOP, TALK, GO_HOME, SLEEP, AT_DOOR
]

const SIT_SECONDS := 8.0
const FISH_SECONDS := 12.0
const SHOP_SECONDS := 10.0
const TALK_SECONDS := 6.0
## Linger in the goal acre, then pick a new walk goal. Not wander duration —
## `aNPC_THINK_WANDER` keeps running for the whole FIELD window.
const STAY_SECONDS := 28.0
const AT_DOOR_SECONDS := 0.4
## `home` is the yard unit's centre, `house_position + (20, 60)` GX. The leave-house walk
## starts on the door threshold, `house + (20, 40)`, one metre back toward the house, and
## ends at `house + (20, 80)`, one metre out (`aNPC_think_leave_house_init_proc`). Offsets
## are for a house facing south; the brain turns them toward the house's real front.
const YARD_OFFSET := Vector3(0.0, 0.0, 1.0)
const DOOR_THRESHOLD := Vector3(0.0, 0.0, -1.0)
## Go-home stand is the yard centre itself (`house + (20, 60)` GX).
const DOOR_APPROACH := Vector3.ZERO


static func is_known(kind: StringName) -> bool:
	return kind in ALL


static func hides_actor(kind: StringName) -> bool:
	return kind == SLEEP or kind == WAKE


static func is_talkable(kind: StringName) -> bool:
	## `aNPC_COND_DEMO_SKIP_TALK_CHECK` while walking out of the door.
	return not hides_actor(kind) and kind != LEAVE_HOME


## `demo_flg` skips head-look, talk and items while walking in or out of the door.
static func is_door_demo(kind: StringName) -> bool:
	return kind == LEAVE_HOME or kind == AT_DOOR


static func wants_move(kind: StringName) -> bool:
	return kind == WALK_TO or kind == WANDER or kind == GO_HOME or kind == LEAVE_HOME


static func loops(kind: StringName) -> bool:
	return kind == SLEEP or kind == WAKE or kind == WANDER or kind == TALK
