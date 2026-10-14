class_name KeyboardPanel
extends Control

## The GameCube-pad keyboard (`m_editor_ovl.c`, `mED_KeyDraw` / `mED_StringsDraw`).
## Lives in 320x240 screen units (place it in a screen-sized parent). The pad body,
## the L shoulder (Caps / small / none) and the Y mode block are layers baked by
## `menu_ui.py`; the 10x4 key caps, their characters, the character shown on the A
## button and the SP glyph are drawn here, like the C code draws them.
##
## Keys (pad → keyboard): printable keys, Space included, type directly (R is the
## space key); arrows move the highlight and Shift+Enter or a click types the
## highlighted key (A); Backspace = B; Tab = Y (letters / punctuation / icons);
## Caps Lock = L. Enter and Escape are left to the owner (START / newline).

signal typed(ch: String)
signal erased

enum InputMode { LETTER, SIGN, MARK }

const COLUMNS := 10
const ROWS := 4
## `mED_get_code` tables (QWERTY `arrange`), converted to Unicode; "" = no key.
const LETTER_LOWER := ["!", "?", "\"", "-", "~", "ー", "'", ";", ":", "⚷",
	"q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
	"a", "s", "d", "f", "g", "h", "j", "k", "l", "",
	"z", "x", "c", "v", "b", "n", "m", ",", ".", " "]
const LETTER_UPPER := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
	"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
	"A", "S", "D", "F", "G", "H", "J", "K", "L", "",
	"Z", "X", "C", "V", "B", "N", "M", ",", ".", " "]
const SIGN := ["#", "?", "\"", "-", "~", "ー", "•", ";", ":", "Æ",
	"%", "&", "@", "_", "¯", "/", "¦", "×", "➗", "=",
	"(", ")", "<", ">", "»", "«", "∋", "∈", "+", "",
	"ß", "Þ", "ð", "§", "‖", "µ", "¬", ",", ".", " "]
const MARK := ["♥", "★", "♪", "🌢", "💢", "🍀", "🐾", "♂", "♀", "∞",
	"○", "🗙", "□", "△", "💀", "😮", "😄", "😣", "😠", "😃",
	"☀", "☁", "☂", "☃", "🌬", "⚡", "🔨", "🎀", "✉", "",
	"🐶", "🐱", "🐰", "🐦", "🐮", "🐷", "💰", "🐟", "🐞", " "]

## `mED_StringsDraw_keyboard` offsets (screen px, top-left origin).
const KEY_X0 := 60.0
const KEY_Y0 := 133.0
const KEY_PITCH := 16.0
const ROW_SLIDE := [0.0, 3.0, 7.0, 10.0]
const TEXT_COLOR := Color8(35, 30, 55)
const TEXT_SELECTED := Color.WHITE
## `sel_col`: red, blue while typing capitals.
const KEY_SELECTED := Color8(205, 0, 0)
const KEY_SELECTED_CAPS := Color8(0, 0, 205)
## `mED_StringsDraw_select`: the key's character on the A button.
const A_BUTTON_TEXT := Vector2(242.0, 180.0)
const FONT_PX := 16
const TEX_DIR := "res://assets/generated/ui/menu/%s.png"
const FONT_PATHS := ["res://assets/generated/ui/message/msg_font.fnt", "res://assets/custom/ui/message/msg_font.fnt"]

@export var show_ink: bool = false

var mode: int = InputMode.LETTER
var caps: bool = false
var col: int = 0
var row: int = 1
## `mED_InkPotDraw`: 0-1 share of the text used.
var ink: float = 0.0

var _font: Font = null
var _key_tex: Texture2D = null
var _space_tex: Texture2D = null

@onready var _l: TextureRect = $L
@onready var _body: TextureRect = $Body
@onready var _y: TextureRect = $Y
@onready var _ink: TextureRect = $Ink
@onready var _keys: Control = $Keys


func _ready() -> void:
	_body.texture = _tex("kb_body")
	_ink.texture = _tex("kb_ink")
	_key_tex = _tex("kb_key")
	_space_tex = _tex("kb_space")
	for path: String in FONT_PATHS:
		if ResourceLoader.exists(path):
			_font = load(path)
			break
	if _font == null:
		_font = get_theme_default_font()
	_keys.draw.connect(_draw_keys)
	refresh()


func _tex(name: String) -> Texture2D:
	var path := TEX_DIR % name
	return load(path) if ResourceLoader.exists(path) else null


func table() -> Array:
	match mode:
		InputMode.SIGN: return SIGN
		InputMode.MARK: return MARK
	return LETTER_UPPER if caps else LETTER_LOWER


func key_at(c: int, r: int) -> String:
	return table()[r * COLUMNS + c]


func refresh() -> void:
	if not is_node_ready():
		return
	if mode == InputMode.LETTER:
		_l.texture = _tex("kb_l_small" if caps else "kb_l_caps")
	else:
		_l.texture = _tex("kb_l_none")
	_y.texture = _tex("kb_y%d" % mode)
	_ink.visible = show_ink
	_keys.queue_redraw()


## Handle a key press; true if the keyboard used it.
func handle_key(k: InputEventKey) -> bool:
	match k.keycode:
		KEY_LEFT: _move(-1, 0)
		KEY_RIGHT: _move(1, 0)
		KEY_UP: _move(0, -1)
		KEY_DOWN: _move(0, 1)
		KEY_ENTER, KEY_KP_ENTER:
			if not k.shift_pressed:
				return false
			var ch := key_at(col, row)
			if ch != "":
				typed.emit(ch)
		KEY_BACKSPACE:
			erased.emit()
		KEY_TAB:
			mode = wrapi(mode + 1, 0, 3)
			Audio.play_se(&"cursol")
		KEY_CAPSLOCK:
			if mode == InputMode.LETTER:
				caps = not caps
				Audio.play_se(&"cursol")
		_:
			if k.unicode >= 32:
				typed.emit(char(k.unicode))
			else:
				return false
	refresh()
	return true


func _move(dx: int, dy: int) -> void:
	col = wrapi(col + dx, 0, COLUMNS)
	row = wrapi(row + dy, 0, ROWS)
	Audio.play_se(&"cursol")


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for r in ROWS:
		for c in COLUMNS:
			if _key_rect(c, r).has_point(mb.position) and key_at(c, r) != "":
				col = c
				row = r
				typed.emit(key_at(c, r))
				refresh()
				accept_event()
				return


func _key_rect(c: int, r: int) -> Rect2:
	return Rect2(KEY_X0 + KEY_PITCH * c + float(ROW_SLIDE[r]), KEY_Y0 + KEY_PITCH * r, KEY_PITCH, KEY_PITCH)


func _draw_keys() -> void:
	var sel_key := KEY_SELECTED_CAPS if (mode == InputMode.LETTER and caps) else KEY_SELECTED
	var key_src := Rect2(0, 0, 32, 32)
	if _key_tex != null:
		key_src = Rect2(Vector2.ZERO, _key_tex.get_size() * 2.0)
	for r in ROWS:
		for c in COLUMNS:
			var rect := _key_rect(c, r)
			var selected := c == col and r == row
			if _key_tex != null:
				_keys.draw_texture_rect_region(_key_tex, rect, key_src, sel_key if selected else Color.WHITE)
			var ch := key_at(c, r)
			if ch == "":
				continue
			var ink_col := TEXT_SELECTED if selected else TEXT_COLOR
			_draw_char(ch, rect.position + Vector2(2, 0), ink_col)
	var cur := key_at(col, row)
	if cur != "":
		_draw_char(cur, A_BUTTON_TEXT, TEXT_SELECTED)


## One key face at `top_left` (the glyph's top-left, like `mFont_SetLineStrings`).
func _draw_char(ch: String, top_left: Vector2, color: Color) -> void:
	if ch == " ":
		## `mED_StringsDraw_spaceCode`: the SP plate, 0.75 wide, centred on the key.
		if _space_tex != null:
			var size := Vector2(12, 16)
			var center := top_left + Vector2(6.5, 8.5)
			_keys.draw_texture_rect(_space_tex, Rect2(center - size * 0.5, size), false, color)
		return
	var baseline := top_left + Vector2(0, _font.get_ascent(FONT_PX))
	_keys.draw_string(_font, baseline, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX, color)
