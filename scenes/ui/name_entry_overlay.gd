extends CanvasLayer

## Minimal on-screen name entry (`m_ledit_ovl` / `mLE_TYPE_MYORIGINAL_NAME`).
## Opened after the editor saves a fresh design (`aNNW_talk_design_open3`) to set
## `design.name` (16-char cap, `mNW_OverWriteOriginalName`).
##
## `open(initial, callback)` — callback receives the final name string (unchanged
## `initial` if cancelled). Glyph grid + hardware keyboard both work.

signal closed

const NAME_LEN := DesignPattern.NAME_LEN
const ROWS := [
	"ABCDEFGHIJKLM",
	"NOPQRSTUVWXYZ",
	"abcdefghijklm",
	"nopqrstuvwxyz",
	"0123456789 -.",
]

var _open: bool = false
var _text: String = ""
var _row: int = 0
var _col: int = 0
var _cb: Callable = Callable()

@onready var _root: Control = $Root
@onready var _entry: Label = $Root/Frame/Box/Entry
@onready var _grid: Control = $Root/Frame/Box/Grid
@onready var _hint: Label = $Root/Frame/Box/Hint


func _ready() -> void:
	layer = 27
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("name_entry_ui")
	_root.visible = false
	_grid.draw.connect(_draw_grid)
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _open


func open(initial: String, callback: Callable = Callable()) -> void:
	if _open:
		return
	_text = initial.substr(0, NAME_LEN)
	_cb = callback
	_row = 0
	_col = 0
	_open = true
	_root.visible = true
	set_process_unhandled_input(true)
	Audio.play_se(&"cursol")
	_refresh()


func _finish(cancelled: bool) -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	set_process_unhandled_input(false)
	var result := _text.strip_edges()
	if cancelled or result.is_empty():
		result = _text if not _text.strip_edges().is_empty() else "design"
	var cb := _cb
	_cb = Callable()
	closed.emit()
	if cb.is_valid():
		cb.call(result.substr(0, NAME_LEN))


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	var k := event as InputEventKey
	match k.keycode:
		KEY_LEFT: _col = wrapi(_col - 1, 0, ROWS[_row].length())
		KEY_RIGHT: _col = wrapi(_col + 1, 0, ROWS[_row].length())
		KEY_UP: _row = wrapi(_row - 1, 0, ROWS.size()); _col = mini(_col, ROWS[_row].length() - 1)
		KEY_DOWN: _row = wrapi(_row + 1, 0, ROWS.size()); _col = mini(_col, ROWS[_row].length() - 1)
		KEY_SPACE:
			_append(ROWS[_row][_col])
		KEY_BACKSPACE:
			if _text.length() > 0:
				_text = _text.substr(0, _text.length() - 1)
				Audio.play_se(&"cursol")
		KEY_ENTER, KEY_KP_ENTER:
			Audio.play_se(&"cursol")
			_finish(false)
			return
		KEY_ESCAPE:
			_finish(true)
			return
		_:
			var ch := char(k.unicode)
			if k.unicode >= 32 and k.unicode < 127:
				_append(ch)
	_refresh()


func _append(ch: String) -> void:
	if _text.length() >= NAME_LEN:
		Audio.play_se(&"cursol")
		return
	_text += ch
	Audio.play_se(&"cursol")


func _refresh() -> void:
	if not _open:
		return
	_entry.text = "%s%s" % [_text, "_" if _text.length() < NAME_LEN else ""]
	_hint.text = "arrows + space to type  ·  Backspace delete  ·  Enter done  (%d/%d)" % [_text.length(), NAME_LEN]
	_grid.queue_redraw()


func _draw_grid() -> void:
	var font := _grid.get_theme_default_font()
	var cw := _grid.size.x / 13.0
	var chh := _grid.size.y / float(ROWS.size())
	for r in ROWS.size():
		var row: String = ROWS[r]
		for c in row.length():
			var cell := Rect2(c * cw, r * chh, cw - 2, chh - 2)
			if r == _row and c == _col:
				_grid.draw_rect(cell, Color(1, 0.85, 0.3, 1))
			else:
				_grid.draw_rect(cell, Color(1, 1, 1, 0.7))
			_grid.draw_string(font, cell.position + Vector2(cw * 0.5 - 4, chh * 0.6), row[c],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.2, 0.15, 0.1))
