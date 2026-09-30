extends CanvasLayer

## The letter composition board (`m_board_ovl.c` WRITE mode) over the pad keyboard
## (`m_editor_ovl.c`, `mED_TYPE_BOARD`, with its ink pot). Recipient
## (`letter_address_overlay`) and paper (`letter_paper_picker_overlay`) are chosen
## before this opens.
##
## Header ("Dear <name>," with the name in red while writing, like
## `mBD_set_writing_header`) and footer (the player's name) are filled in; only the
## body is edited — an approved simplification of the three editable fields. The body
## is 6 lines (`mBD_BODY_LINE_NUM`) of at most `mBD_MAX_WIDTH`, wrapping like
## `mBD_strLineCheck`. The paper rolls in 16-px steps to keep the line being written
## above the keyboard (`mBD_roll_control`). START (Escape) asks "Is this OK?"
## (`mSM_OVL_EDITENDCHK`, Yes / Rewrite); Escape on an empty body just closes.
##
## `open_board` edits the house gyroid's message instead (`m_hboard_ovl.c`): its own
## frame, 4 lines of the same width, 128 characters, dark red text at (46, 54).
##
## Keys: typing goes straight onto the paper; Enter starts a new line (the C-stick's
## down at the end of the text); the rest is `KeyboardPanel`'s mapping.

signal closed

const MAX_LINES := 6
## `mED_TYPE_HBOARD` (`m_hboard_ovl`): the house gyroid's visitor message.
const HBOARD_LINES := 4
const HBOARD_LEN := 128
const HBOARD_TEXT := Vector2(46, 54)
const HBOARD_COLOR := Color8(30, 0, 0)
const FONT_PX := 16
const CURSOR_COLOR := Color8(195, 80, 80)

var _open: bool = false
var _recipient: Dictionary = {}
var _paper_type: int = 0
var _lines: PackedStringArray = PackedStringArray([""])
var _prompt: bool = false
## Board mode: `_max_lines` / `_max_len` caps and the callback that receives the text on
## Save. Letter mode leaves `_board_cb` invalid.
var _max_lines: int = MAX_LINES
var _max_len: int = -1
var _board_cb: Callable = Callable()
## `mBD_roll_control`.
var _center_line: int = 2
var _roll_speed: float = 1.0
var _end_tex: Texture2D = null
## The address book is up over the board (`letter_address_overlay`).
var _choosing_address: bool = false

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _board: LetterBoard = $Root/Screen/Board
@onready var _hboard: TextureRect = $Root/Screen/HBoard
@onready var _marks: Control = $Root/Screen/Marks
@onready var _keyboard: KeyboardPanel = $Root/Screen/Keyboard
@onready var _promptbox: EditEndPrompt = $Root/Screen/Prompt


func _ready() -> void:
	layer = 27
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("letter_writer_ui")
	_root.visible = false
	_marks.draw.connect(_draw_marks)
	_keyboard.typed.connect(_type)
	_keyboard.erased.connect(_backspace)
	_promptbox.answered.connect(_on_answer)
	_root.resized.connect(_fit_screen)
	var path := "res://assets/generated/ui/menu/kb_end.png"
	_end_tex = load(path) if ResourceLoader.exists(path) else null
	path = "res://assets/generated/ui/menu/hboard.png"
	_hboard.texture = load(path) if ResourceLoader.exists(path) else null
	_fit_screen()
	set_process(false)
	set_process_unhandled_input(false)


func _fit_screen() -> void:
	var sz := _root.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var k := minf(sz.x / 320.0, sz.y / 240.0)
	_screen.scale = Vector2(k, k)
	_screen.position = (sz - Vector2(320, 240) * k) * 0.5


func is_open() -> bool:
	return _open


func _is_hboard() -> bool:
	return _board_cb.is_valid()


## Edit a free text block in place (`m_hboard_ovl`): `initial` split on newlines, capped at
## `lines` lines / `max_len` characters. `callback(text: String)` runs on Save.
func open_board(initial: String, lines: int, max_len: int, callback: Callable, paper_type: int = 0) -> void:
	if _open:
		return
	open({}, paper_type)
	_max_lines = lines
	_max_len = max_len
	_board_cb = callback
	_lines = PackedStringArray(initial.split("\n")) if initial != "" else PackedStringArray([""])
	while _lines.size() > _max_lines:
		_lines.remove_at(_lines.size() - 1)
	_refresh()


## `mSM_BD_OPEN_WRITE`: the board comes up on the chosen paper with the address book
## over it (`mSM_open_submenu_new2(..., mSM_OVL_ADDRESS, ...)`); writing starts once a
## recipient is picked, and backing out of the book closes the board.
func open_letter(paper_type: int) -> void:
	if _open:
		return
	open({"name": ""}, paper_type)
	_choosing_address = true
	var address: Node = get_tree().get_first_node_in_group("letter_address_ui")
	if address == null or not address.has_method("open"):
		_choosing_address = false
		return
	## `mBD_set_point`: `ofs_x = header width before the name + 36 - 96`.
	var anchor := _board.text_width(_board.header) + 36.0 - 96.0
	address.call("open", _on_address_picked, anchor)


func _on_address_picked(recipient: Dictionary) -> void:
	_choosing_address = false
	if recipient.is_empty():
		close()
		return
	_recipient = recipient
	_board.header_name = str(recipient.get("name", ""))
	_refresh()


func open(recipient: Dictionary, paper_type: int) -> void:
	if _open:
		return
	_max_lines = MAX_LINES
	_max_len = -1
	_board_cb = Callable()
	_recipient = recipient
	_paper_type = LetterChrome.clamp_paper_type(paper_type)
	_lines = PackedStringArray([""])
	_prompt = false
	_choosing_address = false
	_center_line = 2
	_roll_speed = 1.0
	_open = true
	_root.visible = true
	_promptbox.close()
	_board.paper_type = _paper_type
	_board.position_y = 0.0
	_board.header = "Dear "
	_board.header_name = str(_recipient.get("name", "Friend"))
	_board.header_after = ","
	_board.footer = Game.player_name if Game != null else ""
	_keyboard.mode = KeyboardPanel.InputMode.LETTER
	_keyboard.caps = false
	_keyboard.refresh()
	set_process(true)
	set_process_unhandled_input(true)
	Audio.play_se(&"cursol")
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	set_process(false)
	set_process_unhandled_input(false)
	_board_cb = Callable()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or _choosing_address or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	var k := event as InputEventKey
	if _prompt:
		if not k.echo:
			_promptbox.handle_key(k)
		return
	match k.keycode:
		KEY_ESCAPE:
			if k.echo:
				return
			if "".join(_lines).strip_edges() == "" and not _is_hboard():
				Audio.play_se(&"cursol")
				close()
				return
			_open_prompt()
			return
		KEY_ENTER, KEY_KP_ENTER:
			if not k.shift_pressed:
				_newline()
				return
	_keyboard.handle_key(k)


func _type(ch: String) -> void:
	if _max_len > 0 and "\n".join(_lines).length() >= _max_len:
		Audio.play_se(&"cursol")
		return
	var line: String = _lines[_lines.size() - 1]
	var candidate: String = line + ch
	if _board.text_width(candidate) > LetterBoard.MAX_WIDTH:
		if _lines.size() >= _max_lines:
			Audio.play_se(&"cursol")
			return
		## Break at the last space so a wrap doesn't split a word mid-way
		## (`mBD_LINE_CHECK_OVERSTRING` vs `_OVERLINE` distinguishes exactly this).
		var break_at: int = line.rfind(" ")
		var kept: String = line
		var carry: String = ""
		if break_at >= 0:
			kept = line.substr(0, break_at)
			carry = line.substr(break_at + 1)
		_lines[_lines.size() - 1] = kept
		_lines.append(carry + ch)
	else:
		_lines[_lines.size() - 1] = candidate
	Audio.play_se(&"cursol")
	_refresh()


func _newline() -> void:
	if _lines.size() >= _max_lines:
		Audio.play_se(&"cursol")
		return
	_lines.append("")
	Audio.play_se(&"cursol")
	_refresh()


func _backspace() -> void:
	var last: int = _lines.size() - 1
	if _lines[last] != "":
		_lines[last] = _lines[last].substr(0, _lines[last].length() - 1)
	elif last > 0:
		_lines.remove_at(last)
	Audio.play_se(&"cursol")
	_refresh()


func _open_prompt() -> void:
	_prompt = true
	_promptbox.open(EditEndPrompt.Kind.BOARD)
	Audio.play_se(&"cursol")


## `mEE_TYPE_BOARD`: Yes sends, Rewrite goes back to the board.
func _on_answer(idx: int) -> void:
	_resolve_prompt(idx)


## 0 Yes (save), 1 Rewrite, 2 throw it out (only reachable by closing an empty board).
func _resolve_prompt(idx: int) -> void:
	_prompt = false
	_promptbox.close()
	match idx:
		0:
			_save()
		1:
			_refresh()
		_:
			Audio.play_se(&"cursol")
			close()


func _save() -> void:
	if _board_cb.is_valid():
		var cb: Callable = _board_cb
		var text: String = "\n".join(_lines)
		Audio.play_se(&"cursol")
		## Before `close()`: whoever awaits `closed` should already see the saved text.
		cb.call(text)
		close()
		return
	var inv: Inventory = Game.inventory
	var body: String = "\n".join(_lines)
	var mail := MailData.make_send(
		StringName(str(_recipient.get("id", ""))),
		str(_recipient.get("name", "")),
		body,
		Game.player_name,
		&"player"
	)
	mail.paper_type = _paper_type
	if inv.add_mail(mail) < 0:
		Game.post_notice("Your letter slots are full.")
		close()
		return
	Audio.play_se(&"cursol")
	Game.post_notice("Wrote a letter to %s." % mail.recipient_name)
	close()


func _refresh() -> void:
	if not _open:
		return
	var hb := _is_hboard()
	_board.visible = not hb
	_hboard.visible = hb
	_keyboard.show_ink = true
	_keyboard.ink = clampf(float("".join(_lines).length()) / float(_max_len if _max_len > 0 else 192), 0.0, 1.0)
	if not hb:
		_board.body_lines = _lines
	_keyboard.refresh()
	_marks.queue_redraw()


## `mBD_roll_control`: keep the line being written within two of the centre line;
## the paper chases `(center - 2) * 16`, doubling speed (max 4) while far away.
func _process(_delta: float) -> void:
	if _is_hboard():
		_marks.queue_redraw()
		return
	var line := _lines.size() - 1 + 2
	var dist := line - _center_line
	if dist < -2:
		_center_line = line + 2
		_roll_speed = 1.0
	elif dist > 2:
		_center_line = line - 2
		_roll_speed = 1.0
	var target := float((_center_line - 2) * 16)
	var gap := absf(target - _board.position_y)
	if gap > 0.1:
		if gap > 9.0:
			_roll_speed = minf(_roll_speed * 2.0, 4.0)
		elif gap < 7.0:
			_roll_speed = maxf(_roll_speed * 0.5, 1.0)
		_board.position_y = move_toward(_board.position_y, target, _roll_speed)
	else:
		_board.position_y = target
	_marks.queue_redraw()


## Cursor (`mBD_set_cursol` / `mED_cursol_draw`) and the end mark (`mED_endCode_draw`)
## after the last character; the gyroid board's text is drawn here too.
func _draw_marks() -> void:
	if not _open or _choosing_address:
		return
	var font := _board.font()
	var last := _lines.size() - 1
	var line_w := _board.text_width(_lines[last])
	var top: float
	var x0: float
	if _is_hboard():
		var asc := font.get_ascent(FONT_PX)
		for i in _lines.size():
			if _lines[i] != "":
				_marks.draw_string(font, HBOARD_TEXT + Vector2(0, 16 * i + asc), _lines[i],
					HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX, HBOARD_COLOR)
		x0 = HBOARD_TEXT.x
		top = HBOARD_TEXT.y + 16 * last
	else:
		x0 = LetterBoard.TEXT_X
		top = _board.body_line_top(last)
	if _end_tex != null:
		_marks.draw_texture_rect(_end_tex, Rect2(Vector2(x0 + line_w + 1.0 - 160.0, top - 120.0), Vector2(320, 240)), false)
	var step := int(Time.get_ticks_msec() / 1000.0 * 60.0) % 35
	if step > 17:
		step = 35 - step
	var cursor := CURSOR_COLOR
	cursor.a = float(17 - step) / 17.0
	_marks.draw_rect(Rect2(x0 + line_w, top + 1, 2, 14), cursor)
