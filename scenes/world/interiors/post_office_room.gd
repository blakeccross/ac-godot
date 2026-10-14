extends "res://scenes/world/interiors/public_room.gd"

## Post office — fixtures are authored in the scene; `PostPresenter` shows the mail piles.


func present_exhibits(furniture: Node3D, interior: IndoorSession) -> void:
	PostPresenter.new().present(furniture, interior)
