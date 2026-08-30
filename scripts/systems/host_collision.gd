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
## `aMHS_rewrite_pl_out_data` restart offset (GX). Door is SW in local mesh space.
const PLAYER_DOOR_GX := 48.29


static func is_player_house(visual_id: StringName) -> bool:
	return String(visual_id).contains("myhome")


static func player_door_offset() -> Vector3:
	var d: float = PLAYER_DOOR_GX * FieldCatalog.GX_TO_METERS
	return Vector3(-d, 1.0, d)


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
		var door: Vector3 = player_door_offset()
		for name: String in ["InteractVolume", "Door"]:
			var node: Node = host.get_node_or_null(name)
			if node is Node3D:
				var n := node as Node3D
				n.position = Vector3(door.x, n.position.y, door.z)
		return
	place_south_sensor(host, occupancy, cell_size)


static func place_south_sensor(host: Node3D, footprint: Vector2i, cell_size: float, inset: float = INSET) -> void:
	## Door / interact volume sits just outside the south face so ENTER still reaches.
	var xz: Vector2 = xz_size(footprint, cell_size, inset)
	var z: float = xz.y * 0.5 + SENSOR_PAD
	for name: String in ["InteractVolume", "Door"]:
		var node: Node = host.get_node_or_null(name)
		if node is Node3D:
			var n := node as Node3D
			n.position = Vector3(n.position.x, n.position.y, z)


static func _body_shape(host: Node) -> CollisionShape3D:
	if host == null:
		return null
	for child in host.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null
