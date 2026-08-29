extends Node3D

## Outdoor flower FG item. Pick adds a placeholder flower item when catalog has one.

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.PLANT
@export var visual_id: StringName = &"FLOWER_PANSIES0"
@export var persist_id: StringName = &""


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	var actions: Array[Interaction] = [
		Interaction.of(Interaction.PICK_UP, "Pick flower", 10)
	]
	if ToolUse.has(ctx, ToolData.Kind.WATERING_CAN):
		actions.append(Interaction.of(Interaction.WATER, "Water flower", 16, &"ply_1_water1"))
	return actions


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null:
		return false
	if action.id == Interaction.WATER:
		if not ToolUse.has(ctx, ToolData.Kind.WATERING_CAN):
			return false
		Game.post_notice("You water the flower.")
		return true
	if action.id != Interaction.PICK_UP:
		return false
	var item: ItemData = ItemCatalog.get_item(&"flower")
	if item != null and Game.inventory != null:
		if not Game.inventory.add(item, 1):
			Game.post_notice("Pockets are full.")
			return false
	Game.post_notice("Picked a flower.")
	var pid: StringName = persist_id if persist_id != &"" else occupant_id
	if pid != &"":
		Game.mark_interactable_removed(pid)
	if ctx != null:
		ctx.release_occupant(pid)
	queue_free()
	return true
