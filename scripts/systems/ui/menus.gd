class_name Menus
extends RefCounted

## Whether a menu is up, by its group (`inventory_ui`, `shop_ui`, `map_ui`, …). Menus are
## different classes (`CanvasLayer`s, `Control`s) with no common base, and a group such as
## `shop_ui` holds several of them, so this is the one place that asks each for `is_open()`
## by name. Code that knows the one overlay it wants uses that class's `find` instead.

## The groups that count as "a menu is open" for the player, the HUD and the touch pads.
const ALL: Array[StringName] = [
	&"inventory_ui", &"map_ui", &"dialogue_ui", &"shop_ui", &"debug_console_ui",
	&"design_ui", &"design_list_ui", &"design_album_ui", &"name_entry_ui",
]


static func is_open(tree: SceneTree, group: StringName) -> bool:
	if tree == null:
		return false
	for node: Node in tree.get_nodes_in_group(group):
		if node.has_method(&"is_open") and bool(node.call(&"is_open")):
			return true
	return false


static func any_open(tree: SceneTree, groups: Array[StringName] = ALL) -> bool:
	for group: StringName in groups:
		if is_open(tree, group):
			return true
	return false
