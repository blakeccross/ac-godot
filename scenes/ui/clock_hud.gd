extends CanvasLayer

## Debug-readable clock. T +1 hour, Y +1 day, U save, I load.

@onready var _label: Label = %ClockLabel


func _ready() -> void:
	Clock.time_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_T:
				Clock.advance_minutes(60)
				get_viewport().set_input_as_handled()
			KEY_Y:
				Clock.advance_minutes(60 * 24)
				get_viewport().set_input_as_handled()
			KEY_U:
				SaveService.save_game()
				get_viewport().set_input_as_handled()
			KEY_I:
				if SaveService.has_save():
					SaveService.load_game()
				get_viewport().set_input_as_handled()


func _refresh() -> void:
	_label.text = "%s\nWASD move  Shift sprint  T +1h  Y +1d  U save  I load" % Clock.format_clock()
