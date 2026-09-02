extends "res://scenes/world/museum/museum_room.gd"

## Painting wing — wall art exhibits only (shell collision from base).


func present_exhibits(furniture: Node3D, session: Interior) -> void:
	MuseumPresenter.new().present_paintings(furniture, session)
