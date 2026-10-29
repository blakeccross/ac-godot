extends "res://features/museum/museum_room.gd"

## Painting wing — wall art exhibits. Its partitions are BG units (`InteriorShellBuilder`).


func present_exhibits(furniture: Node3D, session: IndoorSession) -> void:
	MuseumPresenter.new().present_paintings(furniture, session)
