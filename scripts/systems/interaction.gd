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
const BUY := &"buy"
const SELL := &"sell"
const DIG := &"dig"
const FILL := &"fill"
const CHOP := &"chop"
const WATER := &"water"
const SWING_NET := &"swing_net"
const CAST := &"cast"
const HOOK := &"hook"
const PLACE := &"place"
const ROTATE := &"rotate"
const OPEN := &"open"
const TOGGLE := &"toggle"
const LIE := &"lie"
const DISPLAY := &"display"
const TAKE := &"take"

var id: StringName = &""
var prompt: String = ""
var priority: int = 0
var locks_player: bool = true
var player_anim: StringName = &""
## Frame of `player_anim` at which the effect lands, or -1 to apply it once the clip ends.
## The original does not wait for a swing to finish: `cast_rod` hands the bobber its cast
## command on its first frame, which `ready_rod` reaches at animation frame 10, and the rest
## of the swing plays out around a line that is already in the air.
var effect_frame: float = -1.0


static func of(
	p_id: StringName,
	p_prompt: String,
	p_priority: int = 0,
	p_anim: StringName = &"",
	p_effect_frame: float = -1.0
) -> Interaction:
	var action := Interaction.new()
	action.id = p_id
	action.prompt = p_prompt
	action.priority = p_priority
	action.player_anim = p_anim
	action.effect_frame = p_effect_frame
	return action


static func primary(actions: Array[Interaction]) -> Interaction:
	var best: Interaction = null
	for action: Interaction in actions:
		if action == null or action.id == &"":
			continue
		if best == null or action.priority > best.priority:
			best = action
	return best
