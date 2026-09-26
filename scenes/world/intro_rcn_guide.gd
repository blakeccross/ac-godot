class_name IntroRcnGuide
extends Node3D

## Tom Nook for the station arrival (`ac_npc_rcn_guide`, `SP_NPC_RCN_GUIDE`). The station stage
## moves him; this scene is his body, his collision (`status_data.weight = 255`, immovable)
## and the one talk the player can start themselves: `aNRG_norm_talk_request` (`0x0820`) while
## he waits for a house to be picked (`DECIDE_HOUSE_WAIT`).

const SKELETON := &"rcn_1"

## Set while `aNRG_norm_talk_request` is his talk request; empty = force-talks only.
var talk_handler: Callable = Callable()

var _pivot: Node3D

@onready var _body: StaticBody3D = $Body


func _ready() -> void:
	visibility_changed.connect(_sync_body)
	_sync_body()


## Attach the `rcn_1` mesh once. Returns the skeleton pivot (face binding).
func build() -> Node3D:
	if _pivot == null:
		_pivot = GeneratedVisual.attach_special_npc(self, SKELETON)
	return _pivot


## Not spawned yet / deleted: no body in the way (`Actor_delete`).
func _sync_body() -> void:
	_body.process_mode = Node.PROCESS_MODE_INHERIT if visible else Node.PROCESS_MODE_DISABLED


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if not visible or not talk_handler.is_valid():
		return []
	return [Interaction.of(Interaction.TALK, "Talk to Tom Nook", 20)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or not talk_handler.is_valid():
		return false
	await talk_handler.call()
	return true
