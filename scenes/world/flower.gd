extends Node3D

## Outdoor flower. Growth is derived from `Game.town.plant_states`; this scene presents it.

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
			if PlantGrowth.is_grown_flower_visual(visual_id):
				PlantGrowth.ensure_grown_bloom(persist_id, visual_id)
				rec = PlantGrowth.record(persist_id)
			visual_id = PlantGrowth.visual_id(rec, plant)
	GeneratedVisual.detach(self)
	GeneratedVisual.attach(self, visual_id)


## Flowers are FG ids in the ENV range, which `Player_actor_CheckItem_fromPosition` never
## accepts: there is no picking one by hand, only digging it up with the shovel.
func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	var actions: Array[Interaction] = []
	if ToolUse.has(ctx, ToolData.Kind.SHOVEL):
		actions.append(Interaction.of(Interaction.DIG, "Dig up", 12, &"ply_1_dig1", 15.0))
	if ToolUse.has(ctx, ToolData.Kind.WATERING_CAN) and _needs_water():
		actions.append(Interaction.of(Interaction.WATER, "Water flower", 16, &"ply_1_water1"))
	return actions


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null:
		return false
	if action.id == Interaction.DIG:
		if not ToolUse.has(ctx, ToolData.Kind.SHOVEL):
			return false
		if ctx != null and ctx.actor != null:
			PlayerSe.scoop_dig(ctx.actor)
		var cell: Vector2i = _cell()
		if not PlantGrowth.dig_up_flower(ctx, cell):
			return false
		ToolUse.dig_effects(ctx, cell, true)
		return true
	if action.id == Interaction.WATER:
		if not ToolUse.has(ctx, ToolData.Kind.WATERING_CAN):
			return false
		if persist_id != &"":
			PlantGrowth.water(persist_id)
			apply_growth()
		Game.post_notice("You water the flower.")
		return true
	return false


func _needs_water() -> bool:
	return plant == null or plant.needs_water


func _cell() -> Vector2i:
	var world := World.find(get_tree())
	if world != null and "grid" in world and world.grid != null:
		return world.grid.world_to_cell(global_position)
	return Vector2i.ZERO
