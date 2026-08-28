class_name PlantData
extends Resource

## Growing plant (tree, flower, bush). Not a pocket item.

@export var id: StringName = &""
@export var display_name: String = ""
@export var fruit: ItemData
@export var stage_days: PackedInt32Array = PackedInt32Array([1, 2, 3, 4])
