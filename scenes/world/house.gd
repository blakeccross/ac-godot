extends StaticBody3D

## Outdoor house shell. Villager homes use `obj_s_house1` (`ac_house`);
## the player house placement sets `obj_s_myhome1` (`ac_my_house`).

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(2, 2)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.BUILDING
@export var visual_id: StringName = &"obj_s_house1"


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)
	HostCollision.apply_house(self, visual_id, footprint, HostCollision.CELL)


func apply_grid_yaw(facing: WorldGrid.Facing) -> void:
	rotation.y = WorldGrid.yaw_for_facing(facing)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.ENTER, "Enter house", 12)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.ENTER:
		return false
	if occupant_id != &"":
		if Game.try_enter_interior(occupant_id):
			return true
		if InteriorCatalog.resolve_entry(occupant_id) != &"":
			return false
	Game.post_notice("The door is locked.")
	return true
