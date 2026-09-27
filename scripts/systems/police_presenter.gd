class_name PolicePresenter
extends RefCounted

## Furnishes the police box: Booker at his stand, the two window sunshine beams, and one
## field card per lost-and-found item (`police_box_actable`, `POLICE_BOX_actor_data`,
## `RSV_POLICE_ITEM_*`). Lost-and-found props are in the `"police_set"` group so
## `refresh_public_set` rebuilds them.

const BOOKER_SCENE := preload("res://scenes/world/interiors/booker.tscn")
const LOST_FOUND_SCENE := preload("res://scenes/world/lost_and_found_item.tscn")
const SUNSHINE_SCENE := preload("res://scenes/world/interiors/police_sunshine.tscn")


func present(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	_booker(root, interior)
	_sunshine(root, interior, "SunshineL", PoliceDisplay.SUNSHINE_L_GX, true)
	_sunshine(root, interior, "SunshineR", PoliceDisplay.SUNSHINE_R_GX, false)
	_lost_and_found(root, interior)


func _booker(root: Node3D, interior: IndoorSession) -> void:
	var existing: Node3D = root.get_node_or_null("Booker") as Node3D
	if existing != null:
		## Refreshes after a claim must not snap him back to his stand.
		if existing.has_meta("placed"):
			return
		existing.position = PoliceDisplay.gx_to_world(interior.grid, PoliceDisplay.BOOKER_STAND_GX)
		existing.rotation.y = WorldGrid.yaw_for_facing(PoliceDisplay.BOOKER_FACING)
		existing.set_meta("placed", true)
		if existing.has_method("bind_grid"):
			existing.call("bind_grid", interior.grid)
		return
	var booker: Node3D = BOOKER_SCENE.instantiate() as Node3D
	booker.name = "Booker"
	booker.position = PoliceDisplay.gx_to_world(interior.grid, PoliceDisplay.BOOKER_STAND_GX)
	booker.rotation.y = WorldGrid.yaw_for_facing(PoliceDisplay.BOOKER_FACING)
	booker.set_meta("placed", true)
	root.add_child(booker)
	if booker.has_method("bind_grid"):
		booker.call("bind_grid", interior.grid)


func _sunshine(root: Node3D, interior: IndoorSession, node_name: String, gx: Vector3, left: bool) -> void:
	var node: Node3D = root.get_node_or_null(node_name) as Node3D
	if node == null:
		node = SUNSHINE_SCENE.instantiate() as Node3D
		node.name = node_name
		root.add_child(node)
	node.set("left", left)
	node.position = PoliceDisplay.gx_to_world(interior.grid, PoliceDisplay.sunshine_anchor_gx(gx, left))


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
