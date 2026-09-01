extends Node3D

## FG waterfall (`obj_fallS` / `obj_fallSE`). Visual-only; sits on the river cliff sheet.

@export var visual_id: StringName = &"obj_fallS"


func _ready() -> void:
	GeneratedVisual.attach(self, visual_id)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)
