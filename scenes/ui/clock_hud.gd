extends CanvasLayer

## Play HUD host: overlays, interaction prompt, event notices. Hidden debug keys: T +1 hour,
## Y +1 day, U next season, I cycle weather (the console's `time` / `season` do the same).
## Esc asks to exit to the title (`PauseOverlay`). X opens pockets. `/` or ` opens the console.

@onready var _prompt: Label = %PromptLabel
@onready var _notice: Label = %NoticeLabel
@onready var _inventory: CanvasLayer = $InventoryOverlay
@onready var _console: CanvasLayer = $DebugConsole

var _notice_left: float = 0.0


func _ready() -> void:
	Game.prompt_changed.connect(_on_prompt)
	Game.notice_posted.connect(_on_notice)
	_on_prompt(Game.interact_prompt)


func inventory_is_open() -> bool:
	return _inventory != null and _inventory.has_method("is_open") and bool(_inventory.call("is_open"))


func dialogue_is_open() -> bool:
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	return ui != null and ui.has_method("is_open") and bool(ui.call("is_open"))


func shop_is_open() -> bool:
	var ui: Node = get_tree().get_first_node_in_group("shop_ui") if get_tree() != null else null
	return ui != null and ui.has_method("is_open") and bool(ui.call("is_open"))


func console_is_open() -> bool:
	return _console != null and _console.has_method("is_open") and bool(_console.call("is_open"))


func _process(delta: float) -> void:
	if _notice_left <= 0.0:
		return
	_notice_left -= delta
	if _notice_left <= 0.0:
		_notice.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if inventory_is_open() or dialogue_is_open() or shop_is_open() or console_is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_T:
				Clock.advance_minutes(60)
				get_viewport().set_input_as_handled()
			KEY_Y:
				Clock.advance_minutes(60 * 24)
				get_viewport().set_input_as_handled()
			KEY_U:
				Clock.advance_season()
				Game.post_notice(Clock.season_name())
				get_viewport().set_input_as_handled()
			KEY_I:
				Game.cycle_weather_debug()
				Game.post_notice("Weather: %s" % String(Game.weather))
				get_viewport().set_input_as_handled()


func _on_prompt(text: String) -> void:
	if text == "":
		_prompt.text = ""
	else:
		_prompt.text = "E — %s" % text


func _on_notice(text: String) -> void:
	_notice.text = text
	_notice_left = 2.5
