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
	if front.menu_rect().has_point(click.global_position):
		return false
	front.dismiss()
	return true


static func front_menu(tree: SceneTree) -> MenuOverlay:
	var best: MenuOverlay = null
	for node: Node in tree.get_nodes_in_group(GROUP):
		if _usable(node) and (best == null or (node as MenuOverlay).layer >= best.layer):
			best = node as MenuOverlay
	return best


static func _usable(node: Node) -> bool:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return false
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return false
	var menu := node as MenuOverlay
	if menu == null or not menu.is_open():
		return false
	var rect: Rect2 = menu.menu_rect()
	return rect.size.x > 1.0 and rect.size.y > 1.0
