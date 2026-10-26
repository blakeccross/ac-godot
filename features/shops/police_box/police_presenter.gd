class_name PolicePresenter
extends RefCounted

## Fills the police box for today. Booker, the clock and the two window sunshine beams are
## authored in `police_box.tscn`; this adds the hulls for the blocking units, gives Booker
## the room's grid, and lays out one field card per lost-and-found item
## (`police_box_actable`, `RSV_POLICE_ITEM_*`). Lost-and-found props are in the
## `"police_set"` group so `refresh_public_set` rebuilds them.

const LOST_FOUND_SCENE := preload("res://features/shops/police_box/lost_and_found_item.tscn")


func present(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	_furniture_collision(root, interior)
	var booker: Node = root.get_node_or_null("Booker")
	if booker != null and booker.has_method("bind_grid"):
		booker.call("bind_grid", interior.grid)
	_lost_and_found(root, interior)


## Solid hulls for the blocking BG units (shelves, desk, locker, entrance walls): the shell
## mesh has no physics. Kept items then rest on the shelf tops
## (`mCoBG_GetBgY_OnlyCenter_FromWpos2`), not inside them.
func _furniture_collision(root: Node3D, interior: IndoorSession) -> void:
	InteriorUnitCollision.add_hulls(
		root, interior.grid, "PoliceFurnitureCol", PoliceDisplay.blocked_units()
	)


func _lost_and_found(root: Node3D, interior: IndoorSession) -> void:
	if Game == null or Game.police == null:
		return
	for old: Node in root.get_children():
		if String(old.name).begins_with("LostFound_"):
			root.remove_child(old)
			old.queue_free()
	var items: Array[StringName] = Game.police.keep_items()
	var cells: Array[Vector2i] = PoliceDisplay.lost_found_cells()
	for i: int in mini(items.size(), cells.size()):
		var item_id: StringName = items[i]
		if item_id == &"":
			continue
		var node: Node3D = LOST_FOUND_SCENE.instantiate() as Node3D
		node.name = "LostFound_%d" % i
		node.set("slot", i)
		node.set("item_id", item_id)
		node.position = PoliceDisplay.gx_to_world(interior.grid, PoliceDisplay.unit_center_gx(cells[i]))
		root.add_child(node)
