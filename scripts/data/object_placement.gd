class_name ObjectPlacement
extends Resource

## One outdoor object on the cell grid. Kind is resolved by WorldBuilder.

@export var id: StringName = &""
@export var kind: StringName = &"tree"
@export var cell: Vector2i = Vector2i.ZERO
@export var footprint: Vector2i = Vector2i.ONE
@export var facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var persist_id: StringName = &""
@export var message: String = ""
@export var payload: Resource
@export var visual_id: StringName = &""
