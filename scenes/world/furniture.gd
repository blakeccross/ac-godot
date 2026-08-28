extends Node3D

## Placeholder placed furniture. Offers sit; indoor push/pull comes later.

@export var data: FurnitureData
@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE
@export var visual_id: StringName = &"int_sum_chair01"


func _ready() -> void:
	add_to_group("interactable")
	if data != null and data.footprint != Vector2i.ZERO:
		footprint = data.footprint
	GeneratedVisual.attach(self, visual_id)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	var label: String = data.display_name if data else "Furniture"
	return [Interaction.of(Interaction.SIT, "Sit on %s" % label, 8)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.SIT:
		return false
	Game.post_notice("You sit down.")
	return true
