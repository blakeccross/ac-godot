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
	_furniture_collision(root, interior)
	_booker(root, interior)
	_clock(root, interior)
	_sunshine(root, interior, "SunshineL", PoliceDisplay.SUNSHINE_L_GX, true)
	_sunshine(root, interior, "SunshineR", PoliceDisplay.SUNSHINE_R_GX, false)
	_lost_and_found(root, interior)


## Solid hulls for the shell's raised BG units (shelves, desk, locker): the shell mesh has
## no physics and `add_shell_collision` only builds the floor and walls. Kept items then
## sit on the shelf tops (`mCoBG_GetBgY_OnlyCenter_FromWpos2`), not inside them.
func _furniture_collision(root: Node3D, interior: IndoorSession) -> void:
	if root.get_node_or_null("PoliceFurnitureCol") != null:
		return
	var raised: Dictionary = PoliceDisplay.raised_units()
	if raised.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "PoliceFurnitureCol"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var cell_m: float = interior.grid.cell_size
	for cell: Vector2i in raised:
		## One box per run of equal-height units along a row.
		if raised.get(cell - Vector2i(1, 0), -1.0) == raised[cell]:
			continue
		var h_gx: float = raised[cell]
		var run := 1
		while raised.get(cell + Vector2i(run, 0), -1.0) == h_gx:
			run += 1
		var h: float = h_gx * FieldCatalog.GX_TO_METERS
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(cell_m * run, h, cell_m)
		shape.shape = box
		var west: Vector3 = PoliceDisplay.gx_to_world(
			interior.grid, Vector3(float(cell.x) * 40.0, 0.0, float(cell.y) * 40.0 + 20.0)
		)
		shape.position = west + Vector3(cell_m * run * 0.5, h * 0.5, 0.0)
		body.add_child(shape)


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


## `HOUSE_CLOCK` in the police box (`aHC_position_data`).
func _clock(root: Node3D, interior: IndoorSession) -> void:
	if root.get_node_or_null("PoliceClock") != null:
		return
	if FieldCatalog.mesh_paths(PoliceDisplay.CLOCK_VISUAL).is_empty():
		return
	var host := Node3D.new()
	host.name = "PoliceClock"
	host.position = PoliceDisplay.gx_to_world(interior.grid, PoliceDisplay.CLOCK_GX)
	root.add_child(host)
	GeneratedVisual.attach(host, PoliceDisplay.CLOCK_VISUAL)


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
