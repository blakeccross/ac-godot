extends "res://scenes/world/museum/museum_room.gd"

## Fish wing — tanks + swimming exhibits (tank collision from presenter).


func present_exhibits(furniture: Node3D, session: Interior) -> void:
	MuseumPresenter.new().present_fish(furniture, session)
