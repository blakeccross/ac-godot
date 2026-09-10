extends "res://scenes/world/interiors/public_room.gd"

## Able Sisters — furnishing lives in `NeedleworkPresenter`.


func present_exhibits(furniture: Node3D, interior: Interior) -> void:
	NeedleworkPresenter.new().present(furniture, interior)
