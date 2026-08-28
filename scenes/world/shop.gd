extends Node3D

## Placeholder shop. Hours come from `Clock` (Cranny 9–22). Economy stays later.

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(2, 2)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = false
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.BUILDING
@export var open_hour: int = 9
@export var close_hour: int = 22
@export var visual_id: StringName = &"obj_s_shop1"


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)


func is_open() -> bool:
	return Clock.in_hour_window(open_hour, close_hour)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if is_open():
		return [Interaction.of(Interaction.SHOP, "Shop", 12)]
	return [Interaction.of(Interaction.SHOP, "Shop (closed)", 12)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.SHOP:
		return false
	if not is_open():
		Game.post_notice("The shop is closed.")
		return false
	Game.post_notice("The shop is open.")
	return true
