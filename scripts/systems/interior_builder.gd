class_name InteriorBuilder
extends RefCounted

## Turns a bound `Interior` into placeholder floor, walls, furniture, and doors.

const WALL_HEIGHT := 3.0
const FURNITURE_SCENE := preload("res://scenes/world/furniture.tscn")
const DOOR_SCENE := preload("res://scenes/world/door.tscn")


func build(root: Node3D, interior: Interior) -> void:
	if root == null or interior == null or interior.room == null:
		return
	var room: Room = interior.room
	var grid: WorldGrid = interior.grid
	var terrain: Node3D = root.get_node_or_null("Terrain") as Node3D
	var furniture_root: Node3D = root.get_node_or_null("Furniture") as Node3D
	var doors_root: Node3D = root.get_node_or_null("Doors") as Node3D
	if terrain == null:
		terrain = Node3D.new()
		terrain.name = "Terrain"
		root.add_child(terrain)
	if furniture_root == null:
		furniture_root = Node3D.new()
		furniture_root.name = "Furniture"
		root.add_child(furniture_root)
	if doors_root == null:
		doors_root = Node3D.new()
		doors_root.name = "Doors"
		root.add_child(doors_root)
	_paint_shell(terrain, room, grid)
	for entry: FurniturePlacement in room.placements:
		add_furniture(furniture_root, interior, entry)
	_add_exit_door(doors_root, grid, room)
	_add_linked_doors(doors_root, grid, room)


func _paint_shell(root: Node3D, room: Room, grid: WorldGrid) -> void:
	var target := _shell_bounds(room, grid)
	var shell: Node3D = GeneratedVisual.attach_interior(root, room.shell_ids, room.wall_id, room.floor_id, target)
	_add_shell_collision(root, room, grid)
	if shell != null:
		return
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = InteriorCatalog.floor_color(room.floor_id)
	if floor_mat.albedo_color.a <= 0.0:
		floor_mat.albedo_color = InteriorCatalog.floor_color(InteriorCatalog.FLOOR_DEFAULT)
	_apply_tile_texture(floor_mat, InteriorCatalog.floor_texture_path(room.floor_id))
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = InteriorCatalog.wall_color(room.wall_id)
	if wall_mat.albedo_color.a <= 0.0:
		wall_mat.albedo_color = InteriorCatalog.wall_color(InteriorCatalog.WALL_DEFAULT)
	_apply_tile_texture(wall_mat, InteriorCatalog.wall_texture_path(room.wall_id))
	var inner := _inner_size(room, grid)
	var center := _inner_center(room, grid)
	root.add_child(_box_visual(Vector3(inner.x, 0.08, inner.z), center + Vector3(0.0, 0.04, 0.0), floor_mat))
	_add_wall_visuals(root, room, grid, wall_mat)


func _add_shell_collision(root: Node3D, room: Room, grid: WorldGrid) -> void:
	var inner := _inner_size(room, grid)
	var center := _inner_center(room, grid)
	root.add_child(_collider(Vector3(inner.x, 0.12, inner.z), center + Vector3(0.0, 0.04, 0.0)))
	var origin: Vector3 = grid.cell_corner(Vector2i.ZERO)
	var full := Vector3(float(grid.columns) * grid.cell_size, WALL_HEIGHT, float(grid.rows) * grid.cell_size)
	var inner_nw: Vector3 = grid.cell_corner(room.inner_origin)
	var inner_se: Vector3 = grid.cell_corner(room.inner_origin + room.inner_size)
	var north_d: float = inner_nw.z - origin.z
	if north_d > 0.05:
		root.add_child(
			_collider(
				Vector3(full.x, WALL_HEIGHT, north_d),
				Vector3(origin.x + full.x * 0.5, WALL_HEIGHT * 0.5, origin.z + north_d * 0.5)
			)
		)
	var south_d: float = origin.z + full.z - inner_se.z
	if south_d > 0.05:
		root.add_child(
			_collider(
				Vector3(full.x, WALL_HEIGHT, south_d),
				Vector3(origin.x + full.x * 0.5, WALL_HEIGHT * 0.5, inner_se.z + south_d * 0.5)
			)
		)
	var west_d: float = inner_nw.x - origin.x
	var mid_z: float = (inner_nw.z + inner_se.z) * 0.5
	var mid_h: float = inner_se.z - inner_nw.z
	if west_d > 0.05:
		root.add_child(
			_collider(
				Vector3(west_d, WALL_HEIGHT, mid_h),
				Vector3(origin.x + west_d * 0.5, WALL_HEIGHT * 0.5, mid_z)
			)
		)
	var east_d: float = origin.x + full.x - inner_se.x
	if east_d > 0.05:
		root.add_child(
			_collider(
				Vector3(east_d, WALL_HEIGHT, mid_h),
				Vector3(inner_se.x + east_d * 0.5, WALL_HEIGHT * 0.5, mid_z)
			)
		)


func _add_wall_visuals(root: Node3D, room: Room, grid: WorldGrid, mat: Material) -> void:
	var origin: Vector3 = grid.cell_corner(Vector2i.ZERO)
	var full := Vector3(float(grid.columns) * grid.cell_size, WALL_HEIGHT, float(grid.rows) * grid.cell_size)
	var inner_nw: Vector3 = grid.cell_corner(room.inner_origin)
	var inner_se: Vector3 = grid.cell_corner(room.inner_origin + room.inner_size)
	var north_d: float = inner_nw.z - origin.z
	if north_d > 0.05:
		root.add_child(
			_box_visual(
				Vector3(full.x, WALL_HEIGHT, north_d),
				Vector3(origin.x + full.x * 0.5, WALL_HEIGHT * 0.5, origin.z + north_d * 0.5),
				mat
			)
		)
	var south_d: float = origin.z + full.z - inner_se.z
	if south_d > 0.05:
		root.add_child(
			_box_visual(
				Vector3(full.x, WALL_HEIGHT, south_d),
				Vector3(origin.x + full.x * 0.5, WALL_HEIGHT * 0.5, inner_se.z + south_d * 0.5),
				mat
			)
		)
	var west_d: float = inner_nw.x - origin.x
	var mid_z: float = (inner_nw.z + inner_se.z) * 0.5
	var mid_h: float = inner_se.z - inner_nw.z
	if west_d > 0.05:
		root.add_child(
			_box_visual(
				Vector3(west_d, WALL_HEIGHT, mid_h),
				Vector3(origin.x + west_d * 0.5, WALL_HEIGHT * 0.5, mid_z),
				mat
			)
		)
	var east_d: float = origin.x + full.x - inner_se.x
	if east_d > 0.05:
		root.add_child(
			_box_visual(
				Vector3(east_d, WALL_HEIGHT, mid_h),
				Vector3(inner_se.x + east_d * 0.5, WALL_HEIGHT * 0.5, mid_z),
				mat
			)
		)


func _inner_size(room: Room, grid: WorldGrid) -> Vector3:
	return Vector3(
		float(maxi(room.inner_size.x, 1)) * grid.cell_size,
		WALL_HEIGHT,
		float(maxi(room.inner_size.y, 1)) * grid.cell_size
	)


func _inner_center(room: Room, grid: WorldGrid) -> Vector3:
	var nw: Vector3 = grid.cell_corner(room.inner_origin)
	var size := _inner_size(room, grid)
	return Vector3(nw.x + size.x * 0.5, 0.0, nw.z + size.z * 0.5)


func _collider(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body


func _box_visual(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.position = pos
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = mat
	return visual


func _shell_bounds(room: Room, grid: WorldGrid) -> AABB:
	## Fit shell to the walkable rect (same as player myhome). NPC Arrange_Room
	## uses rom_myhome2, not the 8×8 room01 acre.
	var nw: Vector3 = grid.cell_corner(room.inner_origin)
	var se: Vector3 = grid.cell_corner(room.inner_origin + room.inner_size)
	return AABB(Vector3(nw.x, 0.0, nw.z), Vector3(se.x - nw.x, WALL_HEIGHT, se.z - nw.z))


func _apply_tile_texture(mat: StandardMaterial3D, path: String) -> void:
	if path.is_empty():
		return
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.texture_repeat = true


func add_furniture(root: Node3D, interior: Interior, entry: FurniturePlacement) -> void:
	if entry == null or entry.id == &"":
		return
	var data: FurnitureData = interior.furniture_of(entry.furniture_id)
	if data == null:
		return
	var footprint: Vector2i = entry.resolved_footprint(data)
	var node: Node3D = FURNITURE_SCENE.instantiate() as Node3D
	node.name = String(entry.id)
	node.set("data", data)
	node.set("occupant_id", entry.id)
	node.set("footprint", footprint)
	node.set("grid_facing", entry.facing)
	node.set("cloth_index", entry.cloth_index)
	if data.visual_id != &"":
		node.set("visual_id", data.visual_id)
	var pos: Vector3 = interior.grid.furniture_world(entry.cell, footprint, entry.facing)
	pos.y = 0.0
	node.position = pos
	root.add_child(node)
	if entry.cloth_index >= 0:
		GeneratedVisual.apply_cloth(node, entry.cloth_index)
	if node.has_method("apply_grid_yaw"):
		node.call("apply_grid_yaw", entry.facing)
	if node.has_method("apply_footprint"):
		node.call("apply_footprint", interior.grid.cell_size)


func _add_exit_door(root: Node3D, grid: WorldGrid, room: Room) -> void:
	var door: Node3D = DOOR_SCENE.instantiate() as Node3D
	door.name = "Exit"
	door.position = grid.cell_to_world(room.door_cell)
	door.set("label", "Leave")
	door.set("verb", Interaction.ENTER)
	door.set("exits_interior", true)
	door.set("occupy_grid", false)
	root.add_child(door)


func _add_linked_doors(root: Node3D, grid: WorldGrid, room: Room) -> void:
	if room.linked_rooms.is_empty():
		return
	var inner_north := room.inner_origin.y
	var start_x: int = room.inner_origin.x + 1
	for i: int in room.linked_rooms.size():
		var room_id: StringName = room.linked_rooms[i]
		var template: Room = InteriorCatalog.room_template(room_id)
		var door: Node3D = DOOR_SCENE.instantiate() as Node3D
		door.name = "Link_%s" % String(room_id)
		var cell := Vector2i(start_x + i * 2, inner_north)
		if not room.is_inner(cell):
			cell = Vector2i(room.inner_origin.x, inner_north)
		door.position = grid.cell_to_world(cell)
		door.set("label", template.display_name if template else "Room")
		door.set("verb", Interaction.ENTER)
		door.set("linked_room_id", room_id)
		door.set("occupy_grid", false)
		root.add_child(door)
