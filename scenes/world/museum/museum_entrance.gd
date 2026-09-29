extends "res://scenes/world/museum/museum_room.gd"

## Entrance hall. Blathers, the floor clock and the wing-link doors are authored nodes in
## `museum_entrance.tscn`; the stained-glass window beams follow the room grid.


func present_exhibits(furniture: Node3D, session: IndoorSession) -> void:
	MuseumPresenter.new().present_sunshine(furniture, session)
