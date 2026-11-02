class_name WindowDismiss
extends RefCounted

## Desktop and landscape: a left click that misses the front menu's window runs the
## same path as Escape. Portrait mobile sheets keep their own Close button, and a tap
## on the world above the sheet does not dismiss it.

const GROUP := &"menu_frame"


static func escape_key() -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	key.echo = false
	return key


## True when the click dismissed the front window. `allow` is false for the portrait
## mobile sheets, which keep their own Close button.
static func handle(tree: SceneTree, event: InputEvent, allow: bool = true) -> bool:
	if tree == null or not allow:
		return false
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return false
	var front := front_menu(tree)
	if front == null:
		return false
	var rect: Rect2 = front.call("menu_rect")
	if rect.has_point(click.global_position):
		return false
	front.call("dismiss")
	return true


static func front_menu(tree: SceneTree) -> Node:
	var best: Node = null
	var best_layer := -100000
	for node: Node in tree.get_nodes_in_group(GROUP):
		if not _usable(node):
			continue
		var canvas := node as CanvasLayer
		var layer := canvas.layer if canvas != null else 0
		if best == null or layer >= best_layer:
			best = node
			best_layer = layer
	return best


static func _usable(node: Node) -> bool:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return false
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return false
	if not node.has_method(&"is_open") or not bool(node.call(&"is_open")):
		return false
	if not node.has_method(&"menu_rect") or not node.has_method(&"dismiss"):
		return false
	var rect: Rect2 = node.call(&"menu_rect")
	return rect.size.x > 1.0 and rect.size.y > 1.0
