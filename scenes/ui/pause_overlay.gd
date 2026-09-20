extends CanvasLayer

## Esc confirm: "Exit to the title screen?" Saves (via `Game.return_to_title`) on Yes.
## Pauses the tree while open, like the pockets.

@onready var _root: Control = %Root
@onready var _yes: Button = %YesButton
@onready var _no: Button = %NoButton

var _open: bool = false


func _ready() -> void:
	layer = 30
	add_to_group("pause_ui")
	_root.visible = false
	_yes.pressed.connect(_confirm)
	_no.pressed.connect(close)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_root.visible = true
	get_tree().paused = true
	## Default to the safe answer so a stray Enter doesn't leave the game.
	_no.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	get_tree().paused = false


func _confirm() -> void:
	close()
	Game.return_to_title()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("pause_menu") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
