class_name TouchSafeArea
extends RefCounted

## Keeps touch controls off a phone's notch and home bar: how far in from each edge of
## the window the display's safe area starts, in the viewport's own units. Zero on a
## desktop, where the "safe area" is just the space round the taskbar.


## Left, top, right, bottom insets for `vp`.
static func insets(vp: Viewport) -> Vector4:
	if vp == null or not OS.has_feature("mobile"):
		return Vector4.ZERO
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var win_pos := Vector2(DisplayServer.window_get_position())
	var win_size := Vector2(DisplayServer.window_get_size())
	if safe.size.x <= 0.0 or win_size.x <= 0.0 or win_size.y <= 0.0:
		return Vector4.ZERO
	var scale: Vector2 = vp.get_visible_rect().size / win_size
	var left: float = maxf(safe.position.x - win_pos.x, 0.0)
	var top: float = maxf(safe.position.y - win_pos.y, 0.0)
	var right: float = maxf(win_pos.x + win_size.x - safe.end.x, 0.0)
	var bottom: float = maxf(win_pos.y + win_size.y - safe.end.y, 0.0)
	return Vector4(left * scale.x, top * scale.y, right * scale.x, bottom * scale.y)


## Pull a full-rect `root` in by the insets (and again whenever the window changes).
static func fit(root: Control) -> void:
	var vp: Viewport = root.get_viewport()
	var apply := func() -> void:
		var inset: Vector4 = insets(vp)
		root.offset_left = inset.x
		root.offset_top = inset.y
		root.offset_right = -inset.z
		root.offset_bottom = -inset.w
	apply.call()
	if vp == null:
		return
	vp.size_changed.connect(apply)
	## The lambda captures `root`; drop it with the node or the next resize calls into a freed one.
	root.tree_exiting.connect(
		func() -> void:
			if vp.size_changed.is_connected(apply):
				vp.size_changed.disconnect(apply),
		CONNECT_ONE_SHOT
	)
