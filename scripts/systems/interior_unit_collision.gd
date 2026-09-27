class_name InteriorUnitCollision
extends RefCounted

## Solid hulls for the units an original indoor field blocks (`mCoBG` unit heights, the
## shop tables). Shell meshes carry no physics and `InteriorShellBuilder.add_shell_collision`
## only builds the floor slab, the outer walls and the door gaps, so raised furniture and
## inner wall runs (police shelves, Able's counters, the Cranny's south wall and tables)
## need these. Heights are GX above the room floor.

## Blocking walls stand as tall as the shell's collision walls.
const WALL_GX := InteriorShellBuilder.WALL_HEIGHT / FieldCatalog.GX_TO_METERS

static var _bg_cache: Dictionary = {}


## Centre height counts (`c`) of a shell's 256 BG units from its `.col.json`. Empty when the
## pipeline has not generated it. Read directly: `AcreGrid` drops mostly-`HEIGHT_MAX` tables
## as fillers, and an interior shell is mostly wall.
static func bg_counts(shell_id: StringName) -> PackedInt32Array:
	if _bg_cache.has(shell_id):
		return _bg_cache[shell_id] as PackedInt32Array
	var out := PackedInt32Array()
	var path := FieldCatalog.GENERATED_ROOT + "environment/acres/%s.col.json" % shell_id
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var rows: Variant = (parsed as Dictionary).get("units", []) if parsed is Dictionary else []
		if rows is Array and (rows as Array).size() == FieldCatalog.UNITS_PER_ACRE:
			for row: Variant in rows:
				out.append(int((row as Dictionary).get("c", FieldCatalog.LAND_COUNTS)))
	_bg_cache[shell_id] = out
	return out


## Units in `rect` whose BG height differs from the floor: unit → height in GX. Raised
## furniture keeps its own height (`mCoBG` counts × 10); walls (`wall_counts` and up) and
## sunken units get `WALL_GX`.
static func blocked_from_bg(
	shell_id: StringName, floor_counts: int, wall_counts: int, rect: Rect2i
) -> Dictionary:
	var out: Dictionary = {}
	var counts: PackedInt32Array = bg_counts(shell_id)
	if counts.size() != FieldCatalog.UNITS_PER_ACRE:
		return out
	for z: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if x < 0 or x >= 16 or z < 0 or z >= 16:
				continue
			var c: int = counts[z * 16 + x]
			if c == floor_counts:
				continue
			if c > floor_counts and c < wall_counts:
				out[Vector2i(x, z)] = float(c - floor_counts) * 10.0
			else:
				out[Vector2i(x, z)] = WALL_GX
	return out


## One `StaticBody3D` named `body_name` under `root`, one box per run of equal-height units
## along each row. Idempotent: an existing body of that name is kept.
static func add_hulls(
	root: Node3D, grid: WorldGrid, body_name: String, blocked: Dictionary
) -> StaticBody3D:
	var existing: StaticBody3D = root.get_node_or_null(body_name) as StaticBody3D
	if existing != null or blocked.is_empty() or grid == null:
		return existing
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var cells: Array = blocked.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell: Vector2i in cells:
		var h_gx: float = blocked[cell]
		if blocked.get(cell - Vector2i(1, 0), -1.0) == h_gx:
			continue
		var run := 1
		while blocked.get(cell + Vector2i(run, 0), -1.0) == h_gx:
			run += 1
		var h: float = h_gx * FieldCatalog.GX_TO_METERS
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(grid.cell_size * run, h, grid.cell_size)
		shape.shape = box
		var west: Vector3 = MuseumDisplay.gx_to_world(
			grid, Vector3(float(cell.x) * 40.0, 0.0, float(cell.y) * 40.0 + 20.0)
		)
		shape.position = west + Vector3(grid.cell_size * run * 0.5, h * 0.5, 0.0)
		body.add_child(shape)
	return body
