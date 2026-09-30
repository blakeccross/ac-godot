class_name FontMark
extends RefCounted

## `mFont_SetMarkChar`: the 16x16 I4 marks from `FONT_nes_tex_*`, baked white+alpha by
## `message_ui.py` (`msg_mark_*.png`, ACHD-sized when the pack has them). The game draws
## them with `mFont_CC_FONT` (colour PRIM, alpha PRIM x TEXEL0), so a modulate is exact.

const NEXT := &"next"
const CHOICE := &"choice"
const CURSOR := &"cursor"
const SIZE := Vector2(16.0, 16.0)
const TEX := "res://assets/generated/ui/message/msg_mark_%s.png"
## `mED_cursol_draw` colour; `mED_cursol_draw` callers place the mark 7 px left of the
## text end so its bar (texels 6-8) straddles the caret position.
const CURSOR_COLOR := Color8(195, 80, 80)
const CURSOR_X_OFFSET := -7.0

static var _cache: Dictionary = {}


static func texture(kind: StringName) -> Texture2D:
	if not _cache.has(kind):
		var path := TEX % kind
		_cache[kind] = load(path) if ResourceLoader.exists(path) else null
	return _cache[kind]


## Draw mark `kind` on `canvas` with its 16x16 cell at `rect` (or a plain rect if the
## generated texture is missing).
static func draw(canvas: CanvasItem, kind: StringName, rect: Rect2, color: Color) -> void:
	var tex := texture(kind)
	if tex != null:
		canvas.draw_texture_rect(tex, rect, false, color)
	else:
		canvas.draw_rect(Rect2(rect.position + rect.size * Vector2(0.375, 0.0625),
			rect.size * Vector2(0.1875, 0.9375)), color)


## `mED_cursol_draw`: fades over a 35-frame cycle; `caret` is the text end at the top
## of the line.
static func draw_cursor(canvas: CanvasItem, caret: Vector2) -> void:
	var step := int(Time.get_ticks_msec() / 1000.0 * 60.0) % 35
	if step > 17:
		step = 35 - step
	var col := CURSOR_COLOR
	col.a = float(17 - step) / 17.0
	draw(canvas, CURSOR, Rect2(caret + Vector2(CURSOR_X_OFFSET, 0.0), SIZE), col)
