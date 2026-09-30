extends CanvasLayer

## Text entry window (`m_ledit_ovl.c`) over the pad keyboard (`KeyboardPanel`). Opened
## after the editor saves a fresh design (`aNNW_talk_design_open3`) to set
## `design.name` (16-char cap, `mNW_OverWriteOriginalName`), and for album folder
## names.
##
## The window is the purpose's own `*_win_model` baked by `menu_ui.py`; its title and
## the typed text draw at that window's `mLE_win_data` offsets and colours, with the
## blinking red cursor mark (`mED_cursol_draw`, `FontMark.draw_cursor`).
##
## `open(initial, callback, kind)` — callback receives the final name string (unchanged
## `initial` if cancelled).

signal closed

const NAME_LEN := DesignPattern.NAME_LEN
## `mLE_win_data`: window, title, title origin + scale, text origin, text colour.
const WINDOWS := {
	&"player": ["nam", "Enter your name.", Vector2(132, 45), 0.875, Vector2(120, 72), Color8(0, 0, 255)],
	&"catchphrase": ["ephrase", "Enter something!", Vector2(134, 45), 0.875, Vector2(100, 76), Color8(235, 75, 0)],
	&"song": ["req", "Request a song!", Vector2(138, 41), 0.875, Vector2(82, 76), Color8(50, 50, 235)],
	&"design": ["dna", "Enter a name.", Vector2(142, 37), 0.875, Vector2(82, 69), Color8(50, 40, 50)],
}
const FONT_PX := 16

var _open: bool = false
var _text: String = ""
var _kind: StringName = &"design"
var _cb: Callable = Callable()
var _font: Font = null

@onready var _root: Control = $Root
@onready var _screen: Control = $Root/Screen
@onready var _window: TextureRect = $Root/Screen/Window
@onready var _text_view: Control = $Root/Screen/Text
@onready var _keyboard: KeyboardPanel = $Root/Screen/Keyboard


func _ready() -> void:
	layer = 27
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("name_entry_ui")
	_root.visible = false
	_text_view.draw.connect(_draw_text)
	_root.resized.connect(_fit_screen)
	_keyboard.typed.connect(_append)
	_keyboard.erased.connect(_erase)
	for path: String in KeyboardPanel.FONT_PATHS:
		if ResourceLoader.exists(path):
			_font = load(path)
			break
	if _font == null:
		_font = _root.get_theme_default_font()
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


func _process(_delta: float) -> void:
	_text_view.queue_redraw()


func is_open() -> bool:
	return _open


func open(initial: String, callback: Callable = Callable(), kind: StringName = &"design") -> void:
	if _open:
		return
	_text = initial.substr(0, NAME_LEN)
	_cb = callback
	_kind = kind if WINDOWS.has(kind) else &"design"
	var win: Array = WINDOWS[_kind]
	var path := "res://assets/generated/ui/menu/ledit_%s.png" % win[0]
	_window.texture = load(path) if ResourceLoader.exists(path) else null
	_keyboard.mode = KeyboardPanel.InputMode.LETTER
	_keyboard.caps = true
	_keyboard.refresh()
	_open = true
	_root.visible = true
	set_process(true)
	set_process_unhandled_input(true)
	Audio.play_se(&"cursol")


func _finish(cancelled: bool) -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	set_process(false)
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
		KEY_ESCAPE:
			_finish(true)
			return
		KEY_ENTER, KEY_KP_ENTER:
			if not k.shift_pressed:
				## START: done.
				Audio.play_se(&"cursol")
				_finish(false)
				return
	_keyboard.handle_key(k)


func _append(ch: String) -> void:
	if _text.length() >= NAME_LEN:
		Audio.play_se(&"cursol")
		return
	_text += ch
	Audio.play_se(&"cursol")
	_text_view.queue_redraw()


func _erase() -> void:
	if _text.length() > 0:
		_text = _text.substr(0, _text.length() - 1)
		Audio.play_se(&"cursol")
		_text_view.queue_redraw()


## `mLE_set_dl` strings: the title in white, the entry in the window's colour, the
## cursor after the last character.
func _draw_text() -> void:
	if not _open:
		return
	var win: Array = WINDOWS[_kind]
	var title_px := int(round(FONT_PX * float(win[3])))
	var title_pos: Vector2 = win[2]
	_text_view.draw_string(_font, title_pos + Vector2(0, _font.get_ascent(title_px)), win[1],
		HORIZONTAL_ALIGNMENT_LEFT, -1, title_px, Color.WHITE)
	var edit_pos: Vector2 = win[4]
	_text_view.draw_string(_font, edit_pos + Vector2(0, _font.get_ascent(FONT_PX)), _text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX, win[5])
	var x := edit_pos.x + _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x
	FontMark.draw_cursor(_text_view, Vector2(x, edit_pos.y))
