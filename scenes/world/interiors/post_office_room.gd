extends "res://scenes/world/interiors/public_room.gd"

## Post office — furnishing lives in `PostPresenter`.


func present_exhibits(furniture: Node3D, interior: Interior) -> void:
	PostPresenter.new().present(furniture, interior)
