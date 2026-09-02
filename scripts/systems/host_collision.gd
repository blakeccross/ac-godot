class_name HostCollision
extends RefCounted

## Physics hulls for outdoor hosts. Generated GLBs have no collision; placeholder
## boxes in the `.tscn` are the authored 2×2 house, not the occupancy footprint.
## Size from `WorldGrid` cells (same 2 m unit as outdoor). Do not trimesh the mesh.

const CELL := 2.0
const INSET := 0.92
const BUILDING_HEIGHT := 2.8
const TREE_HEIGHT := 2.2
const ROCK_HEIGHT := 1.1
const SENSOR_PAD := 0.25
const SENSOR_Y := 1.0
## `aMHS_rewrite_pl_out_data` restart offset (GX). Local SW; west plots rotate with mesh yaw.
const PLAYER_DOOR_GX := 48.29
## Door approach stands (GX from actor world / mesh). Angled doors are not south-face boxes.
## Shop: `aSHOP` request (−50,+50). Able/post check (−40,+50). Police request (+50,+50).
## Museum check/request (0,+100).
const SHOP_DOOR_GX := Vector2(-50.0, 50.0)
const ABLE_DOOR_GX := Vector2(-40.0, 50.0)
const POLICE_DOOR_GX := Vector2(50.0, 50.0)
const MUSEUM_DOOR_GX := Vector2(0.0, 100.0)


static func is_player_house(visual_id: StringName) -> bool:
	return String(visual_id).contains("myhome")


static func is_museum(visual_id: StringName) -> bool:
	return String(visual_id).contains("museum")


static func is_able_sisters(visual_id: StringName) -> bool:
	return String(visual_id).contains("tailor")


static func is_police(visual_id: StringName) -> bool:
	return String(visual_id).contains("kouban")


static func is_shop(visual_id: StringName) -> bool:
	return String(visual_id).contains("shop1")


static func is_post_office(visual_id: StringName) -> bool:
	## `obj_s_yubinkyoku` / winter variant; not the indoor `post_office` room id alone.
	var s := String(visual_id)
	return s.contains("yubinkyoku") or s.contains("post_office")


static func uses_structure_offset(visual_id: StringName) -> bool:
	## Walk walls from `StructureOffset` plus-offsets — not a StaticBody hull.
	return (
		is_player_house(visual_id)
		or is_museum(visual_id)
		or is_able_sisters(visual_id)
		or is_police(visual_id)
		or is_shop(visual_id)
		or is_post_office(visual_id)
	)


static func player_door_offset() -> Vector3:
	var d: float = PLAYER_DOOR_GX * FieldCatalog.GX_TO_METERS
	return Vector3(-d, SENSOR_Y, d)


static func door_offset(visual_id: StringName) -> Vector3:
	## Local sensor offset from the structure mesh origin (meters). Empty → use south face.
	if is_player_house(visual_id):
		return player_door_offset()
	if is_shop(visual_id):
		return _door_from_gx(SHOP_DOOR_GX)
	if is_able_sisters(visual_id) or is_post_office(visual_id):
		return _door_from_gx(ABLE_DOOR_GX)
	if is_police(visual_id):
		return _door_from_gx(POLICE_DOOR_GX)
	if is_museum(visual_id):
		return _door_from_gx(MUSEUM_DOOR_GX)
	return Vector3.ZERO


static func xz_size(footprint: Vector2i, cell_size: float, inset: float = INSET) -> Vector2:
	var cs: float = cell_size if cell_size > 0.001 else CELL
	var frac: float = inset if inset > 0.001 else 1.0
	return Vector2(
		maxf(float(maxi(footprint.x, 1)) * cs * frac, 0.4),
		maxf(float(maxi(footprint.y, 1)) * cs * frac, 0.4)
	)


static func apply_box(
	host: Node3D,
	footprint: Vector2i,
	cell_size: float,
	height: float = BUILDING_HEIGHT,
	inset: float = INSET
) -> void:
	var col: CollisionShape3D = _body_shape(host)
	if col == null:
		return
	var xz: Vector2 = xz_size(footprint, cell_size, inset)
	var box := BoxShape3D.new()
	box.size = Vector3(xz.x, height, xz.y)
	col.shape = box
	col.position = Vector3(0.0, height * 0.5, 0.0)
	col.disabled = false
	if host is CollisionObject3D:
		(host as CollisionObject3D).collision_layer = 1
		(host as CollisionObject3D).collision_mask = 0
	place_south_sensor(host, footprint, cell_size, inset)


static func apply_cylinder(host: Node3D, footprint: Vector2i, cell_size: float) -> void:
	var col: CollisionShape3D = _body_shape(host)
	if col == null:
		return
	var xz: Vector2 = xz_size(footprint, cell_size)
	var cyl := CylinderShape3D.new()
	cyl.height = TREE_HEIGHT
	cyl.radius = minf(xz.x, xz.y) * 0.5
	col.shape = cyl
	col.position = Vector3(0.0, TREE_HEIGHT * 0.5, 0.0)
	col.disabled = false
	if host is CollisionObject3D:
		(host as CollisionObject3D).collision_layer = 1
		(host as CollisionObject3D).collision_mask = 0


static func apply_rock(host: Node3D, footprint: Vector2i, cell_size: float) -> void:
	apply_box(host, footprint, cell_size, ROCK_HEIGHT)


static func disable_body(host: Node3D) -> void:
	var col: CollisionShape3D = _body_shape(host)
	if col != null:
		col.disabled = true
	if host is CollisionObject3D:
		(host as CollisionObject3D).collision_layer = 0
		(host as CollisionObject3D).collision_mask = 0


static func apply_house(host: Node3D, visual_id: StringName, occupancy: Vector2i, cell_size: float) -> void:
	## Walk collision is `StructureOffset` on the heightfield. Keep the door sensor only.
	disable_body(host)
	if is_player_house(visual_id):
		place_door_sensor(host, player_door_offset())
		return
	place_south_sensor(host, occupancy, cell_size)


static func apply_building(host: Node3D, visual_id: StringName, occupancy: Vector2i, cell_size: float) -> void:
	## Public structures with `set_bgOffset` use the heightfield; others keep a box.
	if (
		is_museum(visual_id)
		or is_able_sisters(visual_id)
		or is_police(visual_id)
		or is_post_office(visual_id)
	):
		disable_body(host)
		var door: Vector3 = door_offset(visual_id)
		if door != Vector3.ZERO:
			## Museum opening spans ~80 GX — fill it so you cannot walk past the stand.
			## Outdoor check radius is ~33 GX (`aMsm_check_player` t < 1100); box covers the bay.
			var box := Vector3(1.6, 2.0, 1.6)
			if is_museum(visual_id):
				box = Vector3(4.0, 2.6, 2.2)
			elif is_police(visual_id):
				box = Vector3(2.0, 2.0, 2.0)
			place_door_sensor(host, door, box)
		else:
			place_south_sensor(host, occupancy, cell_size)
		return
	apply_box(host, occupancy, cell_size)


static func resize_interact_box(host: Node3D, size: Vector3) -> void:
	## Public helper for indoor museum wing openings.
	if host == null or size == Vector3.ZERO:
		return
	_resize_door_box(host, size)
	var nested: Node = host.get_node_or_null("InteractVolume")
	if nested is Node3D:
		_resize_door_box(nested as Node3D, size)


static func apply_shop(host: Node3D, occupancy: Vector2i, cell_size: float) -> void:
	## Nook shop walk walls are `StructureOffset` (`aSHOP_set_bgOffset`).
	disable_body(host)
	place_door_sensor(host, _door_from_gx(SHOP_DOOR_GX), Vector3(1.6, 2.0, 1.6))


static func place_door_sensor(host: Node3D, offset: Vector3, box_size: Vector3 = Vector3.ZERO) -> void:
	## Place InteractVolume / Door at the decomp door stand (local space).
	for name: String in ["InteractVolume", "Door"]:
		var node: Node = host.get_node_or_null(name)
		if node is Node3D:
			var n := node as Node3D
			n.position = Vector3(offset.x, offset.y if offset.y > 0.01 else n.position.y, offset.z)
			if box_size != Vector3.ZERO:
				_resize_door_box(n, box_size)


static func _resize_door_box(node: Node3D, size: Vector3) -> void:
	var shape_node: CollisionShape3D = null
	if node is CollisionShape3D:
		shape_node = node as CollisionShape3D
	else:
		var nested: Node = node.get_node_or_null("InteractVolume/CollisionShape3D")
		if nested == null:
			nested = node.get_node_or_null("CollisionShape3D")
		if nested is CollisionShape3D:
			shape_node = nested as CollisionShape3D
	if shape_node == null:
		return
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box


static func place_south_sensor(host: Node3D, footprint: Vector2i, cell_size: float, inset: float = INSET) -> void:
	## Door / interact volume sits just outside the south face so ENTER still reaches.
	var xz: Vector2 = xz_size(footprint, cell_size, inset)
	var z: float = xz.y * 0.5 + SENSOR_PAD
	for name: String in ["InteractVolume", "Door"]:
		var node: Node = host.get_node_or_null(name)
		if node is Node3D:
			var n := node as Node3D
			n.position = Vector3(n.position.x, n.position.y, z)


static func _door_from_gx(xz: Vector2) -> Vector3:
	var s: float = FieldCatalog.GX_TO_METERS
	return Vector3(xz.x * s, SENSOR_Y, xz.y * s)


static func _body_shape(host: Node) -> CollisionShape3D:
	if host == null:
		return null
	for child in host.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null
