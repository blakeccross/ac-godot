class_name MessageContinueArrow
extends Control

## `mFont_MARKTYPE_NEXT` turn mark. `mMsg_Set_display_button_turn_color` ramps the alpha
## 0 → 1 → 0 across `mMsg_BUTTON_TURN_TIME` (60 frames at 30 Hz), so it is a triangle
## wave and not a hard blink.

const PULSE_FRAMES := 60.0
const FRAME_HZ := 30.0

## `continue_button_color` is pure blue in `mMsg_init`; the GC frame reads violet.
const ARROW_COLOR := Color(64.0 / 255.0, 0.0, 192.0 / 255.0)

var _timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func restart() -> void:
	_timer = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer = fmod(_timer + delta * FRAME_HZ, PULSE_FRAMES)
	queue_redraw()


func _draw() -> void:
	var half := PULSE_FRAMES * 0.5
	var ramp: float = (_timer - half) / half
	var alpha: float = clampf(1.0 + ramp if ramp <= 0.0 else 1.0 - ramp, 0.0, 1.0)
	var points := PackedVector2Array(
		[Vector2(0.0, 0.0), Vector2(size.x, 0.0), Vector2(size.x * 0.5, size.y)]
	)
	draw_colored_polygon(points, Color(ARROW_COLOR, alpha))
