class_name PauseOverlay
extends CanvasLayer

## Esc pause menu: resume, settings, or save and return to the title. Pauses the tree while
## open, like the pockets.

const GROUP := &"pause_ui"

@onready var _root: Control = %Root
@onready var _resume: Button = %ResumeButton
@onready var _settings: Button = %SettingsButton
@onready var _exit: Button = %ExitButton

var _open: bool = false


## The one in `tree`, or null.
static func find(tree: SceneTree) -> PauseOverlay:
	return tree.get_first_node_in_group(GROUP) as PauseOverlay if tree != null else null


func _ready() -> void:
	layer = 30
	add_to_group(GROUP)
	_root.visible = false
	_resume.pressed.connect(close)
	_settings.pressed.connect(_open_settings)
	_exit.pressed.connect(_confirm_exit)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_root.visible = true
	get_tree().paused = true
	_resume.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	var settings: SettingsOverlay = SettingsOverlay.find(get_tree())
	if settings != null and settings.is_open():
		settings.close()
	get_tree().paused = false


func _open_settings() -> void:
	var settings: SettingsOverlay = SettingsOverlay.find(get_tree())
	if settings != null:
		settings.open()


func _confirm_exit() -> void:
	close()
	Game.return_to_title()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	var settings: SettingsOverlay = SettingsOverlay.find(get_tree())
	if settings != null and settings.is_open():
		return
	if event.is_action_pressed("pause_menu") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
