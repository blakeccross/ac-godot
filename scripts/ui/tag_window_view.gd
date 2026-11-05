class_name TagWindowView
extends Control

## Draws one `TagLayout.Tag` the way `mTG_set_win_field` does: shadow, arrow, window, then its
## text and the magenta cursor, all hung from the tag's base point and grown from it by
## `tag.scale` (`Matrix_scale(tag->scale)`). Positions are screen units about the screen
## centre (y up); `px_per_unit` turns them into the shell stack's pixels.

const FONT_UNITS := 16.0
## The font's cell is 16 units; text is drawn at 0.875 of that (`mTG_set_select`).
const TEXT_SCALE := 0.875

var px_per_unit: float = 3.12
var font: Font = null

var _root := Node2D.new()
var _shadow := Sprite2D.new()
var _arrow := Sprite2D.new()
var _frame := Sprite2D.new()
var _cursor := Sprite2D.new()
var _rows: Array[Label] = []
var _frame_node := Node2D.new()
var _shadow_node := Node2D.new()
var _text_root := Node2D.new()
var _centre := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_child(_root)
	_root.add_child(_shadow_node)
	_shadow_node.add_child(_shadow)
	_root.add_child(_arrow)
	_root.add_child(_frame_node)
	_frame_node.add_child(_frame)
	_root.add_child(_text_root)
	_root.add_child(_cursor)
	for sprite: Sprite2D in [_shadow, _arrow, _frame, _cursor]:
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_shadow.self_modulate = Color(1, 1, 1, 0.5)


## Screen units about the centre (y up) to pixels in this view's space.
func to_px(units: Vector2) -> Vector2:
	return _centre + Vector2(units.x, -units.y) * px_per_unit


func set_centre(stack_size: Vector2) -> void:
	_centre = stack_size * 0.5


## `models`: stems of the baked sprites ("frame", "shadow", "arrow", "cursor"; arrow and
## cursor may be empty). `rows`: one string per verb / the name.
func show_tag(
	tag: TagLayout.Tag,
	models: Dictionary,
	rows: PackedStringArray,
	colors: Array[Color],
	cursor_row: int
) -> void:
	_root.position = to_px(tag.base)
	_root.scale = Vector2.ONE
	_place_model(_frame, str(models.get("frame", "")))
	_place_model(_shadow, str(models.get("shadow", "")))
	var window_scale: Vector2 = tag.body_scale * tag.model_scale
	_frame_node.position = Vector2(tag.body_ofs.x, -tag.body_ofs.y) * px_per_unit
	_frame_node.scale = window_scale
	_shadow_node.position = _frame_node.position
	_shadow_node.scale = window_scale
	var arrow_stem: String = str(models.get("arrow", ""))
	_arrow.visible = tag.arrow_dir != 0 and arrow_stem != ""
	if _arrow.visible:
		_place_model(_arrow, arrow_stem)
	var cursor_stem: String = str(models.get("cursor", ""))
	_cursor.visible = cursor_stem != "" and cursor_row >= 0
	if _cursor.visible:
		_place_model(_cursor, cursor_stem)
		var at := Vector2(
			tag.text_ofs.x + (tag.model_scale * -4.0 + tag.body_ofs.x),
			(tag.text_ofs.y + (tag.model_scale * -8.0 + tag.body_ofs.y)) - float(cursor_row) * TagLayout.TEXT_LINE_HEIGHT * tag.model_scale,
		)
		_cursor.position = Vector2(at.x, -at.y) * px_per_unit + _cursor.position
	_set_rows(tag, rows, colors)
	visible = true


func set_open_scale(amount: float) -> void:
	_root.scale = Vector2.ONE * maxf(amount, 0.0001)


func _place_model(sprite: Sprite2D, stem: String) -> void:
	var tex: Texture2D = InventoryChrome.load_tex(stem)
	sprite.texture = tex
	if tex == null:
		return
	var bounds: Rect2 = InventoryChrome.tag_model(stem)
	if bounds.size == Vector2.ZERO:
		return
	sprite.position = Vector2(bounds.position.x, -bounds.position.y) * px_per_unit
	sprite.scale = Vector2(bounds.size.x * px_per_unit / tex.get_width(), bounds.size.y * px_per_unit / tex.get_height())


func _set_rows(tag: TagLayout.Tag, rows: PackedStringArray, colors: Array[Color]) -> void:
	while _rows.size() < rows.size():
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_constant_override("line_spacing", 0)
		_text_root.add_child(label)
		_rows.append(label)
	var size_px: int = roundi(FONT_UNITS * TEXT_SCALE * px_per_unit)
	var origin := Vector2(tag.body_ofs.x + tag.text_ofs.x, -(tag.body_ofs.y + tag.text_ofs.y)) * px_per_unit
	for i: int in _rows.size():
		var label: Label = _rows[i]
		label.visible = i < rows.size()
		if i >= rows.size():
			continue
		if font != null:
			label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", size_px)
		label.add_theme_color_override("font_color", colors[mini(i, colors.size() - 1)])
		label.text = rows[i]
		label.size = Vector2.ZERO
		label.position = origin + Vector2(0.0, float(i) * FONT_UNITS * TEXT_SCALE * px_per_unit)
