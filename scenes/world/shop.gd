extends StaticBody3D

## Nook shop outdoor. Visual and hours follow `ShopBook` upgrade level.

@export var occupant_id: StringName = &"acre_shop"
@export var footprint: Vector2i = Vector2i(2, 2)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = false
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.BUILDING
@export var open_hour: int = 9
@export var close_hour: int = 22
@export var visual_id: StringName = &"obj_s_shop1"


func _ready() -> void:
	add_to_group("interactable")
	_sync_from_shop_book()
	GeneratedVisual.attach(self, visual_id)
	HostCollision.apply_shop(self, footprint, HostCollision.CELL)


func _sync_from_shop_book() -> void:
	if Game == null or Game.shops == null:
		return
	visual_id = Game.shops.nook_visual_id()
	open_hour = Game.shops.nook_open_hour()
	close_hour = Game.shops.nook_close_hour()


func is_open() -> bool:
	return Clock.in_hour_window(open_hour, close_hour)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if is_open():
		return [Interaction.of(Interaction.SHOP, "Shop", 12)]
	return [Interaction.of(Interaction.SHOP, "Shop (closed)", 12)]


func refresh_seasonal_visual() -> void:
	_sync_from_shop_book()
	GeneratedVisual.refresh(self, visual_id)


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.SHOP:
		return false
	if not is_open():
		Game.post_notice("The shop is closed.")
		return false
	if occupant_id != &"":
		await StructureDoor.play_enter(self)
		if Game.try_enter_interior(occupant_id):
			return true
	Game.post_notice("The shop is open.")
	return true
