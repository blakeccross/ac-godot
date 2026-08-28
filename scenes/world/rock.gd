extends StaticBody3D

## Outdoor rock FG item (`ROCK_A`–`ROCK_E`). Dig is a stub until scoop tools exist.

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.PLANT
@export var visual_id: StringName = &"ROCK_A"


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.DIG, "Dig rock", 8, &"ply_1_dig1")]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.DIG:
		return false
	Game.post_notice("You dig around the rock.")
	return true
