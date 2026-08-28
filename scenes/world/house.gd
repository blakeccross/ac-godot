extends StaticBody3D

## Placeholder house shell. Door offers enter; indoor scenes come later.

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(2, 2)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.BUILDING
@export var visual_id: StringName = &"obj_s_house1"


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.ENTER, "Enter house", 12)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.ENTER:
		return false
	Game.post_notice("The door is locked.")
	return true
