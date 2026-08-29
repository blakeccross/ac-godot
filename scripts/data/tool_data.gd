class_name ToolData
extends ItemData

## Equippable field tool. Kind selects host verbs; field_* is the empty-tile A-button.

enum Kind { NONE, SHOVEL, FISHING_ROD, NET, AXE, WATERING_CAN }
enum FieldRequire { NONE, WATER, EMPTY_GROUND }

@export var kind: Kind = Kind.NONE
@export var field_verb: StringName = &""
@export var field_prompt: String = ""
@export var field_anim: StringName = &""
@export var field_priority: int = 6
@export var field_require: FieldRequire = FieldRequire.NONE
@export var field_notice: String = ""
## Pipeline id (`tol_axe_1`). Empty when the disc has no mesh (watering can).
@export var visual_id: StringName = &""
## Player wait clip while this tool is equipped (`ply_1_kamae_wait_m1` for the net).
@export var hold_anim: StringName = &""
## Clip on the tool GLB while equipped (`kamae_main_m1`, `sao_wait1`).
@export var visual_hold_anim: StringName = &""
## Clip on the tool GLB during the player use anim (`net_swing1`, `sao_swing1`).
@export var visual_use_anim: StringName = &""


func _init() -> void:
	category = Category.TOOL
	equippable = true
	max_stack = 1
