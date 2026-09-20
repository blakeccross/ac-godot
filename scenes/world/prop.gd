extends StaticBody3D

## Fixed FG prop from the disc templates: fences, sight-map and tune boards.
## Solid over its whole occupancy footprint (`obj_hight_table_item0_nogrow` raises the unit).
## Only the sight-map board has a verb: A opens the town map (`mSM_OVL_MAP`, mode 0 — the board
## shows the map whether or not the player owns one).

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE
@export var visual_id: StringName = &"obj_s_fenceS"

## `height_table` counts × 10 GX: fences 4 (2 m), boards 7 (3.5 m).
const FENCE_HEIGHT := 2.0
const BOARD_HEIGHT := 3.5
const SENSOR_HEIGHT := 1.4
const SENSOR_DEPTH := 0.8


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)
	HostCollision.apply_box(self, footprint, HostCollision.CELL, _collision_height())
	var xz: Vector2 = HostCollision.xz_size(footprint, HostCollision.CELL)
	HostCollision.resize_interact_box(self, Vector3(xz.x + 0.4, SENSOR_HEIGHT, SENSOR_DEPTH))


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)


func is_map_board() -> bool:
	return String(visual_id).ends_with("_sightmap")


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if is_map_board():
		return [Interaction.of(Interaction.READ, "Look at map", 6)]
	return []


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.READ or not is_map_board():
		return false
	var map_ui: Node = get_tree().get_first_node_in_group("map_ui")
	if map_ui == null or not map_ui.has_method("open"):
		return false
	map_ui.call("open", true)
	return true


func _collision_height() -> float:
	var id: String = String(visual_id)
	if id.contains("fence"):
		return FENCE_HEIGHT
	return BOARD_HEIGHT
