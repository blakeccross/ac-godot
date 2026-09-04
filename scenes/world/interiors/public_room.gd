extends Node3D

## Authored public interior (Nook, Able Sisters, police, post, …).
## Shell GLBs live under `Shell/GeneratedVisual`; collision / stock fill at `populate()`.

@export var room_id: StringName = &""

var _session: Interior = null


func populate() -> void:
	if room_id == &"" or Game == null:
		return
	var room: Room = Game.interiors.room(room_id)
	if room == null:
		return
	_session = Interior.new()
	_session.bind(room)
	InteriorBuilder.new().populate_authored(self, _session)


func present_exhibits(furniture: Node3D, session: Interior) -> void:
	## Pin Tom Nook to the current shop's `shop0N_actable` stand.
	if furniture == null or session == null or not ShopDisplay.nook_is_shop_room(room_id):
		return
	InteriorBuilder.new().add_tom_nook(furniture, session)
