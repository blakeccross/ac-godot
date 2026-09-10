extends "res://scenes/world/interiors/public_room.gd"

## Police box — furnishing lives in `PolicePresenter`.


func present_exhibits(furniture: Node3D, interior: Interior) -> void:
	PolicePresenter.new().present(furniture, interior)
