extends Node3D

## Placeholder shop. Offers shop; economy stays in a system when that slice is earned.

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(2, 2)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = false
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.BUILDING


func _ready() -> void:
	add_to_group("interactable")


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.SHOP, "Shop", 12)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.SHOP:
		return false
	Game.post_notice("The shop is closed.")
	return true
