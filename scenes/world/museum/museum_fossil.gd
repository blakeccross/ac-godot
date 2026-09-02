extends "res://scenes/world/museum/museum_room.gd"

## Fossil wing — skeletons (exhibit collision comes from `MuseumPresenter`).


func present_exhibits(furniture: Node3D, session: Interior) -> void:
	MuseumPresenter.new().present_fossils(furniture, session)
