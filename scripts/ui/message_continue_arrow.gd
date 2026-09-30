@tool
class_name MessageContinueArrow
extends Control

## `mMsg_DrawWindowTurnButton`: `mFont_MARKTYPE_NEXT` (`FONT_nes_tex_next`) in
## `continue_button_color`, pure blue from `mMsg_init`. `mMsg_Set_display_button_turn_color`
## ramps its alpha 0 → 1 → 0 across `mMsg_BUTTON_TURN_TIME` (60 frames = 1 s), a
## triangle wave and not a hard blink.

const PULSE_FRAMES := 60.0
const ARROW_COLOR := Color8(0, 0, 255)

var _timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visible = false


func restart() -> void:
	_timer = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer = fmod(_timer + delta * DecompTime.TICK_HZ, PULSE_FRAMES)
	queue_redraw()


func _draw() -> void:
	var half := PULSE_FRAMES * 0.5
	var ramp: float = (_timer - half) / half
	var alpha: float = clampf(1.0 + ramp if ramp <= 0.0 else 1.0 - ramp, 0.0, 1.0)
	FontMark.draw(self, FontMark.NEXT, Rect2(Vector2.ZERO, size), Color(ARROW_COLOR, alpha))
