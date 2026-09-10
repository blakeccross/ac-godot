extends "res://scenes/world/interiors/public_room.gd"

## Nook shop — furnishing lives in `ShopPresenter`.


func present_exhibits(furniture: Node3D, interior: Interior) -> void:
	ShopPresenter.new().present(furniture, interior)
