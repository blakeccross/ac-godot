extends Node3D

## Outdoor flower. Growth is derived from `Game.plant_states`; this scene presents it.

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.PLANT
@export var visual_id: StringName = &"FLOWER_PANSIES0"
@export var persist_id: StringName = &""
@export var plant: PlantData


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("plant")
	if persist_id != &"" and Game.is_interactable_removed(persist_id):
		queue_free()
		return
	if persist_id != &"" and plant != null:
		PlantGrowth.ensure(persist_id, plant, visual_id, _cell())
	apply_growth()


func refresh_seasonal_visual() -> void:
	apply_growth()


func apply_growth() -> void:
	if plant != null and persist_id != &"":
		var rec: Dictionary = PlantGrowth.record(persist_id)
		if not rec.is_empty():
			visual_id = PlantGrowth.visual_id(rec, plant)
	GeneratedVisual.detach(self)
	GeneratedVisual.attach(self, visual_id)


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	var actions: Array[Interaction] = []
	if _can_pick():
		actions.append(Interaction.of(Interaction.PICK_UP, "Pick flower", 10))
	if ToolUse.has(ctx, ToolData.Kind.WATERING_CAN) and _needs_water():
		actions.append(Interaction.of(Interaction.WATER, "Water flower", 16, &"ply_1_water1"))
	return actions


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null:
		return false
	if action.id == Interaction.WATER:
		if not ToolUse.has(ctx, ToolData.Kind.WATERING_CAN):
			return false
		if persist_id != &"":
			PlantGrowth.water(persist_id)
			apply_growth()
		Game.post_notice("You water the flower.")
		return true
	if action.id != Interaction.PICK_UP:
		return false
	if not _can_pick():
		return false
	var item: ItemData = ItemCatalog.get_item(&"flower")
	if item != null and Game.inventory != null:
		if Game.inventory.add(item, 1) != 0:
			Game.post_notice("Pockets are full.")
			return false
	Game.post_notice("Picked a flower.")
	var pid: StringName = persist_id if persist_id != &"" else occupant_id
	if pid != &"":
		PlantGrowth.clear(pid)
		Game.mark_interactable_removed(pid)
	if ctx != null:
		ctx.release_occupant(pid)
	queue_free()
	return true


func _can_pick() -> bool:
	if plant == null or persist_id == &"":
		return true
	var rec: Dictionary = PlantGrowth.record(persist_id)
	return PlantGrowth.pipeline(rec, plant) == PlantGrowth.Pipeline.HARVESTABLE


func _needs_water() -> bool:
	return plant == null or plant.needs_water


func _cell() -> Vector2i:
	var world: Node = get_tree().get_first_node_in_group("world") if get_tree() != null else null
	if world != null and "grid" in world and world.grid != null:
		return world.grid.world_to_cell(global_position)
	return Vector2i.ZERO
