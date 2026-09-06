extends CanvasLayer

## Minecraft-style debug console. Open with `/` or ` (backtick). Tab completes.

@onready var _root: Control = %Root
@onready var _log: RichTextLabel = %Log
@onready var _suggest: Label = %SuggestLabel
@onready var _input: LineEdit = %CommandInput

var _console: DebugConsole = DebugConsole.new()
var _open: bool = false
var _history_index: int = -1
var _live_line: String = ""
var _tab_matches: PackedStringArray = []
var _tab_index: int = -1


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("debug_console_ui")
	_root.visible = false
	_input.text_submitted.connect(_on_submit)
	_input.text_changed.connect(_on_text_changed)
	_input.gui_input.connect(_on_input_gui)
	_log.clear()
	_suggest.text = ""


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_root.visible = true
	_history_index = -1
	_live_line = ""
	_tab_matches.clear()
	_tab_index = -1
	_input.text = ""
	_suggest.text = ""
	_input.grab_focus()
	_input.caret_column = 0


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	_input.release_focus()
	_suggest.text = ""


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if _open:
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		return
	if _other_menu_open():
		return
	## `/` or backtick opens the console (Minecraft muscle memory).
	if key.keycode == KEY_SLASH or key.physical_keycode == KEY_SLASH \
			or key.keycode == KEY_QUOTELEFT or key.physical_keycode == KEY_QUOTELEFT:
		open()
		get_viewport().set_input_as_handled()


func _other_menu_open() -> bool:
	if get_tree() == null:
		return false
	for group: String in ["inventory_ui", "map_ui", "dialogue_ui", "shop_ui"]:
		var ui: Node = get_tree().get_first_node_in_group(group)
		if ui != null and ui.has_method("is_open") and bool(ui.call("is_open")):
			return true
	return false


func _on_submit(text: String) -> void:
	var line: String = text.strip_edges()
	_input.clear()
	_history_index = -1
	_live_line = ""
	_tab_matches.clear()
	_tab_index = -1
	_suggest.text = ""
	if line.is_empty():
		return
	_append_log("> %s" % line)
	var result: String = _console.execute(line)
	if result == "__clear__":
		_log.clear()
		return
	if not result.is_empty():
		_append_log(result)


func _on_text_changed(new_text: String) -> void:
	if _history_index < 0:
		_live_line = new_text
	_tab_matches.clear()
	_tab_index = -1
	_refresh_suggestions()


func _on_input_gui(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_TAB:
			_apply_tab(key.shift_pressed)
			_input.accept_event()
		KEY_UP:
			_step_history(-1)
			_input.accept_event()
		KEY_DOWN:
			_step_history(1)
			_input.accept_event()
		KEY_ESCAPE:
			close()
			_input.accept_event()


func _apply_tab(reverse: bool) -> void:
	if _tab_matches.is_empty():
		_tab_matches = _console.suggestions(_input.text)
		_tab_index = -1
		if _tab_matches.is_empty():
			_refresh_suggestions()
			return
		if _tab_matches.size() == 1:
			_set_input_text(_console.autocomplete(_input.text))
			_tab_matches.clear()
			_refresh_suggestions()
			return
		## Multiple matches: fill shared prefix first, then cycle on further Tabs.
		var shared: String = _console.autocomplete(_input.text)
		if shared != _input.text:
			_set_input_text(shared)
			_refresh_suggestions()
			return
	if _tab_matches.is_empty():
		return
	if reverse:
		_tab_index = (_tab_index - 1 + _tab_matches.size()) % _tab_matches.size()
	else:
		_tab_index = (_tab_index + 1) % _tab_matches.size()
	_set_input_text(_console.fill_suggestion(_input.text, String(_tab_matches[_tab_index])))
	_refresh_suggestions()


func _step_history(delta: int) -> void:
	if delta < 0:
		var prev: Dictionary = _console.history_prev(_input.text, _history_index)
		_history_index = int(prev["index"])
		_set_input_text(String(prev["text"]))
	else:
		var nxt: Dictionary = _console.history_next(_input.text, _history_index, _live_line)
		_history_index = int(nxt["index"])
		_set_input_text(String(nxt["text"]))
	_tab_matches.clear()
	_tab_index = -1
	_refresh_suggestions()


func _set_input_text(text: String) -> void:
	_input.text = text
	_input.caret_column = text.length()


func _refresh_suggestions() -> void:
	var matches: PackedStringArray = _console.suggestions(_input.text)
	if matches.is_empty():
		_suggest.text = ""
		return
	var shown: PackedStringArray = matches.slice(0, mini(8, matches.size()))
	var extra: String = "" if matches.size() <= 8 else " …+%d" % (matches.size() - 8)
	_suggest.text = "  ".join(shown) + extra


func _append_log(text: String) -> void:
	_log.append_text(text + "\n")
	## Keep the view pinned to the latest line.
	_log.scroll_to_line(_log.get_line_count())
