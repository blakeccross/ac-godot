extends StaticBody3D

## Readable field sign.

@export var message: String = "Welcome to the acre."
@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE
@export var visual_id: StringName = &"SIGNBOARD"


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)
	HostCollision.apply_box(self, footprint, HostCollision.CELL, 1.4)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.READ, "Read sign", 6)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.READ:
		return false
	Game.post_notice(message)
	return true
