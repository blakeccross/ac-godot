extends Node3D

## Outdoor hole FG (`HOLE00`–`HOLE24`). Fill when a shovel is equipped.

@export var occupant_id: StringName = &""
@export var persist_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.PLANT
@export var visual_id: StringName = &"HOLE00"


func _ready() -> void:
	add_to_group("interactable")
	var vis: Node3D = GeneratedVisual.attach(self, visual_id)
	var placeholder := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if placeholder != null:
		placeholder.visible = vis == null


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)
	var vis := get_node_or_null("GeneratedVisual")
	var placeholder := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if placeholder != null:
		placeholder.visible = vis == null


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	if not ToolUse.has(ctx, ToolData.Kind.SHOVEL):
		return []
	## `FILL_UP1` hole reset at frame 18 (`Player_actor_Reset_Hole_Fill_scoop`).
	return [
		Interaction.of(
			Interaction.FILL,
			"Fill hole",
			8,
			PlantGrowth.FILL_SCOOP_ANIM,
			PlantGrowth.FILL_HOLE_EFFECT_FRAME
		)
	]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.FILL:
		return false
	if not ToolUse.has(ctx, ToolData.Kind.SHOVEL):
		return false
	return HoleUse.fill(self, ctx)
