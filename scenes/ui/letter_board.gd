class_name LetterBoard
extends Control

## A letter on its stationery, laid out like `m_board_ovl.c` (`mBD_set_frame_dl` +
## `mBD_set_character`) in 320x240 screen units: the paper model baked by `menu_ui.py`,
## the header at (64, 36), six 16-px body lines from (64, 64), and the footer
## right-aligned to x 256 twelve pixels under the body. `position_y` is the board's
## `menu_info->position[1]` (units, up), which `mBD_roll_control` moves while writing.

const PAPER_RECT := Rect2(36, 20, 248, 186)
const TEXT_X := 64.0
const HEADER_Y := 36.0
const BODY_Y := 64.0
const LINE_PITCH := 16.0
const BODY_LINES := 6
## `mBD_MAX_WIDTH`.
const MAX_WIDTH := 192.0
const FONT_PX := 16
## The recipient's name in the header while writing (`mBD_set_writing_header`).
const NAME_COLOR := Color8(185, 0, 0)

var paper_type: int = 0:
	set(v):
		paper_type = LetterChrome.clamp_paper_type(v)
		_paper = LetterChrome.paper_texture(paper_type)
		queue_redraw()
var header: String = "":
	set(v):
		header = v
		queue_redraw()
## Written in red after `header` when set (writing mode).
var header_name: String = "":
	set(v):
		header_name = v
		queue_redraw()
var header_after: String = "":
	set(v):
		header_after = v
		queue_redraw()
var body_lines: PackedStringArray = PackedStringArray():
	set(v):
		body_lines = v
		queue_redraw()
var footer: String = "":
	set(v):
		footer = v
		queue_redraw()
var position_y: float = 0.0:
	set(v):
		position_y = v
		queue_redraw()

var _paper: Texture2D = null
var _font: Font = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = font()


static func load_font() -> Font:
	for path: String in KeyboardPanel.FONT_PATHS:
		if ResourceLoader.exists(path):
			return load(path)
	return ThemeDB.fallback_font


func font() -> Font:
	if _font == null:
		_font = load_font()
	return _font


func ink() -> Color:
	return LetterChrome.ink_color(paper_type)


func text_width(text: String) -> float:
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x


## Break `text` into body lines the way `mBD_strLineCheck` does: at newlines, and at the
## last space before a line would pass `MAX_WIDTH`. At most `BODY_LINES` lines.
func wrap(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for para: String in text.split("\n"):
		var line := ""
		for word: String in para.split(" "):
			var candidate := word if line == "" else line + " " + word
			if line != "" and text_width(candidate) > MAX_WIDTH:
				out.append(line)
				line = word
			else:
				line = candidate
		out.append(line)
	while out.size() > BODY_LINES:
		out.remove_at(out.size() - 1)
	return out


## Top of body line `i` on screen, after the roll.
func body_line_top(i: int) -> float:
	return BODY_Y + LINE_PITCH * i - position_y


func footer_top() -> float:
	return BODY_Y + LINE_PITCH * BODY_LINES + 12.0 - position_y


func _draw() -> void:
	var dy := -position_y
	if _paper != null:
		draw_texture_rect(_paper, Rect2(PAPER_RECT.position + Vector2(0, dy), PAPER_RECT.size), false)
	var col := ink()
	var f := font()
	var asc := f.get_ascent(FONT_PX)
	var x := TEXT_X
	_text(header, Vector2(x, HEADER_Y + dy + asc), col)
	x += text_width(header)
	if header_name != "":
		_text(header_name, Vector2(x, HEADER_Y + dy + asc), NAME_COLOR)
		x += text_width(header_name)
		_text(header_after, Vector2(x, HEADER_Y + dy + asc), col)
	for i in mini(body_lines.size(), BODY_LINES):
		_text(body_lines[i], Vector2(TEXT_X, body_line_top(i) + asc), col)
	_text(footer, Vector2(TEXT_X + MAX_WIDTH - text_width(footer), footer_top() + asc), col)


func _text(s: String, baseline: Vector2, col: Color) -> void:
	if s != "":
		draw_string(font(), baseline, s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX, col)
