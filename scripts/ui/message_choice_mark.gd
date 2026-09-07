@tool
class_name MessageChoiceMark
extends Control

## `mFont_MARKTYPE_CHOICE` — cyan triangle left of the selected option
## (`mChoice_DrawFont` uses `background_color` (0, 195, 185)).

const MARK_COLOR := Color(0.0, 195.0 / 255.0, 185.0 / 255.0, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	## Right-pointing wedge in the 16×16 mark cell.
	var points := PackedVector2Array(
		[
			Vector2(size.x * 0.15, size.y * 0.2),
			Vector2(size.x * 0.85, size.y * 0.5),
			Vector2(size.x * 0.15, size.y * 0.8),
		]
	)
	draw_colored_polygon(points, MARK_COLOR)
