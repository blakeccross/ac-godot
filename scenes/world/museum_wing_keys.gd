extends Node

## Hotkeys while inside any museum wing (test scene + normal play).
## 1 entrance · 2 painting · 3 fossil · 4 insect · 5 fish

const WINGS: Array[StringName] = [
	&"museum_entrance",
	&"museum_painting",
	&"museum_fossil",
	&"museum_insect",
	&"museum_fish",
]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var idx: int = -1
	match key.keycode:
		KEY_1:
			idx = 0
		KEY_2:
			idx = 1
		KEY_3:
			idx = 2
		KEY_4:
			idx = 3
		KEY_5:
			idx = 4
		_:
			return
	if idx < 0 or idx >= WINGS.size():
		return
	if Game.current_room_id == WINGS[idx]:
		return
	Game.try_enter_interior(WINGS[idx])
	get_viewport().set_input_as_handled()
