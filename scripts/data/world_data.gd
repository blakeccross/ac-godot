class_name WorldData
extends Resource

## Town layout as data. Not a dump of every tree into world.tscn.
## Terrain bytes use WorldGrid.Terrain. Elevation is 0–3 (original combo height).

enum Mode { TEST, GENERATED, REFERENCE }

@export var id: StringName = &""
@export var display_name: String = ""
@export var mode: Mode = Mode.TEST
@export var seed_value: int = 0
@export var columns: int = 16
@export var rows: int = 16
@export var cell_size: float = 2.0
@export var terrain: PackedByteArray = PackedByteArray()
@export var elevation: PackedByteArray = PackedByteArray()
@export var water_cells: Array[Vector2i] = []
@export var sand_cells: Array[Vector2i] = []
@export var path_cells: Array[Vector2i] = []
@export var cliff_cells: Array[Vector2i] = []
@export var buildings: Array[BuildingPlacement] = []
@export var objects: Array[ObjectPlacement] = []
@export var spawn_points: Array[SpawnPoint] = []
## Original acre mesh (`BG_TYPE_GRD_S_F_1` → `grd_s_f_1`). Empty keeps the placeholder plane.
@export var acre_visual: StringName = &"grd_s_f_1"
## Full 7×10 `mFM_BLOCK_TYPE_*` grid from TownFieldGenerator (70 bytes). Empty for test town.
@export var acre_types: PackedByteArray = PackedByteArray()
@export var acre_heights: PackedByteArray = PackedByteArray()
## Per-block `grd_*` visual ids (70 entries, parallel to acre_types). Empty string = no mesh.
@export var acre_visuals: PackedStringArray = PackedStringArray()


func origin() -> Vector3:
	var size_x: float = float(columns) * cell_size
	var size_z: float = float(rows) * cell_size
	return Vector3(-size_x * 0.5, 0.0, -size_z * 0.5)


func cell_to_world(cell: Vector2i) -> Vector3:
	var org: Vector3 = origin()
	return org + Vector3((float(cell.x) + 0.5) * cell_size, 0.0, (float(cell.y) + 0.5) * cell_size)


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < columns and cell.y < rows


func bake() -> void:
	_ensure_grids()
	_paint(water_cells, WorldGrid.Terrain.WATER)
	_paint(sand_cells, WorldGrid.Terrain.SAND)
	_paint(path_cells, WorldGrid.Terrain.PATH)
	_paint(cliff_cells, WorldGrid.Terrain.CLIFF)


func terrain_at(cell: Vector2i) -> WorldGrid.Terrain:
	if not is_in_bounds(cell):
		return WorldGrid.Terrain.BLOCKED
	_ensure_grids()
	return terrain[_index(cell)] as WorldGrid.Terrain


func set_terrain_cell(cell: Vector2i, value: WorldGrid.Terrain) -> void:
	if not is_in_bounds(cell):
		return
	_ensure_grids()
	terrain[_index(cell)] = value


func elevation_at(cell: Vector2i) -> int:
	if not is_in_bounds(cell):
		return 0
	_ensure_grids()
	return int(elevation[_index(cell)])


func set_elevation_cell(cell: Vector2i, value: int) -> void:
	if not is_in_bounds(cell):
		return
	_ensure_grids()
	elevation[_index(cell)] = clampi(value, 0, 3)


func player_spawn() -> SpawnPoint:
	for spawn: SpawnPoint in spawn_points:
		if spawn != null and spawn.id == &"player":
			return spawn
	var fallback := SpawnPoint.new()
	fallback.id = &"player"
	fallback.cell = Vector2i(columns / 2, rows / 2)
	return fallback


func fingerprint() -> String:
	bake()
	var building_bits: PackedStringArray = PackedStringArray()
	for b: BuildingPlacement in buildings:
		if b == null:
			continue
		building_bits.append("%s:%s:%d,%d" % [String(b.id), String(b.kind), b.cell.x, b.cell.y])
	var object_bits: PackedStringArray = PackedStringArray()
	for o: ObjectPlacement in objects:
		if o == null:
			continue
		object_bits.append("%s:%s:%d,%d" % [String(o.id), String(o.kind), o.cell.x, o.cell.y])
	return "%s|%s|%s|%s|%s" % [
		terrain.hex_encode(),
		elevation.hex_encode(),
		",".join(building_bits),
		",".join(object_bits),
		"%d,%d" % [player_spawn().cell.x, player_spawn().cell.y],
	]


func _ensure_grids() -> void:
	var n: int = maxi(columns, 1) * maxi(rows, 1)
	if terrain.size() != n:
		terrain.resize(n)
		terrain.fill(WorldGrid.Terrain.GRASS)
	if elevation.size() != n:
		elevation.resize(n)
		elevation.fill(0)


func _paint(cells: Array[Vector2i], value: WorldGrid.Terrain) -> void:
	for cell: Vector2i in cells:
		set_terrain_cell(cell, value)


func _index(cell: Vector2i) -> int:
	return cell.y * columns + cell.x
