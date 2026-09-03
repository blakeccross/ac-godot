extends CanvasLayer

## Modal talk window (`m_msg` appear/normal/cursor) drawn by `MessageWindowChrome`.

signal closed
signal event_fired(event: Dictionary)

const CHARS_PER_SEC := 42.0
const FAST_SCALE := 8.0

@onready var _root: Control = %Root
@onready var _chrome: MessageWindowChrome = %MessageChrome
@onready var _choices: VBoxContainer = %ChoiceList

var _runner: DialogueRunner
var _open: bool = false
var _shown: String = ""
var _cursor: int = 0
var _choice_index: int = 0
var _buttons: Array[Button] = []


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("dialogue_ui")
	if not Engine.is_editor_hint():
		_root.visible = false


func is_open() -> bool:
	return _open


## `mMsg_Check_NowUtter`: text is still being laid in. Drives NPC mouth flap.
func is_uttering() -> bool:
	return _open and _cursor < _shown.length()


func runner() -> DialogueRunner:
	return _runner


## Skip typewriter / pick first choice / advance one step — for offline recording.
func fast_advance() -> void:
	if not _open or _runner == null:
		return
	if _runner.waiting_choice and not _buttons.is_empty():
		_pick(_choice_index)
		return
	if _cursor < _shown.length():
		_cursor = _shown.length()
		_chrome.set_body(_shown)
		_show_continue()
		return
	if _runner == null:
		return
	_runner.advance()
	if _runner.done:
		close()


func play(
	data: DialogueData,
	ctx: DialogueContext,
	state: VillagerState = null,
	advance_gate: Callable = Callable()
) -> void:
	if data == null:
		return
	if _open:
		close()
	if _runner != null:
		_disconnect_runner()
	_runner = DialogueRunner.new()
	_runner.advance_gate = advance_gate
	_runner.line_shown.connect(_on_line)
	_runner.choices_shown.connect(_on_choices)
	_runner.finished.connect(_on_finished)
	_runner.event_fired.connect(_on_runner_event)
	_open = true
	_root.visible = true
	_chrome.set_speaker(ctx.speaker_name if ctx != null else "")
	_chrome.set_continue_visible(false)
	_clear_choices()
	_runner.start(data, ctx, state)
	if _runner != null and _runner.done:
		close()


func say(text: String, speaker: String = "") -> void:
	if text.is_empty():
		return
	if _open:
		close()
	if _runner != null:
		_disconnect_runner()
		_runner = null
	_open = true
	_root.visible = true
	_chrome.set_speaker(speaker)
	_clear_choices()
	_on_line(text)


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	_shown = ""
	_cursor = 0
	_chrome.set_continue_visible(false)
	_disconnect_runner()
	_runner = null
	_clear_choices()
	closed.emit()


func _disconnect_runner() -> void:
	if _runner == null:
		return
	if _runner.line_shown.is_connected(_on_line):
		_runner.line_shown.disconnect(_on_line)
	if _runner.choices_shown.is_connected(_on_choices):
		_runner.choices_shown.disconnect(_on_choices)
	if _runner.finished.is_connected(_on_finished):
		_runner.finished.disconnect(_on_finished)
	if _runner.event_fired.is_connected(_on_runner_event):
		_runner.event_fired.disconnect(_on_runner_event)


func _on_runner_event(event: Dictionary) -> void:
	event_fired.emit(event)


func _process(delta: float) -> void:
	if not _open or (_runner != null and _runner.waiting_choice):
		return
	if _cursor >= _shown.length():
		return
	var rate: float = CHARS_PER_SEC
	if Input.is_action_pressed("interact") or Input.is_action_pressed("ui_accept"):
		rate *= FAST_SCALE
	_cursor = mini(_shown.length(), _cursor + int(ceil(rate * delta)))
	_chrome.set_body(_shown.substr(0, _cursor))
	if _cursor >= _shown.length():
		_show_continue()


func _show_continue() -> void:
	var blocked: bool = _runner != null and _runner.is_continue_blocked()
	_chrome.set_continue_visible(not blocked)


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if _runner != null and _runner.waiting_prompt:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
		get_viewport().set_input_as_handled()
		return
	if _runner != null and _runner.waiting_choice:
		_choice_input(event)
		return
	if _runner != null and _runner.is_continue_blocked():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if _cursor < _shown.length():
			_cursor = _shown.length()
			_chrome.set_body(_shown)
			_show_continue()
			return
		if _runner == null:
			close()
			return
		_runner.advance()
		if _runner != null and _runner.done:
			close()


func _choice_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		_choice_index = posmod(_choice_index - 1, _buttons.size())
		_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		_choice_index = posmod(_choice_index + 1, _buttons.size())
		_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_pick(_choice_index)
		get_viewport().set_input_as_handled()


func _on_line(text: String) -> void:
	_shown = text
	_cursor = 0
	_chrome.set_body("")
	_chrome.set_continue_visible(false)
	_clear_choices()


func _on_choices(options: Array) -> void:
	_shown = _runner.line
	_cursor = _shown.length()
	_chrome.set_body(_shown)
	_chrome.set_continue_visible(false)
	_clear_choices()
	_choice_index = 0
	for i: int in options.size():
		var opt: Dictionary = options[i]
		var btn := Button.new()
		btn.text = str(opt.get("text", ""))
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_pick.bind(i))
		_choices.add_child(btn)
		_buttons.append(btn)
	_highlight()


func _on_finished() -> void:
	close()


func _pick(index: int) -> void:
	if _runner == null:
		return
	_runner.choose(index)
	if _runner != null and _runner.done:
		close()


func _highlight() -> void:
	for i: int in _buttons.size():
		_chrome.style_choice(_buttons[i], i == _choice_index)


func _clear_choices() -> void:
	for child: Node in _choices.get_children():
		child.queue_free()
	_buttons.clear()
