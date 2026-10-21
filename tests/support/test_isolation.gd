class_name TestIsolation
extends RefCounted

## Earlier suites can leave nodes in the tree (gdUnit runs every suite in one scene tree):
## a player that `Game.capture_player_from_tree` reads on save, bugs still in `Bug.GROUP`,
## an overlay that reports itself open. Lookups by group then find those first. Drop the
## leftovers from the groups a test relies on, without freeing nodes other suites own.


static func forget_groups(tree: SceneTree, groups: Array[StringName]) -> void:
	if tree == null:
		return
	for group: StringName in groups:
		for stale: Node in tree.get_nodes_in_group(group):
			stale.remove_from_group(group)


## Free leftover nodes of `type_name` (a `class_name`) anywhere under the tree's root.
static func free_leftovers(tree: SceneTree, type_name: String) -> void:
	if tree == null:
		return
	for node: Node in tree.root.find_children("*", type_name, true, false):
		node.queue_free()
