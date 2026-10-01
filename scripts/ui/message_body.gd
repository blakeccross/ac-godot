@tool
class_name MessageBody
extends Control

## The talk window's text, laid out like `mFontSentence` (`m_font_main.c_inc`) instead of
## a RichTextLabel: 16-unit lines that never grow, each glyph scaled about its line
## type's pivot (`mFontSentence_line_offset_calc`: top / centre / bottom of the 16-unit
## cell, so a big glyph on a Top line hangs down rather than pushing the line), advances
## scaled with the glyph, and LINEOFS lowering the rest of the page.
##
## Markup from the dialogue converter:
## - `{c:r,g,b}` colour, `{s:n}` scale n/32, `{y:n}` offset, `{lt:n}` line type
## - `{p:n}` pause, `{se:n}` sound, `{just}` / `{unjust}`, `{btn}` (wait for A): timing marks for the
##   typewriter, reported by `marks()` against the glyph they precede.

const CELL := 16.0
const SCALE_UNIT := 32.0
const DEFAULT_COLOR := Color8(50, 60, 50)
const TAG_RE := "\\{(c|s|y|lt|p|se|just|unjust|cap|btn)(?::(-?[0-9,]+))?\\}"
## `mFont_LineType_*` pivots within the 16-unit cell.
const LINE_PIVOT := [0.0, 8.0, 16.0]

@export var font: Font
## Screen pixels per 320x240 unit (the chrome's ui scale x the window scale).
@export var units_px: float = 1.0:
	set(v):
		units_px = maxf(v, 0.001)
		queue_redraw()
@export var default_color: Color = DEFAULT_COLOR

var visible_characters: int = -1:
	set(v):
		visible_characters = v
		queue_redraw()

## {ch, x, line, color, scale, y, pivot} in units.
var _glyphs: Array[Dictionary] = []
## {at: glyph index, kind: "p"/"se"/"just"/"unjust", value: int}
var _marks: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func strip_tags(text: String) -> String:
	var re := RegEx.new()
	re.compile(TAG_RE)
	return re.sub(text, "", true)


func set_text(text: String) -> void:
	_glyphs.clear()
	_marks.clear()
	var re := RegEx.new()
	re.compile(TAG_RE)
	var color := default_color
	var scale := 1.0
	var y_ofs := 0.0
	var pivot := 0.0
	var x := 0.0
	var line := 0
	var i := 0
	while i <= text.length():
		var m: RegExMatch = re.search(text, i)
		var end: int = m.get_start() if m != null else text.length()
		for k: int in range(i, end):
			var ch: String = text[k]
			if ch == "\n":
				line += 1
				x = 0.0
				continue
			var adv := advance(ch) * scale
			_glyphs.append({"ch": ch, "x": x, "line": line, "color": color, "scale": scale, "y": y_ofs,
				"pivot": pivot})
			x += adv
		if m == null:
			break
		var arg: String = m.get_string(2)
		match m.get_string(1):
			"c":
				var rgb := arg.split(",")
				if rgb.size() >= 3:
					color = Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
			"s":
				scale = maxf(1.0, float(arg)) / SCALE_UNIT
			"y":
				y_ofs = float(arg)
			"lt":
				pivot = float(LINE_PIVOT[clampi(int(arg), 0, LINE_PIVOT.size() - 1)])
			"p", "se":
				_marks.append({"at": _glyphs.size(), "kind": m.get_string(1), "value": int(arg)})
			"just", "unjust", "btn":
				_marks.append({"at": _glyphs.size(), "kind": m.get_string(1), "value": 0})
		i = m.get_end()
	queue_redraw()


func glyph_count() -> int:
	return _glyphs.size()


func marks() -> Array[Dictionary]:
	return _marks


## The glyph's advance at scale 1, in units (the font is 16 px per cell).
func advance(ch: String) -> float:
	if font == null:
		return 8.0
	return font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, int(CELL)).x


func glyph_text() -> String:
	var out := ""
	for g: Dictionary in _glyphs:
		out += str(g["ch"])
	return out


func _draw() -> void:
	if font == null:
		return
	var shown: int = _glyphs.size() if visible_characters < 0 else mini(visible_characters, _glyphs.size())
	for i: int in shown:
		var g: Dictionary = _glyphs[i]
		var s: float = g["scale"]
		var px: int = maxi(1, int(round(CELL * s * units_px)))
		## `mFontChar_gppDrawRect`: top = pivot - pivot * s, so the glyph grows away from it.
		var pivot: float = g["pivot"]
		var top: float = CELL * int(g["line"]) + float(g["y"]) + pivot - pivot * s
		var pos := Vector2(float(g["x"]), top) * units_px
		pos.y += font.get_ascent(px)
		draw_char(font, pos, str(g["ch"]), px, g["color"])
