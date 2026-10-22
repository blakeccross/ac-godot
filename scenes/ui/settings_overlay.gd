class_name SettingsOverlay
extends CanvasLayer

## Screen shape and controls remapping. Open from the pause menu or the title. Process always so it works while
## the tree is paused.

const GROUP := &"settings_ui"

@onready var _root: Control = %Root
@onready var _list: VBoxContainer = %BindList
@onready var _hint: Label = %HintLabel
@onready var _reset: Button = %ResetButton
@onready var _back: Button = %BackButton

var _open: bool = false
var _waiting: StringName = &""
var _bind_buttons: Dictionary = {} ## StringName → Button
var _screen_button: Button


## The one in `tree`, or null.
static func find(tree: SceneTree) -> SettingsOverlay:
	return tree.get_first_node_in_group(GROUP) as SettingsOverlay if tree != null else null


func _ready() -> void:
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	_root.visible = false
	_reset.pressed.connect(_on_reset)
	_back.pressed.connect(close)
	_build_rows()
	InputBindings.ensure_loaded()
	_refresh_labels()


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_waiting = &""
	_root.visible = true
	InputBindings.ensure_loaded()
	DisplayConfig.ensure_loaded()
	_refresh_labels()
	_hint.text = "Click a binding, then press a key or button. Esc cancels."
	_back.grab_focus()


func close() -> void:
	if not _open:
		return
	_waiting = &""
	_open = false
	_root.visible = false


func _build_rows() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	_bind_buttons.clear()
	_list.add_child(_build_screen_row())
	for entry: Dictionary in InputBindings.ACTIONS:
		var id: StringName = entry["id"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_label := Label.new()
		name_label.text = str(entry["label"])
		name_label.custom_minimum_size = Vector2(160, 0)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bind_btn := Button.new()
		bind_btn.custom_minimum_size = Vector2(260, 0)
		bind_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bind_btn.pressed.connect(_on_bind_pressed.bind(id))
		row.add_child(name_label)
		row.add_child(bind_btn)
		_list.add_child(row)
		_bind_buttons[id] = bind_btn


func _build_screen_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.text = "Screen"
	name_label.custom_minimum_size = Vector2(160, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen_button = Button.new()
	_screen_button.custom_minimum_size = Vector2(260, 0)
	_screen_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_screen_button.pressed.connect(_on_screen_pressed)
	row.add_child(name_label)
	row.add_child(_screen_button)
	return row


func _on_screen_pressed() -> void:
	DisplayConfig.set_aspect(DisplayConfig.next(), get_window())
	_refresh_labels()


func _refresh_labels() -> void:
	if _screen_button != null:
		_screen_button.text = DisplayConfig.label()
	for id: Variant in _bind_buttons.keys():
		var button: Button = _bind_buttons[id]
		if id == _waiting:
			button.text = "Press a key or button…"
		else:
			button.text = InputBindings.describe(StringName(str(id)))


func _on_bind_pressed(action: StringName) -> void:
	_waiting = action
	_hint.text = "Waiting for %s…" % _label_of(action)
	_refresh_labels()


func _on_reset() -> void:
	_waiting = &""
	InputBindings.restore_defaults()
	_hint.text = "Bindings restored to defaults."
	_refresh_labels()


func _label_of(action: StringName) -> String:
	for entry: Dictionary in InputBindings.ACTIONS:
		if entry["id"] == action:
			return str(entry["label"])
	return String(action)


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if _waiting == &"":
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
			close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or (
		event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE
	):
		_waiting = &""
		_hint.text = "Click a binding, then press a key or button. Esc cancels."
		_refresh_labels()
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey or event is InputEventJoypadButton:
		var action: StringName = _waiting
		_waiting = &""
		if InputBindings.rebind(action, event):
			_hint.text = "Bound %s." % _label_of(action)
		else:
			_hint.text = "That input can't be bound."
		_refresh_labels()
		get_viewport().set_input_as_handled()
