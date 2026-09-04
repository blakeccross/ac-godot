extends CanvasLayer

## Timed full-screen wipe that gates door scene swaps (triforce stand-in).
## `WIPE_TYPE_TRIFORCE` mesh is deferred; timing still covers the field change.

## Rough triforce hold (~0.6 s) before / after the scene load.
const WIPE_SEC := 0.6

var wipe_in_pending: bool = false

var _rect: ColorRect
var _tween: Tween


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.name = "WipeRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_rect = ColorRect.new()
	_rect.name = "Wipe"
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_rect)


func play_wipe_out() -> void:
	wipe_in_pending = true
	await _fade_to(1.0)


func play_wipe_in() -> void:
	wipe_in_pending = false
	await _fade_to(0.0)


func play_wipe_in_if_pending() -> void:
	if not wipe_in_pending:
		return
	## Stay fully opaque through the first indoor draw — otherwise one frame can flash
	## the new room before the fade-in tween starts.
	if _rect != null:
		_rect.color.a = 1.0
	## Fire-and-forget so room spawn / arrive can start immediately under the fade.
	play_wipe_in()


func cancel_wipe() -> void:
	## Enter failed after wipe-out — restore visibility without a scene change.
	wipe_in_pending = false
	if _tween != null:
		_tween.kill()
		_tween = null
	if _rect != null:
		_rect.color.a = 0.0


func _fade_to(alpha: float) -> void:
	if _rect == null:
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_rect, "color:a", alpha, WIPE_SEC)
	await _tween.finished
