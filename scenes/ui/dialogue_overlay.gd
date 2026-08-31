extends CanvasLayer

## Modal talk window (`m_msg` appear/normal/cursor). Placeholder chrome.

signal closed

const CHARS_PER_SEC := 42.0
const FAST_SCALE := 8.0

@onready var _root: Control = %Root
@onready var _name: Label = %NameLabel
@onready var _body: Label = %BodyLabel
@onready var _hint: Label = %HintLabel
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
	_root.visible = false


func is_open() -> bool:
	return _open


func play(data: DialogueData, ctx: DialogueContext, state: VillagerState = null) -> void:
	if data == null:
		return
	if _open:
		close()
	if _runner != null:
		_disconnect_runner()
	_runner = DialogueRunner.new()
	_runner.line_shown.connect(_on_line)
	_runner.choices_shown.connect(_on_choices)
	_runner.finished.connect(_on_finished)
	_open = true
	_root.visible = true
	_name.text = ctx.speaker_name if ctx != null else ""
	_name.visible = _name.text != ""
	_hint.text = ""
	_clear_choices()
	_runner.start(data, ctx, state)
	if _runner != null and _runner.done:
		close()


## One line of text with no conversation behind it, dismissed the same way as any other. The
## original's catch report is a plain `mMsg` window with `LockContinue` held until the player
## advances it, which is what `notice_rod` waits on before putting the rod away.
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
	_name.text = speaker
	_name.visible = speaker != ""
	_clear_choices()
	_on_line(text)


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	_shown = ""
	_cursor = 0
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


func _process(delta: float) -> void:
	if not _open or (_runner != null and _runner.waiting_choice):
		return
	if _cursor >= _shown.length():
		return
	var rate: float = CHARS_PER_SEC
	if Input.is_action_pressed("interact") or Input.is_action_pressed("ui_accept"):
		rate *= FAST_SCALE
	_cursor = mini(_shown.length(), _cursor + int(ceil(rate * delta)))
	_body.text = _shown.substr(0, _cursor)
	if _cursor >= _shown.length():
		_hint.text = "E continue"


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
		get_viewport().set_input_as_handled()
		return
	if _runner != null and _runner.waiting_choice:
		_choice_input(event)
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if _cursor < _shown.length():
			_cursor = _shown.length()
			_body.text = _shown
			_hint.text = "E continue"
			return
		if _runner == null:
			## A `say` line has nothing to advance to, so dismissing it closes the window.
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
	_body.text = ""
	_hint.text = ""
	_clear_choices()


func _on_choices(options: Array) -> void:
	_shown = _runner.line
	_cursor = _shown.length()
	_body.text = _shown
	_hint.text = "E choose"
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
		_buttons[i].modulate = Color(1, 0.95, 0.55) if i == _choice_index else Color.WHITE


func _clear_choices() -> void:
	for child: Node in _choices.get_children():
		child.queue_free()
	_buttons.clear()
