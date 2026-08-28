extends Node3D

## Ground item. Offers pick_up; pockets refuse if full (`mPr`).

@export var item: ItemData
@export var persist_id: StringName = &"ground_apple"
@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.ITEM


func _ready() -> void:
	add_to_group("interactable")
	if Game.is_interactable_removed(persist_id):
		queue_free()
		return
	if item != null:
		GeneratedVisual.apply_item_albedo(self, item.id)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if item == null:
		return []
	return [
		Interaction.of(Interaction.PICK_UP, "Pick up %s" % item.display_name, 15, &"ply_1_pickup1")
	]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.PICK_UP or item == null or ctx == null:
		return false
	if ctx.inventory == null or not ctx.inventory.has_space(1):
		Game.post_notice("Pockets full")
		return false
	if ctx.inventory.add(item, 1) != 0:
		Game.post_notice("Pockets full")
		return false
	Game.mark_interactable_removed(persist_id)
	var id: StringName = persist_id if persist_id != &"" else occupant_id
	ctx.release_occupant(id)
	Game.post_notice("Picked up %s" % item.display_name)
	queue_free()
	return true
