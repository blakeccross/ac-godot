class_name WorldGrid
extends RefCounted

## Logical cell grid for one outdoor plot. Godot-native; not a port of m_field_info.

enum Terrain { GRASS, SOIL, WATER, BLOCKED }
enum Facing { SOUTH, EAST, NORTH, WEST }
enum PlaceKind { ITEM, PLANT, BUILDING, FURNITURE }

const FACING_COUNT := 4

signal occupancy_changed(cell: Vector2i, occupant: StringName)

var columns: int = 16
var rows: int = 16
var cell_size: float = 2.0
## Minimum-corner of cell (0, 0) on the XZ plane.
var origin: Vector3 = Vector3(-16.0, 0.0, -16.0)

var _terrain: PackedByteArray = PackedByteArray()
var _occupant: Dictionary = {}
var _cells_of: Dictionary = {}


func configure(p_columns: int, p_rows: int, p_cell_size: float, p_origin: Vector3) -> void:
	columns = maxi(p_columns, 1)
	rows = maxi(p_rows, 1)
	cell_size = maxf(p_cell_size, 0.001)
	origin = p_origin
	clear()


func configure_from_acre(data: AcreData) -> void:
	var cols: int = data.columns if data else 16
	var rws: int = data.rows if data else 16
	var size: Vector2 = data.size if data else Vector2(32, 32)
	var cs: float = size.x / float(cols)
	var org := Vector3(-size.x * 0.5, 0.0, -size.y * 0.5)
	configure(cols, rws, cs, org)
	if data == null:
		return
	for cell: Vector2i in data.water_cells:
		set_terrain(cell, Terrain.WATER)
	for cell: Vector2i in data.soil_cells:
		set_terrain(cell, Terrain.SOIL)
	for cell: Vector2i in data.blocked_cells:
		set_terrain(cell, Terrain.BLOCKED)


func clear() -> void:
	_occupant.clear()
	_cells_of.clear()
	_terrain.resize(columns * rows)
	_terrain.fill(Terrain.GRASS)


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < columns and cell.y < rows


func world_to_cell(world_pos: Vector3) -> Vector2i:
	var local_x: float = world_pos.x - origin.x
	var local_z: float = world_pos.z - origin.z
	return Vector2i(floori(local_x / cell_size), floori(local_z / cell_size))


func cell_to_world(cell: Vector2i) -> Vector3:
	return origin + Vector3((float(cell.x) + 0.5) * cell_size, 0.0, (float(cell.y) + 0.5) * cell_size)


func cell_corner(cell: Vector2i) -> Vector3:
	return origin + Vector3(float(cell.x) * cell_size, 0.0, float(cell.y) * cell_size)


func rotate_facing(facing: Facing, steps: int) -> Facing:
	var idx: int = (int(facing) + steps) % FACING_COUNT
	if idx < 0:
		idx += FACING_COUNT
	return idx as Facing


func rotate_offset(offset: Vector2i, facing: Facing) -> Vector2i:
	match facing:
		Facing.SOUTH:
			return offset
		Facing.EAST:
			return Vector2i(offset.y, -offset.x)
		Facing.NORTH:
			return Vector2i(-offset.x, -offset.y)
		Facing.WEST:
			return Vector2i(-offset.y, offset.x)
		_:
			return offset


func footprint_cells(anchor: Vector2i, size: Vector2i, facing: Facing = Facing.SOUTH) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var w: int = maxi(size.x, 1)
	var d: int = maxi(size.y, 1)
	for x: int in w:
		for z: int in d:
			cells.append(anchor + rotate_offset(Vector2i(x, z), facing))
	return cells


func footprint_center(anchor: Vector2i, size: Vector2i, facing: Facing = Facing.SOUTH) -> Vector3:
	var cells: Array[Vector2i] = footprint_cells(anchor, size, facing)
	if cells.is_empty():
		return cell_to_world(anchor)
	var acc := Vector3.ZERO
	for cell: Vector2i in cells:
		acc += cell_to_world(cell)
	return acc / float(cells.size())


func anchor_from_world_center(world_pos: Vector3, size: Vector2i, facing: Facing = Facing.SOUTH) -> Vector2i:
	var w: int = maxi(size.x, 1)
	var d: int = maxi(size.y, 1)
	var local_min := rotate_offset(Vector2i(0, 0), facing)
	var local_max := rotate_offset(Vector2i(w - 1, d - 1), facing)
	var min_x: int = mini(local_min.x, local_max.x)
	var min_z: int = mini(local_min.y, local_max.y)
	var max_x: int = maxi(local_min.x, local_max.x)
	var max_z: int = maxi(local_min.y, local_max.y)
	var extent := Vector3(float(max_x - min_x + 1) * cell_size, 0.0, float(max_z - min_z + 1) * cell_size)
	var min_world: Vector3 = world_pos - extent * 0.5
	var inset := Vector3(cell_size * 0.25, 0.0, cell_size * 0.25)
	return world_to_cell(min_world + inset)


func neighbors4(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for offset: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		var n: Vector2i = cell + offset
		if is_in_bounds(n):
			out.append(n)
	return out


func neighbors8(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x: int in range(-1, 2):
		for z: int in range(-1, 2):
			if x == 0 and z == 0:
				continue
			var n := Vector2i(cell.x + x, cell.y + z)
			if is_in_bounds(n):
				out.append(n)
	return out


func terrain_at(cell: Vector2i) -> Terrain:
	if not is_in_bounds(cell):
		return Terrain.BLOCKED
	return _terrain[_index(cell)] as Terrain


func set_terrain(cell: Vector2i, terrain: Terrain) -> void:
	if not is_in_bounds(cell):
		return
	_terrain[_index(cell)] = terrain


func is_walkable(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	var t: Terrain = terrain_at(cell)
	return t == Terrain.GRASS or t == Terrain.SOIL


func occupant_at(cell: Vector2i) -> StringName:
	if not _occupant.has(cell):
		return &""
	return _occupant[cell] as StringName


func cells_of(occupant_id: StringName) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if occupant_id == &"" or not _cells_of.has(occupant_id):
		return out
	var raw: Array = _cells_of[occupant_id]
	for cell: Variant in raw:
		out.append(cell as Vector2i)
	return out


func is_occupied(cell: Vector2i) -> bool:
	return occupant_at(cell) != &""


func can_place(
	anchor: Vector2i,
	size: Vector2i,
	facing: Facing,
	kind: PlaceKind,
	ignore_id: StringName = &""
) -> bool:
	var cells: Array[Vector2i] = footprint_cells(anchor, size, facing)
	if cells.is_empty():
		return false
	for cell: Vector2i in cells:
		if not is_in_bounds(cell):
			return false
		if not _terrain_allows(terrain_at(cell), kind):
			return false
		var who: StringName = occupant_at(cell)
		if who != &"" and who != ignore_id:
			return false
	return true


func place(
	occupant_id: StringName,
	anchor: Vector2i,
	size: Vector2i,
	facing: Facing,
	kind: PlaceKind
) -> bool:
	if occupant_id == &"":
		return false
	if _cells_of.has(occupant_id):
		return false
	if not can_place(anchor, size, facing, kind):
		return false
	var cells: Array[Vector2i] = footprint_cells(anchor, size, facing)
	_cells_of[occupant_id] = cells.duplicate()
	for cell: Vector2i in cells:
		_occupant[cell] = occupant_id
		occupancy_changed.emit(cell, occupant_id)
	return true


func remove(occupant_id: StringName) -> void:
	if occupant_id == &"" or not _cells_of.has(occupant_id):
		return
	var cells: Array[Vector2i] = cells_of(occupant_id)
	_cells_of.erase(occupant_id)
	for cell: Vector2i in cells:
		if occupant_at(cell) == occupant_id:
			_occupant.erase(cell)
			occupancy_changed.emit(cell, &"")


func _terrain_allows(terrain: Terrain, kind: PlaceKind) -> bool:
	match terrain:
		Terrain.BLOCKED:
			return false
		Terrain.WATER:
			return false
		Terrain.SOIL:
			return kind != PlaceKind.BUILDING
		_:
			return true


func _index(cell: Vector2i) -> int:
	return cell.y * columns + cell.x
