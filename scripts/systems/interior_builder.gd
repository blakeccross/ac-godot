class_name InteriorBuilder
extends RefCounted

## Turns a bound `Interior` into placeholder floor, walls, furniture, and doors.

const WALL_HEIGHT := 3.0
const FURNITURE_SCENE := preload("res://scenes/world/furniture.tscn")
const DOOR_SCENE := preload("res://scenes/world/door.tscn")
const COUNTER_SCENE := preload("res://scenes/world/shop_counter.tscn")
const STOCK_SCENE := preload("res://scenes/world/shop_stock.tscn")


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
	add_shop_set(furniture_root, interior)
	add_museum_set(furniture_root, interior)
	_add_exit_door(doors_root, grid, room)
	_add_linked_doors(doors_root, grid, room)


func build_museum_stage(root: Node3D, interior: Interior) -> void:
	## Legacy single-root harness path — prefer `build_museum_room` per authored wing.
	build_museum_room(root, interior)


func build_museum_room(room_root: Node3D, interior: Interior) -> void:
	## Authored wing helper: shell collision only. Exhibits belong to each room script.
	if room_root == null or interior == null or interior.room == null:
		return
	var terrain: Node3D = room_root.get_node_or_null("Terrain") as Node3D
	if terrain == null:
		return
	_clear_shell_colliders(terrain)
	add_museum_shell_collision(
		terrain, interior.room, interior.grid, museum_door_gaps(interior.room, interior.grid)
	)


## Floor slab + outer walls. `gaps` = [{ "side", "center", "half" }, ...] door openings.
func add_museum_shell_collision(
	root: Node3D, room: Room, grid: WorldGrid, gaps: Variant = []
) -> void:
	if root == null or room == null or grid == null:
		return
	var list: Array = _normalize_museum_gaps(gaps)
	_add_shell_collision(root, room, grid, list)


## All wall openings for a museum room (wing links + leave sensors).
func museum_door_gaps(room: Room, grid: WorldGrid) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if room == null or grid == null:
		return out
	var sensors: Array[Vector3] = []
	if room.id == &"museum_entrance":
		sensors.append(MuseumDisplay.ENTRANCE_EXIT_SENSOR_GX)
		for link: Dictionary in MuseumDisplay.ENTRANCE_WING_DOORS:
			sensors.append(link["sensor"] as Vector3)
	elif MuseumDisplay.WING_EXIT_DOORS.has(room.id):
		sensors.append(MuseumDisplay.WING_EXIT_DOORS[room.id]["sensor"] as Vector3)
	var half: float = 40.0 * FieldCatalog.GX_TO_METERS
	for sensor: Vector3 in sensors:
		var gap: Dictionary = _museum_gap_for_sensor(grid, sensor, half)
		if not gap.is_empty():
			out.append(gap)
	return out


## Backward-compatible single leave-door gap (prefer `museum_door_gaps`).
func museum_exit_gap(room: Room, grid: WorldGrid) -> Dictionary:
	var gaps: Array[Dictionary] = museum_door_gaps(room, grid)
	if room != null and room.id == &"museum_entrance":
		for gap: Dictionary in gaps:
			if gap.get("side", &"") == &"south":
				return gap
	return gaps[0] if not gaps.is_empty() else {}


func _museum_gap_for_sensor(grid: WorldGrid, sensor: Vector3, half: float) -> Dictionary:
	var world: Vector3 = MuseumDisplay.gx_to_world(grid, sensor)
	## North openings sit on the low-Z wall (entrance → art / fossil).
	if sensor.z <= 120.0:
		return {"side": &"north", "center": world.x, "half": half}
	if sensor.z >= 400.0 and sensor.x > 120.0 and sensor.x < 400.0:
		return {"side": &"south", "center": world.x, "half": half}
	if sensor.x <= 120.0:
		return {"side": &"west", "center": world.z, "half": half}
	if sensor.x >= 400.0:
		return {"side": &"east", "center": world.z, "half": half}
	return {"side": &"south", "center": world.x, "half": half}


func _normalize_museum_gaps(gaps: Variant) -> Array:
	if gaps is Dictionary:
		return [gaps] if not (gaps as Dictionary).is_empty() else []
	if gaps is Array:
		return gaps as Array
	return []


func _gaps_on_side(gaps: Array, side: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in gaps:
		if entry is Dictionary and (entry as Dictionary).get("side", &"") == side:
			out.append(entry as Dictionary)
	return out


func _clear_runtime_children(root: Node) -> void:
	if root == null:
		return
	for child: Node in root.get_children():
		root.remove_child(child)
		child.free()


func _clear_shell_colliders(terrain: Node3D) -> void:
	## Drop box colliders from a previous populate.
	if terrain == null:
		return
	for child: Node in terrain.get_children():
		if child is StaticBody3D:
			terrain.remove_child(child)
			child.free()


func _paint_shell(root: Node3D, room: Room, grid: WorldGrid) -> void:
	## Museum `rom_museum*` keep the acre NW at `grid.origin` (FG / tank / door GX).
	var target := (
		AABB(grid.origin, Vector3(float(grid.columns) * grid.cell_size, WALL_HEIGHT, float(grid.rows) * grid.cell_size))
		if room.kind == Room.Kind.MUSEUM
		else _shell_bounds(room, grid)
	)
	var shell: Node3D = GeneratedVisual.attach_interior(root, room.shell_ids, room.wall_id, room.floor_id, target)
	var gaps: Array = museum_door_gaps(room, grid) if room.kind == Room.Kind.MUSEUM else []
	_add_shell_collision(root, room, grid, gaps)
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


func _add_shell_collision(root: Node3D, room: Room, grid: WorldGrid, gaps: Array = []) -> void:
	var inner := _inner_size(room, grid)
	var center := _inner_center(room, grid)
	root.add_child(_collider(Vector3(inner.x, 0.12, inner.z), center + Vector3(0.0, 0.04, 0.0)))
	## Door porches beyond the floor so wing / leave sensors stay walkable.
	if room.kind == Room.Kind.MUSEUM:
		_add_museum_door_porches(root, room, grid, gaps)
	var origin: Vector3 = grid.cell_corner(Vector2i.ZERO)
	var full := Vector3(float(grid.columns) * grid.cell_size, WALL_HEIGHT, float(grid.rows) * grid.cell_size)
	var inner_nw: Vector3 = grid.cell_corner(room.inner_origin)
	var inner_se: Vector3 = grid.cell_corner(room.inner_origin + room.inner_size)
	## Museum wall meshes sit on the floor rim (e.g. rom_museum3 north strip z≈2–4).
	## Outer-margin-only boxes left a cell of walk-through; pull walls one cell inward.
	var inset: float = grid.cell_size if room.kind == Room.Kind.MUSEUM else 0.0
	var wall_nw := Vector3(inner_nw.x + inset, 0.0, inner_nw.z + inset)
	var wall_se := Vector3(inner_se.x - inset, 0.0, inner_se.z - inset)
	if wall_se.x <= wall_nw.x + 0.05 or wall_se.z <= wall_nw.z + 0.05:
		wall_nw = inner_nw
		wall_se = inner_se
	var north_d: float = wall_nw.z - origin.z
	if north_d > 0.05:
		_add_multi_gapped_wall(
			root,
			Vector3(full.x, WALL_HEIGHT, north_d),
			Vector3(origin.x + full.x * 0.5, WALL_HEIGHT * 0.5, origin.z + north_d * 0.5),
			&"x",
			origin.x,
			origin.x + full.x,
			_gaps_on_side(gaps, &"north")
		)
	var south_d: float = origin.z + full.z - wall_se.z
	if south_d > 0.05:
		_add_multi_gapped_wall(
			root,
			Vector3(full.x, WALL_HEIGHT, south_d),
			Vector3(origin.x + full.x * 0.5, WALL_HEIGHT * 0.5, wall_se.z + south_d * 0.5),
			&"x",
			origin.x,
			origin.x + full.x,
			_gaps_on_side(gaps, &"south")
		)
	var west_d: float = wall_nw.x - origin.x
	var mid_z: float = (wall_nw.z + wall_se.z) * 0.5
	var mid_h: float = wall_se.z - wall_nw.z
	if west_d > 0.05 and mid_h > 0.05:
		_add_multi_gapped_wall(
			root,
			Vector3(west_d, WALL_HEIGHT, mid_h),
			Vector3(origin.x + west_d * 0.5, WALL_HEIGHT * 0.5, mid_z),
			&"z",
			wall_nw.z,
			wall_se.z,
			_gaps_on_side(gaps, &"west")
		)
	var east_d: float = origin.x + full.x - wall_se.x
	if east_d > 0.05 and mid_h > 0.05:
		_add_multi_gapped_wall(
			root,
			Vector3(east_d, WALL_HEIGHT, mid_h),
			Vector3(wall_se.x + east_d * 0.5, WALL_HEIGHT * 0.5, mid_z),
			&"z",
			wall_nw.z,
			wall_se.z,
			_gaps_on_side(gaps, &"east")
		)


func _add_museum_door_porches(
	root: Node3D, room: Room, grid: WorldGrid, gaps: Array
) -> void:
	var origin: Vector3 = grid.cell_corner(Vector2i.ZERO)
	var full_x: float = float(grid.columns) * grid.cell_size
	var full_z: float = float(grid.rows) * grid.cell_size
	var inner_nw: Vector3 = grid.cell_corner(room.inner_origin)
	var inner_se: Vector3 = grid.cell_corner(room.inner_origin + room.inner_size)
	for gap: Dictionary in _gaps_on_side(gaps, &"south"):
		var depth: float = origin.z + full_z - inner_se.z
		_add_porch_slab(root, gap, &"z", inner_se.z, depth)
	for gap: Dictionary in _gaps_on_side(gaps, &"north"):
		var depth: float = inner_nw.z - origin.z
		_add_porch_slab(root, gap, &"z", origin.z, depth)
	for gap: Dictionary in _gaps_on_side(gaps, &"west"):
		var depth: float = inner_nw.x - origin.x
		_add_porch_slab(root, gap, &"x", origin.x, depth)
	for gap: Dictionary in _gaps_on_side(gaps, &"east"):
		var depth: float = origin.x + full_x - inner_se.x
		_add_porch_slab(root, gap, &"x", inner_se.x, depth)


func _add_porch_slab(
	root: Node3D, gap: Dictionary, depth_axis: StringName, depth_lo: float, depth: float
) -> void:
	var center: float = float(gap.get("center", -1.0))
	var half: float = float(gap.get("half", 2.0))
	if center < 0.0 or half <= 0.05 or depth <= 0.05:
		return
	if depth_axis == &"z":
		root.add_child(
			_collider(
				Vector3(half * 2.0, 0.12, depth),
				Vector3(center, 0.04, depth_lo + depth * 0.5)
			)
		)
	else:
		root.add_child(
			_collider(
				Vector3(depth, 0.12, half * 2.0),
				Vector3(depth_lo + depth * 0.5, 0.04, center)
			)
		)


func _add_multi_gapped_wall(
	root: Node3D,
	full_size: Vector3,
	full_pos: Vector3,
	axis: StringName,
	span_lo: float,
	span_hi: float,
	gaps: Array[Dictionary]
) -> void:
	if gaps.is_empty():
		root.add_child(_collider(full_size, full_pos))
		return
	## Merge openings, then emit solid segments between them.
	var cuts: Array[Vector2] = []
	for gap: Dictionary in gaps:
		var center: float = float(gap.get("center", -1.0))
		var half: float = float(gap.get("half", 2.0))
		if center < 0.0 or half <= 0.05:
			continue
		cuts.append(Vector2(center - half, center + half))
	if cuts.is_empty():
		root.add_child(_collider(full_size, full_pos))
		return
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = [cuts[0]]
	for i: int in range(1, cuts.size()):
		var prev: Vector2 = merged[merged.size() - 1]
		var cur: Vector2 = cuts[i]
		if cur.x <= prev.y + 0.05:
			merged[merged.size() - 1] = Vector2(prev.x, maxf(prev.y, cur.y))
		else:
			merged.append(cur)
	var cursor: float = span_lo
	for cut: Vector2 in merged:
		var gap_lo: float = maxf(cut.x, span_lo)
		var gap_hi: float = minf(cut.y, span_hi)
		if gap_lo > cursor + 0.05:
			_add_wall_segment(root, full_size, full_pos, axis, cursor, gap_lo)
		cursor = maxf(cursor, gap_hi)
	if span_hi > cursor + 0.05:
		_add_wall_segment(root, full_size, full_pos, axis, cursor, span_hi)


func _add_wall_segment(
	root: Node3D,
	full_size: Vector3,
	full_pos: Vector3,
	axis: StringName,
	seg_lo: float,
	seg_hi: float
) -> void:
	var width: float = seg_hi - seg_lo
	if width <= 0.05:
		return
	if axis == &"x":
		root.add_child(
			_collider(
				Vector3(width, full_size.y, full_size.z),
				Vector3(seg_lo + width * 0.5, full_pos.y, full_pos.z)
			)
		)
	else:
		root.add_child(
			_collider(
				Vector3(full_size.x, full_size.y, width),
				Vector3(full_pos.x, full_pos.y, seg_lo + width * 0.5)
			)
		)


func _add_gapped_wall(
	root: Node3D,
	full_size: Vector3,
	full_pos: Vector3,
	axis: StringName,
	span_lo: float,
	span_hi: float,
	cut: bool,
	gap_center: float,
	gap_half: float
) -> void:
	## Single-gap helper kept for non-museum callers.
	var gaps: Array[Dictionary] = []
	if cut:
		gaps.append({"center": gap_center, "half": gap_half})
	_add_multi_gapped_wall(root, full_size, full_pos, axis, span_lo, span_hi, gaps)


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
	pos.y = 0.8 if entry.layer > 0 else 0.0
	node.position = pos
	root.add_child(node)
	if entry.cloth_index >= 0:
		GeneratedVisual.apply_cloth(node, entry.cloth_index)
	if node.has_method("apply_grid_yaw"):
		node.call("apply_grid_yaw", entry.facing)
	if node.has_method("apply_footprint"):
		node.call("apply_footprint", interior.grid.cell_size)


func add_museum_set(root: Node3D, interior: Interior) -> void:
	## Fossils / art / tank fish / case insects from town `MuseumBook` bits.
	MuseumPresenter.new().present(root, interior)


func add_shop_set(root: Node3D, interior: Interior) -> void:
	if root == null or interior == null or interior.room == null or Game == null:
		return
	var room: Room = interior.room
	var shop_id: StringName = Game.shops.shop_id_for_room(room)
	if shop_id == &"":
		return
	Game.shops.ensure_today(shop_id)
	var counter: Node3D = COUNTER_SCENE.instantiate() as Node3D
	counter.name = "ShopCounter"
	counter.set("shop_id", shop_id)
	counter.position = interior.grid.cell_to_world(_counter_cell(room))
	root.add_child(counter)
	var cells: Array[Vector2i] = _shop_stock_cells(room, interior)
	var listed: Array[StringName] = Game.shops.goods(shop_id)
	for i: int in mini(listed.size(), cells.size()):
		var item_id: StringName = listed[i]
		var node: Node3D = STOCK_SCENE.instantiate() as Node3D
		node.name = "ShopStock_%d" % i
		node.set("shop_id", shop_id)
		node.set("item_id", item_id)
		node.set("occupant_id", StringName("shop_stock_%d" % i))
		node.position = interior.grid.cell_to_world(cells[i])
		root.add_child(node)


func _counter_cell(room: Room) -> Vector2i:
	return Vector2i(room.door_cell.x - 1, room.spawn_cell.y - 1)


func _shop_stock_cells(room: Room, interior: Interior) -> Array[Vector2i]:
	var skip: Dictionary = {}
	skip[room.door_cell] = true
	skip[room.spawn_cell] = true
	skip[_counter_cell(room)] = true
	for entry: FurniturePlacement in room.placements:
		var data: FurnitureData = interior.furniture_of(entry.furniture_id)
		var foot: Vector2i = entry.resolved_footprint(data)
		for cell: Vector2i in interior.grid.footprint_cells(entry.cell, foot, entry.facing):
			skip[cell] = true
	var out: Array[Vector2i] = []
	var origin: Vector2i = room.inner_origin
	var inner: Vector2i = room.inner_size
	for z: int in range(origin.y, origin.y + inner.y):
		for x: int in range(origin.x, origin.x + inner.x):
			var cell := Vector2i(x, z)
			if bool(skip.get(cell, false)):
				continue
			out.append(cell)
	return out


func _add_exit_door(root: Node3D, grid: WorldGrid, room: Room) -> void:
	var door: Node3D = DOOR_SCENE.instantiate() as Node3D
	door.name = "Exit"
	door.set("label", "Leave")
	door.set("verb", Interaction.ENTER)
	door.set("occupy_grid", false)
	## Museum wings return to the entrance at decomp door spawns — not the outdoor exit.
	if room.kind == Room.Kind.MUSEUM and room.parent_room_id != &"" and MuseumDisplay.WING_EXIT_DOORS.has(room.id):
		var link: Dictionary = MuseumDisplay.WING_EXIT_DOORS[room.id] as Dictionary
		door.position = MuseumDisplay.gx_to_world(grid, link["sensor"] as Vector3)
		door.set("exits_interior", false)
		door.set("linked_room_id", room.parent_room_id)
		door.set("auto_enter", true)
		door.set("has_linked_spawn", true)
		door.set("linked_spawn_gx", link["spawn"] as Vector3)
		## `m_scene.c` angle_table matches furniture yaw (EAST=+90°), not `yaw_for_facing`.
		door.set("linked_spawn_yaw", WorldGrid.yaw_for_furniture(link["facing"] as WorldGrid.Facing))
		_size_museum_wing_door(door, link["sensor"] as Vector3)
	elif room.id == &"museum_entrance":
		## South opening sits on enter X (`aMsm_museum_enter_data`), not room-center door_cell.
		var sensor: Vector3 = MuseumDisplay.ENTRANCE_EXIT_SENSOR_GX
		door.position = MuseumDisplay.gx_to_world(grid, sensor)
		door.set("exits_interior", true)
		door.set("auto_enter", true)
		_size_museum_wing_door(door, sensor)
	else:
		door.position = grid.cell_to_world(room.door_cell)
		door.set("exits_interior", true)
	root.add_child(door)


func _add_linked_doors(root: Node3D, grid: WorldGrid, room: Room) -> void:
	if room.kind == Room.Kind.MUSEUM and room.id == &"museum_entrance":
		_add_museum_entrance_doors(root, grid)
		return
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


func _add_museum_entrance_doors(root: Node3D, grid: WorldGrid) -> void:
	## Four wing doors from `MUSEUM_ENTRANCE_door_data` (north / west / east walls).
	for link: Dictionary in MuseumDisplay.ENTRANCE_WING_DOORS:
		var room_id: StringName = link["room"] as StringName
		var template: Room = InteriorCatalog.room_template(room_id)
		var door: Node3D = DOOR_SCENE.instantiate() as Node3D
		door.name = "Link_%s" % String(room_id)
		door.position = MuseumDisplay.gx_to_world(grid, link["sensor"] as Vector3)
		door.set("label", template.display_name if template else "Room")
		door.set("verb", Interaction.ENTER)
		door.set("linked_room_id", room_id)
		door.set("occupy_grid", false)
		door.set("auto_enter", true)
		door.set("has_linked_spawn", true)
		door.set("linked_spawn_gx", link["spawn"] as Vector3)
		door.set("linked_spawn_yaw", WorldGrid.yaw_for_furniture(link["facing"] as WorldGrid.Facing))
		_size_museum_wing_door(door, link["sensor"] as Vector3)
		root.add_child(door)


func _size_museum_wing_door(door: Node3D, sensor_gx: Vector3) -> void:
	## Fill the wall opening (~2 UT / 80 GX) so the player cannot slip past the sensor.
	## North/south openings (z near 80/520) are wide in X; east/west openings wide in Z.
	var wide: float = 80.0 * FieldCatalog.GX_TO_METERS
	var deep: float = 40.0 * FieldCatalog.GX_TO_METERS
	var tall: float = 2.6
	var along_x: bool = sensor_gx.z < 200.0 or sensor_gx.z > 400.0
	var box := Vector3(wide, tall, deep) if along_x else Vector3(deep, tall, wide)
	HostCollision.resize_interact_box(door, box)
