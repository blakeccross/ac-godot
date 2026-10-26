class_name AxeWear
extends RefCounted

## The axe wears out (`Player_actor_GetitemNo_forDamageAxe`, `Common_Get(axe_damage)`). Each
## swing into a tree adds 1 damage, a bounce off a rock or a bank adds 3; at 9 the axe moves
## on a stage (`ITM_AXE` → `ITM_AXE_USE_1` … `_7`, the head chipped `B` then `C`), and past
## the seventh it breaks (`EMPTY_NO`, `mPlayer_INDEX_BROKEN_AXE`). The change lands on the
## swing's frame 15 (`Player_actor_ChangeItemNo_axe_common`), with `TOOL_BROKEN1` at stage 2,
## `2` at stage 5 and `3` when it breaks. The golden axe never wears; nor does the title demo.
## Damage is not saved (it lives in `Common`). Not an autoload.

const STAGES: Array[StringName] = [
	&"axe", &"axe_use_1", &"axe_use_2", &"axe_use_3", &"axe_use_4", &"axe_use_5", &"axe_use_6", &"axe_use_7",
]
const LIMIT := 9
const HIT_TREE := 1
const HIT_REFLECT := 3
## `Player_actor_Broken_axe_demo_ct`.
const MSG_BROKEN := 0x3067
const BROKEN_WINDOW := Color8(225, 165, 255)
const ANIM_BREAK := &"ply_1_axe_break1"
const ANIM_BREAK_WAIT := &"ply_1_axe_breakwait1"
## `Player_actor_MessageControl_Broken_axe`: the report waits 80 frames.
const REPORT_DELAY_FRAMES := 80.0
## `Player_actor_SetEffect_Broken_axe`: `AXE_BREAK1` frame the pieces fly off.
const PIECES_FRAME := 15.0

static var damage: int = 0


static func is_worn_axe(id: StringName) -> bool:
	return STAGES.has(id)


## The tool after this hit: the same id, the next stage, or `&""` (broken).
static func after_hit(id: StringName, reflected: bool) -> StringName:
	var stage: int = STAGES.find(id)
	if stage < 0 or Game.title_demo_active:
		return id
	damage += HIT_REFLECT if reflected else HIT_TREE
	if damage < LIMIT:
		return id
	return STAGES[stage + 1] if stage + 1 < STAGES.size() else &""


## `Player_actor_ChangeItemNo_axe_common`: put the hit's result in hand. Returns the new id
## (`&""` broken) when it changed, or the old one.
static func apply(inventory: Inventory, reflected: bool, at: Node = null) -> StringName:
	if inventory == null or not is_worn_axe(inventory.equipment_id):
		return inventory.equipment_id if inventory != null else &""
	var before: StringName = inventory.equipment_id
	var next: StringName = after_hit(before, reflected)
	if next == before:
		return before
	damage = 0
	inventory.swap_equipped(next)
	match next:
		&"axe_use_2":
			Audio.play_se(&"tool_broken1", at)
		&"axe_use_5":
			Audio.play_se(&"tool_broken2", at)
		&"":
			Audio.play_se(&"tool_broken3", at)
	return next


static func reset() -> void:
	damage = 0
