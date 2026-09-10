class_name PolicePresenter
extends RefCounted

## Furnishes the police box: Booker at his stand and one prop per lost-and-found
## item (`police_box_actable`, `RSV_POLICE_ITEM_*`). Lost-and-found props are in
## the `"police_set"` group so `refresh_public_set` rebuilds them.

const BOOKER_SCENE := preload("res://scenes/world/interiors/booker.tscn")
const LOST_FOUND_SCENE := preload("res://scenes/world/lost_and_found_item.tscn")


func present(root: Node3D, interior: Interior) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	_booker(root, interior)
	_lost_and_found(root, interior)


func _booker(root: Node3D, interior: Interior) -> void:
	var pos: Vector3 = PoliceDisplay.gx_to_world(interior.grid, PoliceDisplay.BOOKER_STAND_GX)
	var yaw: float = WorldGrid.yaw_for_facing(PoliceDisplay.BOOKER_FACING)
	var existing: Node3D = root.get_node_or_null("Booker") as Node3D
	if existing != null:
		existing.position = pos
		existing.rotation.y = yaw
		return
	var booker: Node3D = BOOKER_SCENE.instantiate() as Node3D
	booker.name = "Booker"
	booker.position = pos
	booker.rotation.y = yaw
	root.add_child(booker)


func _lost_and_found(root: Node3D, interior: Interior) -> void:
	if Game == null or Game.police == null:
		return
	for old: Node in root.get_children():
		if String(old.name).begins_with("LostFound_"):
			old.queue_free()
	Game.police.ensure_init()
	var items: Array[StringName] = Game.police.keep_items()
	for i: int in mini(items.size(), PoliceDisplay.LOST_FOUND_CELLS.size()):
		var item_id: StringName = items[i]
		if item_id == &"":
			continue
		var node: Node3D = LOST_FOUND_SCENE.instantiate() as Node3D
		node.name = "LostFound_%d" % i
		node.set("slot", i)
		node.set("item_id", item_id)
		node.position = interior.grid.cell_to_world(PoliceDisplay.cell_for_slot(i))
		root.add_child(node)
