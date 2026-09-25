class_name ToolData
extends ItemData

## Equippable field tool. Kind selects host verbs; field_* is the empty-tile A-button.

enum Kind { NONE, SHOVEL, FISHING_ROD, NET, AXE, WATERING_CAN, UMBRELLA }
enum FieldRequire { NONE, WATER, EMPTY_GROUND }
## `mPlayer_PART_TABLE_*` for the carry clip: which joints it drives (`ToolCarry`).
enum CarryPart { NONE, AXE, NET }

@export var kind: Kind = Kind.NONE
@export var field_verb: StringName = &""
@export var field_prompt: String = ""
@export var field_anim: StringName = &""
@export var field_priority: int = 6
@export var field_require: FieldRequire = FieldRequire.NONE
@export var field_notice: String = ""
## Pipeline id (`tol_axe_1`). Empty when the disc has no mesh (watering can).
@export var visual_id: StringName = &""
## Carry clip (`mPlib_Get_BasicPlayerAnimeIndex_fromItemKind`: `ply_1_axe1`, `ply_1_net1`, …),
## layered over the body's wait / walk / run on the `carry_part` joints (`ToolCarry`).
@export var hold_anim: StringName = &""
@export var carry_part: CarryPart = CarryPart.NONE
## Clip on the tool GLB while equipped (`kamae_main_m1`, `sao_wait1`).
@export var visual_hold_anim: StringName = &""
## Clip on the tool GLB during the player use anim (`net_swing1`, `sao_swing1`).
@export var visual_use_anim: StringName = &""
## Umbrellas (`ITM_UMBRELLA00`…): `tool_name` index into `ac_t_umbrella`'s `draw_dt` (0-31).
@export var umbrella_index: int = -1


func _init() -> void:
	category = Category.TOOL
	equippable = true
	max_stack = 1
