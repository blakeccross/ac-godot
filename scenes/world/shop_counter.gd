extends StaticBody3D

## Indoor register. Buy / sell live on `ShopBook`; this node only offers the verb.

@export var shop_id: StringName = &""
@export var occupant_id: StringName = &"shop_counter"
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = false
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("shop_set")


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	return ShopUse.actions(self, ctx)


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	return ShopUse.apply(action, self, ctx)
