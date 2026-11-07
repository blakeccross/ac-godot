class_name MenuFrame
extends RefCounted

## Places a 320×240 menu. Landscape and desktop keep it centred. A portrait phone
## sits it in a bottom sheet with a Close button that runs the
## menu's Escape path.

const CLOSE_SCENE := preload("res://scenes/ui/mobile_close_bar.tscn")
const SCREEN_SIZE := Vector2(320, 240)


static func rect_of(control: Control) -> Rect2:
	if control == null or not is_instance_valid(control):
		return Rect2()
	var xform := control.get_global_transform_with_canvas()
	var size := control.size
	var a := xform * Vector2.ZERO
	var b := xform * Vector2(size.x, 0.0)
	var c := xform * Vector2(0.0, size.y)
	var d := xform * size
	var min_point := a.min(b).min(c).min(d)
	var max_point := a.max(b).max(c).max(d)
	return Rect2(min_point, max_point - min_point)


static func fit(host: MenuOverlay, root: Control, screen: Control) -> void:
	if root == null or screen == null:
		return
	_bind_close(host, root)
	var size := root.size
	if size.x <= 0.0 or size.y <= 0.0:
		size = root.get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var portrait := InputDeviceTracker.uses_mobile_ui()
	var screen_scale := 1.0
	var screen_pos := Vector2.ZERO
	if portrait:
		var home_bar := TouchSafeArea.insets(root.get_viewport()).w
		var bottom := maxf(home_bar, 16.0) + 12.0
		var avail := Vector2(size.x - 24.0, size.y - bottom - 24.0)
		screen_scale = minf(avail.x / SCREEN_SIZE.x, avail.y / SCREEN_SIZE.y)
		screen_scale = maxf(screen_scale, 0.01)
		var visual := SCREEN_SIZE * screen_scale
		screen_pos = Vector2((size.x - visual.x) * 0.5, size.y - bottom - visual.y)
	else:
		screen_scale = minf(size.x / SCREEN_SIZE.x, size.y / SCREEN_SIZE.y)
		screen_pos = (size - SCREEN_SIZE * screen_scale) * 0.5
	screen.scale = Vector2(screen_scale, screen_scale)
	screen.position = screen_pos
	var close := root.get_node_or_null("MobileClose") as Control
	if close == null:
		return
	close.visible = portrait
	close.mouse_filter = Control.MOUSE_FILTER_STOP if portrait else Control.MOUSE_FILTER_IGNORE
	if portrait:
		var fitted := SCREEN_SIZE * screen_scale
		var close_size := close.get_combined_minimum_size()
		close.size = close_size
		close.position = screen_pos + Vector2(fitted.x - close_size.x - 8.0, 8.0)
		close.z_index = 20


static func _bind_close(host: MenuOverlay, root: Control) -> void:
	if host == null:
		return
	var close := root.get_node_or_null("MobileClose") as Button
	if close == null:
		close = CLOSE_SCENE.instantiate() as Button
		close.name = "MobileClose"
		root.add_child(close)
	if bool(close.get_meta("dismiss_bound", false)):
		return
	close.set_meta("dismiss_bound", true)
	close.pressed.connect(host.dismiss)
