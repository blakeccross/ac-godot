extends StaticBody3D

## Outdoor rock FG item (`ROCK_A`–`ROCK_E`). Dig requires an equipped shovel.

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.PLANT
@export var visual_id: StringName = &"ROCK_A"


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)
	HostCollision.apply_rock(self, footprint, HostCollision.CELL)


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	if not ToolUse.has(ctx, ToolData.Kind.SHOVEL):
		return []
	return [Interaction.of(Interaction.DIG, "Dig rock", 8, &"ply_1_dig1")]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.DIG:
		return false
	if not ToolUse.has(ctx, ToolData.Kind.SHOVEL):
		return false
	Game.post_notice("You dig around the rock.")
	return true
