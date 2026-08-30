class_name FurnitureData
extends ItemData

## Placeable furniture. Footprint is in tile units (`mRmTp_FTRSIZE_*`).

@export var footprint: Vector2i = Vector2i(1, 1)
@export var indoor: bool = true
@export var can_sit: bool = false
@export var can_store: bool = false
@export var blocks_walk: bool = true
@export var visual_id: StringName = &""
@export var storage_slots: int = 0


func _init() -> void:
	category = Category.FURNITURE
