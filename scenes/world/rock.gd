extends StaticBody3D

## Outdoor rock FG item (`ROCK_A`–`ROCK_E`).

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.PLANT
@export var visual_id: StringName = &"ROCK_A"


func _ready() -> void:
	GeneratedVisual.attach(self, visual_id)
