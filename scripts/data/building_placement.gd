class_name BuildingPlacement
extends Resource

## One building on the cell grid. Kind is resolved by WorldBuilder.

@export var id: StringName = &""
@export var kind: StringName = &"house"
@export var cell: Vector2i = Vector2i.ZERO
@export var footprint: Vector2i = Vector2i(2, 2)
@export var facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var visual_id: StringName = &""
