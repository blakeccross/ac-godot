class_name FurnitureData
extends ItemData

## Placeable furniture. Footprint is in tile units.

@export var footprint: Vector2i = Vector2i(1, 1)
@export var indoor: bool = true


func _init() -> void:
	category = Category.FURNITURE
