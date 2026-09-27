extends "res://scenes/world/museum/museum_room.gd"

## Insect wing — case exhibits and the two window beams.


func present_exhibits(furniture: Node3D, session: IndoorSession) -> void:
	var presenter := MuseumPresenter.new()
	presenter.present_insects(furniture, session)
	presenter.present_sunshine(furniture, session)
