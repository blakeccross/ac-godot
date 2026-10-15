class_name InteractionVerb
extends Resource

## One fixed verb a host offers, authored on its `InteractVolume` in the scene. It is on
## offer whenever the player holds `tool` (or always, with `any_tool`); a host whose verbs
## depend on more than that supplies them in code instead (`InteractVolume`).

@export var id: StringName = &""
@export var prompt: String = ""
@export var priority: int = 0
## The player's clip for the action and the frame its effect lands on (-1: when it ends).
@export var player_anim: StringName = &""
@export var effect_frame: float = -1.0
## Offered whatever the player holds.
@export var any_tool: bool = true
## Otherwise, only with this tool out.
@export var tool: ToolData.Kind = ToolData.Kind.NONE


func applies(ctx: InteractionContext) -> bool:
	return any_tool or ToolUse.has(ctx, tool)


func to_interaction() -> Interaction:
	return Interaction.of(id, prompt, priority, player_anim, effect_frame)
