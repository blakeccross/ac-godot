extends StaticBody3D

## Placeholder tree. Growth stays in a plant system; this scene only exposes shake.

@export var plant: PlantData
@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.PLANT
@export var visual_id: StringName = &"TREE_APPLE_FRUIT"


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	var label: String = plant.display_name if plant else "Tree"
	return [Interaction.of(Interaction.SHAKE, "Shake %s" % label, 10, &"ply_1_shake1")]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.SHAKE:
		return false
	Game.post_notice("The tree rustles.")
	return true
