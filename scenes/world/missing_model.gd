class_name MissingModel
extends Node3D

## The one stand-in for a visual that has no generated model (`GeneratedVisual.mark_missing`).
## A box so the thing is still there to see, collide with and interact with; the real model
## replaces it once the pipeline has produced one.

const DEFAULT_TINT := Color(0.85, 0.2, 0.75, 1.0)

## Box extents in metres.
@export var size: Vector3 = Vector3(0.5, 0.5, 0.5):
	set(value):
		size = value
		_apply()
## Albedo; an alpha below 1 draws it translucent.
@export var tint: Color = DEFAULT_TINT:
	set(value):
		tint = value
		_apply()
## Rest the box's bottom on the origin. Off centres it there (balls, orbs).
@export var grounded: bool = true:
	set(value):
		grounded = value
		_apply()

@onready var _box: MeshInstance3D = $Box


func _ready() -> void:
	_apply()


func _apply() -> void:
	if _box == null:
		return
	(_box.mesh as BoxMesh).size = size
	_box.position.y = size.y * 0.5 if grounded else 0.0
	var material := _box.material_override as StandardMaterial3D
	material.albedo_color = tint
	material.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA if tint.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	)
