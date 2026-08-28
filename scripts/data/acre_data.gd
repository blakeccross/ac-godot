class_name AcreData
extends Resource

## Legacy plot description used by WorldGrid tests. Playable layout is WorldData.

@export var id: StringName = &""
@export var display_name: String = ""
## World-space size of the plot (meters). Cell size is size / columns.
@export var size: Vector2 = Vector2(32, 32)
@export var columns: int = 16
@export var rows: int = 16
@export var water_cells: Array[Vector2i] = []
@export var soil_cells: Array[Vector2i] = []
@export var blocked_cells: Array[Vector2i] = []
