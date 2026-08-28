extends Node3D

## Door / entrance sensor. Compose under a building or place as its own world object.
## Proves new interactables are a thin scene + registry entry, not a player type switch.

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i.ONE
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = false
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE
@export var label: String = "Door"
@export var verb: StringName = &"enter"
@export var closed_notice: String = "The door is locked."


func _ready() -> void:
	add_to_group("interactable")


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	var prompt: String = "Enter %s" % label if verb == Interaction.ENTER else String(verb).capitalize()
	if verb == Interaction.SHOP:
		prompt = "Shop"
	return [Interaction.of(verb, prompt, 12)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != verb:
		return false
	if verb == Interaction.SHOP:
		if not Clock.in_hour_window(9, 22):
			Game.post_notice("The shop is closed.")
			return false
		Game.post_notice("The shop is open.")
		return true
	Game.post_notice(closed_notice)
	return true
