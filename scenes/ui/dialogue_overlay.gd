extends CanvasLayer

## Modal talk window (`m_msg` appear/normal/cursor/disappear) drawn by `MessageWindowChrome`.

signal closed
signal event_fired(event: Dictionary)

## Message logic runs on a 30 Hz tick in the original (`mMsg_BUTTON_TURN_TIME` = 60).
const FRAME_HZ := 30.0
## `m_msg_appear` / `m_msg_disappear`: linear scale over 18 frames (accel/brake 0).
const APPEAR_FRAMES := 18.0
## `mChoice` appear/disappear duration.
const CHOICE_APPEAR_FRAMES := 10.2
## Every other frame @ 30 Hz (`mMsg_STATUS_FLAG_NOT_PAUSE_FRAME`).
const CHARS_PER_SEC := 15.0
## `mMsg_STATUS_FLAG_FAST_TEXT` clears the pause frame → one glyph per tick.
const FAST_CHARS_PER_SEC := 30.0

enum Phase { HIDDEN, APPEARING, OPEN, DISAPPEARING }
enum ChoicePhase { HIDDEN, APPEARING, OPEN, DISAPPEARING }

@onready var _root: Control = %Root
@onready var _chrome: MessageWindowChrome = %MessageChrome
@onready var _choices: VBoxContainer = %ChoiceList

var _runner: DialogueRunner
var _open: bool = false
var _phase: Phase = Phase.HIDDEN
var _anim_t: float = 0.0
var _choice_phase: ChoicePhase = ChoicePhase.HIDDEN
var _choice_anim_t: float = 0.0
var _shown: String = ""
var _visible_len: int = 0
var _cursor: int = 0
var _type_accum: float = 0.0
var _fast_text: bool = false
var _choice_index: int = 0
var _buttons: Array[Button] = []
var _pending_choice: int = -1


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("dialogue_ui")
	if not Engine.is_editor_hint():
		_root.visible = false


func is_open() -> bool:
	return _open


## `mMsg_Check_MainNormal` / choice normal — waiting on the player, not typing.
func is_awaiting_input() -> bool:
	if not _open or _runner == null or _phase != Phase.OPEN:
		return false
	if _choice_phase == ChoicePhase.APPEARING or _choice_phase == ChoicePhase.DISAPPEARING:
		return false
	if _runner.waiting_choice or _runner.waiting_prompt:
		return true
	if _runner.done:
		return false
	return _cursor >= _visible_len and _visible_len > 0


## `mMsg_Check_NowUtter`: text is still being laid in. Drives NPC mouth flap.
func is_uttering() -> bool:
	return _open and _phase == Phase.OPEN and _cursor < _visible_len


func runner() -> DialogueRunner:
	return _runner


## Skip typewriter / pick first choice / advance one step — for offline recording.
func fast_advance() -> void:
	if not _open or _runner == null:
		return
	if _phase == Phase.APPEARING:
		_finish_appear()
	if _choice_phase == ChoicePhase.APPEARING:
		_finish_choice_appear()
	if _runner.waiting_choice and not _buttons.is_empty():
		_pick(_choice_index)
		return
	if _cursor < _visible_len:
		_cursor = _visible_len
		_chrome.set_body_visible_chars(_cursor)
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
		close(true)
	if _runner != null:
		_disconnect_runner()
	_runner = DialogueRunner.new()
	_runner.advance_gate = advance_gate
	_runner.line_shown.connect(_on_line)
	_runner.choices_shown.connect(_on_choices)
	_runner.finished.connect(_on_finished)
	_runner.event_fired.connect(_on_runner_event)
	_begin_open(ctx.speaker_name if ctx != null else "", _sex_from_ctx(ctx))
	_runner.start(data, ctx, state)
	if _runner != null and _runner.done:
		close(true)


func say(
	text: String,
	speaker: String = "",
	sex: MessageWindowChrome.SpeakerSex = MessageWindowChrome.SpeakerSex.OTHER
) -> void:
	if text.is_empty():
		return
	if _open:
		close(true)
	if _runner != null:
		_disconnect_runner()
		_runner = null
	_begin_open(speaker, sex)
	_on_line(text)


func close(immediate: bool = false) -> void:
	if not _open:
		return
	_clear_choices_immediate()
	if immediate or _phase == Phase.APPEARING or _phase == Phase.HIDDEN:
		_finish_close()
		return
	if _phase == Phase.DISAPPEARING:
		return
	_phase = Phase.DISAPPEARING
	_anim_t = 0.0
	_chrome.set_continue_visible(false)


func _begin_open(speaker: String, sex: MessageWindowChrome.SpeakerSex) -> void:
	_open = true
	_phase = Phase.APPEARING
	_anim_t = 0.0
	_fast_text = false
	_type_accum = 0.0
	_root.visible = true
	_chrome.set_window_scale(0.0)
	_chrome.set_choice_scale(0.0)
	_chrome.set_speaker(speaker, sex)
	_chrome.set_continue_visible(false)
	_clear_choices_immediate()


func _sex_from_ctx(ctx: DialogueContext) -> MessageWindowChrome.SpeakerSex:
	if ctx == null:
		return MessageWindowChrome.SpeakerSex.OTHER
	return MessageWindowChrome.sex_from_int(ctx.speaker_sex)


func _finish_appear() -> void:
	_phase = Phase.OPEN
	_anim_t = 0.0
	_chrome.set_window_scale(1.0)
	if _cursor >= _visible_len:
		_show_continue()


func _finish_close() -> void:
	_open = false
	_phase = Phase.HIDDEN
	_anim_t = 0.0
	_root.visible = false
	_shown = ""
	_visible_len = 0
	_cursor = 0
	_type_accum = 0.0
	_fast_text = false
	_chrome.set_window_scale(1.0)
	_chrome.set_continue_visible(false)
	_disconnect_runner()
	_runner = null
	_clear_choices_immediate()
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
	if not _open:
		return
	_process_window_anim(delta)
	_process_choice_anim(delta)
	if _phase != Phase.OPEN:
		return
	if _runner != null and _runner.waiting_choice:
		return
	if _cursor >= _visible_len:
		return
	var rate := FAST_CHARS_PER_SEC if _fast_text else CHARS_PER_SEC
	if Input.is_action_pressed("interact") or Input.is_action_pressed("ui_accept"):
		_fast_text = true
		rate = FAST_CHARS_PER_SEC
	_type_accum += rate * delta
	var step := int(_type_accum)
	if step <= 0:
		return
	_type_accum -= float(step)
	_cursor = mini(_visible_len, _cursor + step)
	_chrome.set_body_visible_chars(_cursor)
	if _cursor >= _visible_len:
		_show_continue()


func _process_window_anim(delta: float) -> void:
	if _phase == Phase.APPEARING:
		_anim_t = minf(APPEAR_FRAMES, _anim_t + delta * FRAME_HZ)
		## accel/brake 0 → linear (`get_percent_forAccelBrake`).
		_chrome.set_window_scale(_anim_t / APPEAR_FRAMES)
		if _anim_t >= APPEAR_FRAMES:
			_finish_appear()
	elif _phase == Phase.DISAPPEARING:
		_anim_t = minf(APPEAR_FRAMES, _anim_t + delta * FRAME_HZ)
		_chrome.set_window_scale(1.0 - _anim_t / APPEAR_FRAMES)
		if _anim_t >= APPEAR_FRAMES:
			_finish_close()


func _process_choice_anim(delta: float) -> void:
	if _choice_phase == ChoicePhase.APPEARING:
		_choice_anim_t = minf(CHOICE_APPEAR_FRAMES, _choice_anim_t + delta * FRAME_HZ)
		_chrome.set_choice_scale(_choice_anim_t / CHOICE_APPEAR_FRAMES)
		if _choice_anim_t >= CHOICE_APPEAR_FRAMES:
			_finish_choice_appear()
	elif _choice_phase == ChoicePhase.DISAPPEARING:
		_choice_anim_t = minf(CHOICE_APPEAR_FRAMES, _choice_anim_t + delta * FRAME_HZ)
		_chrome.set_choice_scale(1.0 - _choice_anim_t / CHOICE_APPEAR_FRAMES)
		if _choice_anim_t >= CHOICE_APPEAR_FRAMES:
			_finish_choice_disappear()


func _finish_choice_appear() -> void:
	_choice_phase = ChoicePhase.OPEN
	_choice_anim_t = 0.0
	_chrome.set_choice_scale(1.0)


func _finish_choice_disappear() -> void:
	var pick := _pending_choice
	_pending_choice = -1
	_choice_phase = ChoicePhase.HIDDEN
	_choice_anim_t = 0.0
	_clear_choices_immediate()
	if pick < 0 or _runner == null:
		return
	_runner.choose(pick)
	if _runner != null and _runner.done:
		close()


func _show_continue() -> void:
	var blocked: bool = _runner != null and _runner.is_continue_blocked()
	_chrome.set_continue_visible(not blocked)


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if _phase == Phase.APPEARING or _phase == Phase.DISAPPEARING:
		get_viewport().set_input_as_handled()
		return
	if _choice_phase == ChoicePhase.APPEARING or _choice_phase == ChoicePhase.DISAPPEARING:
		get_viewport().set_input_as_handled()
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
		if _cursor < _visible_len:
			## Cancelable dump / A-to-complete page.
			_cursor = _visible_len
			_chrome.set_body_visible_chars(_cursor)
			_show_continue()
			return
		if _runner == null:
			close()
			return
		_runner.advance()
		if _runner != null and _runner.done:
			close()


func _choice_input(event: InputEvent) -> void:
	if _choice_phase != ChoicePhase.OPEN or _buttons.is_empty():
		return
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
	_chrome.set_body(text)
	_visible_len = _chrome.body_visible_char_count()
	_cursor = 0
	_type_accum = 0.0
	_fast_text = false
	_chrome.set_body_visible_chars(0)
	_chrome.set_continue_visible(false)
	_clear_choices_immediate()
	## Hold glyphs until appear finishes (cursor stays 0 during `mMsg_INDEX_APPEAR`).
	if _phase == Phase.OPEN and _visible_len == 0:
		_show_continue()


func _on_choices(options: Array) -> void:
	_shown = _runner.line
	_chrome.set_body(_shown)
	_visible_len = _chrome.body_visible_char_count()
	_cursor = _visible_len
	_chrome.set_body_visible_chars(_cursor)
	_chrome.set_continue_visible(false)
	_clear_choices_immediate()
	_choice_index = 0
	for i: int in options.size():
		var opt: Dictionary = options[i]
		var btn := Button.new()
		btn.text = str(opt.get("text", ""))
		btn.focus_mode = Control.FOCUS_NONE
		btn.flat = true
		btn.set_meta("choice_label", btn.text)
		btn.set_meta("choice_selected", i == 0)
		btn.pressed.connect(_pick.bind(i))
		_choices.add_child(btn)
		_buttons.append(btn)
	_choice_phase = ChoicePhase.APPEARING
	_choice_anim_t = 0.0
	_chrome.set_choice_scale(0.0)
	_highlight()


func _on_finished() -> void:
	close()


func _pick(index: int) -> void:
	if _runner == null or _buttons.is_empty():
		return
	if _choice_phase == ChoicePhase.DISAPPEARING:
		return
	if _choice_phase == ChoicePhase.APPEARING:
		_finish_choice_appear()
	_pending_choice = index
	_choice_phase = ChoicePhase.DISAPPEARING
	_choice_anim_t = 0.0


func _highlight() -> void:
	for i: int in _buttons.size():
		_buttons[i].set_meta("choice_selected", i == _choice_index)
		_chrome.style_choice(_buttons[i], i == _choice_index)


func _clear_choices_immediate() -> void:
	_choice_phase = ChoicePhase.HIDDEN
	_choice_anim_t = 0.0
	_pending_choice = -1
	_buttons.clear()
	_chrome.clear_choices()
