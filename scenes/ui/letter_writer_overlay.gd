extends CanvasLayer

## The letter composition board (`m_board_ovl.c` WRITE mode + `m_editor_ovl.c`'s
## character-grid keyboard, `mED_TYPE_BOARD`). Step 3 of writing: recipient
## (`letter_address_overlay`) and paper (`letter_paper_picker_overlay`) are already
## chosen by the time this opens.
##
## Header ("Dear <name>,") and footer (the player's name) are auto-filled and not
## separately editable — decomp technically allows editing them too, but essentially no
## player customizes those, and making only the body editable is a documented,
## approved simplification that keeps the editor to one text region instead of three.
##
## Body cap matches decomp exactly: 6 lines (`mBD_BODY_LINE_NUM`), each capped to the
## paper's text-box pixel width (`mBD_MAX_WIDTH` 192px equivalent) rather than a
## character count, auto-wrapping into the next line — same measured-width approach
## `mBD_strLineCheck` uses, just against Godot's own font metrics instead of the N64
## font's.
##
## Finishing (Escape) opens a Save / Keep editing / Discard prompt, matching decomp's
## `mSM_OVL_EDITENDCHK`/`mEE_TYPE_BOARD` (same 3-choice shape already used by
## `design_editor_overlay.gd`'s save prompt).

signal closed

const MAX_LINES := 6
## `mED_TYPE_HBOARD` (`m_hboard_ovl`): the house gyroid's visitor message — 4 lines of the same
## 192 px width, 128 characters, no header / footer, edited in place.
const HBOARD_LINES := 4
const HBOARD_LEN := 128
const ROWS := [
	"ABCDEFGHIJKLM",
	"NOPQRSTUVWXYZ",
	"abcdefghijklm",
	"nopqrstuvwxyz",
	"0123456789 ,.!?'-",
]

var _open: bool = false
var _recipient: Dictionary = {}
var _paper_type: int = 0
var _lines: PackedStringArray = PackedStringArray([""])
var _row: int = 0
var _col: int = 0
var _prompt: bool = false
var _prompt_idx: int = 0
## Board mode: `_max_lines` / `_max_len` caps and the callback that receives the text on
## Save (never called on Discard). Letter mode leaves `_board_cb` invalid.
var _max_lines: int = MAX_LINES
var _max_len: int = -1
var _board_cb: Callable = Callable()

@onready var _root: Control = $Root
@onready var _paper: TextureRect = %Paper
@onready var _header: Label = %Header
@onready var _body: Label = %Body
@onready var _footer: Label = %Footer
@onready var _keyboard: Control = $Root/Frame/Box/Keyboard
@onready var _hint: Label = $Root/Frame/Box/Hint
@onready var _promptbox: PanelContainer = $Root/Prompt
@onready var _prompt_options: Label = $Root/Prompt/V/Options


func _ready() -> void:
	layer = 27
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("letter_writer_ui")
	_root.visible = false
	_keyboard.draw.connect(_draw_keyboard)
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _open


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
	_header.visible = false
	_footer.visible = false
	_refresh()


func open(recipient: Dictionary, paper_type: int) -> void:
	if _open:
		return
	_max_lines = MAX_LINES
	_max_len = -1
	_board_cb = Callable()
	_header.visible = true
	_footer.visible = true
	_recipient = recipient
	_paper_type = LetterChrome.clamp_paper_type(paper_type)
	_lines = PackedStringArray([""])
	_row = 0
	_col = 0
	_prompt = false
	_open = true
	_root.visible = true
	set_process_unhandled_input(true)

	_paper.texture = LetterChrome.paper_texture(_paper_type)
	var ink: Color = LetterChrome.ink_color(_paper_type)
	_header.add_theme_color_override("font_color", ink)
	_body.add_theme_color_override("font_color", ink)
	_footer.add_theme_color_override("font_color", ink)
	_header.text = "Dear %s," % str(_recipient.get("name", "Friend"))
	_footer.text = Game.player_name if Game != null else ""

	Audio.play_se(&"cursol")
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	set_process_unhandled_input(false)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	var k := event as InputEventKey
	if k.echo and k.keycode not in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_BACKSPACE]:
		return

	if _prompt:
		_prompt_key(k.keycode)
		return

	match k.keycode:
		KEY_LEFT: _col = wrapi(_col - 1, 0, ROWS[_row].length())
		KEY_RIGHT: _col = wrapi(_col + 1, 0, ROWS[_row].length())
		KEY_UP: _row = wrapi(_row - 1, 0, ROWS.size()); _col = mini(_col, ROWS[_row].length() - 1)
		KEY_DOWN: _row = wrapi(_row + 1, 0, ROWS.size()); _col = mini(_col, ROWS[_row].length() - 1)
		KEY_SPACE:
			_type(ROWS[_row][_col])
			return
		KEY_ENTER, KEY_KP_ENTER:
			_newline()
			return
		KEY_BACKSPACE:
			_backspace()
			return
		KEY_ESCAPE:
			_open_prompt()
			return
		_:
			var ch := char(k.unicode)
			if k.unicode >= 32 and k.unicode < 127:
				_type(ch)
				return
	_refresh()


## Auto-wraps into the next line when `ch` would push the current line past the body
## box's measured pixel width (`mBD_strLineCheck`'s 192px cap, against real font metrics
## here instead of the N64 font's).
func _type(ch: String) -> void:
	if _max_len > 0 and "\n".join(_lines).length() >= _max_len:
		Audio.play_se(&"cursol")
		return
	var line: String = _lines[_lines.size() - 1]
	var font: Font = _body.get_theme_font("font")
	var fs: int = _body.get_theme_font_size("font_size")
	var max_w: float = maxf(_body.size.x, 1.0)
	var candidate: String = line + ch
	if font != null and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
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
	_prompt_idx = 0
	_promptbox.visible = true
	Audio.play_se(&"cursol")
	_refresh()


func _prompt_key(keycode: int) -> void:
	match keycode:
		KEY_LEFT, KEY_UP:
			_prompt_idx = wrapi(_prompt_idx - 1, 0, 3)
			Audio.play_se(&"cursol")
			_refresh()
		KEY_RIGHT, KEY_DOWN:
			_prompt_idx = wrapi(_prompt_idx + 1, 0, 3)
			Audio.play_se(&"cursol")
			_refresh()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_resolve_prompt(_prompt_idx)
		KEY_ESCAPE, KEY_B:
			_prompt = false
			_promptbox.visible = false
			_refresh()


## 0 Save, 1 Keep editing, 2 Discard — `mSM_OVL_EDITENDCHK`/`mEE_TYPE_BOARD`.
func _resolve_prompt(idx: int) -> void:
	match idx:
		0:
			_save()
		1:
			_prompt = false
			_promptbox.visible = false
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
	_body.text = "\n".join(_lines)
	_hint.text = "arrows move  ·  space type  ·  enter new line  ·  backspace delete  ·  esc finish"
	_promptbox.visible = _prompt
	if _prompt:
		var opts := ["Save it", "Keep editing", "Throw it out"]
		_prompt_options.text = "   ".join(range(3).map(func(i: int) -> String: return ("▶ " if i == _prompt_idx else "  ") + opts[i]))
	_keyboard.queue_redraw()


func _draw_keyboard() -> void:
	var font := _keyboard.get_theme_default_font()
	var cw := _keyboard.size.x / 13.0
	var chh := _keyboard.size.y / float(ROWS.size())
	for r in ROWS.size():
		var row: String = ROWS[r]
		for c in row.length():
			var cell := Rect2(c * cw, r * chh, cw - 2, chh - 2)
			_keyboard.draw_rect(cell, Color(1, 0.85, 0.3, 1) if r == _row and c == _col else Color(1, 1, 1, 0.7))
			_keyboard.draw_string(font, cell.position + Vector2(cw * 0.5 - 4, chh * 0.65), row[c],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.2, 0.15, 0.1))
