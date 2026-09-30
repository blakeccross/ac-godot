@tool
class_name MessageChoiceMark
extends Control

## `mFont_MARKTYPE_CHOICE` (`FONT_nes_tex_choice`) left of the selected option;
## `mChoice_DrawFont` tints it with `background_color` (0, 195, 185).

const MARK_COLOR := Color8(0, 195, 185)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	FontMark.draw(self, FontMark.CHOICE, Rect2(Vector2.ZERO, size), MARK_COLOR)
