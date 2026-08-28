class_name Interaction
extends RefCounted

## One verb an object offers. The player never infers this from the object's type.

const PICK_UP := &"pick_up"
const TALK := &"talk"
const SHAKE := &"shake"
const ENTER := &"enter"
const SIT := &"sit"
const READ := &"read"
const SHOP := &"shop"
const DIG := &"dig"

var id: StringName = &""
var prompt: String = ""
var priority: int = 0
var locks_player: bool = true
var player_anim: StringName = &""


static func of(
	p_id: StringName,
	p_prompt: String,
	p_priority: int = 0,
	p_anim: StringName = &""
) -> Interaction:
	var action := Interaction.new()
	action.id = p_id
	action.prompt = p_prompt
	action.priority = p_priority
	action.player_anim = p_anim
	return action


static func primary(actions: Array[Interaction]) -> Interaction:
	var best: Interaction = null
	for action: Interaction in actions:
		if action == null or action.id == &"":
			continue
		if best == null or action.priority > best.priority:
			best = action
	return best
