extends CanvasLayer

## Play HUD. T +1 hour, Y +1 day, U save. Esc returns to title (and saves).

@onready var _label: Label = %ClockLabel
@onready var _prompt: Label = %PromptLabel
@onready var _notice: Label = %NoticeLabel

var _notice_left: float = 0.0


func _ready() -> void:
	Clock.time_changed.connect(_refresh)
	Game.prompt_changed.connect(_on_prompt)
	Game.notice_posted.connect(_on_notice)
	Game.inventory.changed.connect(_refresh)
	_on_prompt(Game.interact_prompt)
	_refresh()


func _process(delta: float) -> void:
	if _notice_left <= 0.0:
		return
	_notice_left -= delta
	if _notice_left <= 0.0:
		_notice.text = ""


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
				Game.post_notice("Saved")
				get_viewport().set_input_as_handled()


func _refresh() -> void:
	_label.text = "%s\nWASD move  E interact  Esc title  T +1h  Y +1d" % Clock.format_clock()
	var pockets: int = Game.inventory.count_of_occupied()
	_label.text += "\nPockets %d/%d" % [pockets, Inventory.POCKET_SLOTS]


func _on_prompt(text: String) -> void:
	if text == "":
		_prompt.text = ""
	else:
		_prompt.text = "E — %s" % text


func _on_notice(text: String) -> void:
	_notice.text = text
	_notice_left = 2.5
	_refresh()
