extends "res://scenes/world/museum/museum_room.gd"

## Insect wing — case exhibits.


func present_exhibits(furniture: Node3D, session: Interior) -> void:
	MuseumPresenter.new().present_insects(furniture, session)
