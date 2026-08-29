class_name FieldCollision
extends RefCounted

## Walls plus a height query. Behavioral analog of `mCoBG`: each `grd_*` ships a 16×16
## table (center + four corners × 10 GX, attribute, slate). Cardinal walls are thin
## trapezoid *segments* on unit edges where neighbor corners differ; slate units also
## get a 45° diagonal. Oriented boxes / prism triangles — not convex hulls, which fill
## the square between a diagonal and a cardinal wall. Not the `grd_*` triangle mesh.
## columns remain only when the pipeline JSON is missing.

## World-Y sentinel. Catalog water sits below land (count 0 → −2 m); never use `y < 0`.
const NO_FLOOR := -10000.0
## `unit_rel_at` hole on a geometric cliff face (0–1 terrace space, not meters).
const FACE_HOLE := -1.0
## Horizontal cliff face in unit Z (north = 0). Matches `grd_s_c1_*` high-north / low-south.
const NS_FACE0 := 10.0
const NS_FACE1 := 12.0
## Vertical cliff face in unit X. `grd_s_c3_*` is already low by unit 11; 12 marked the
## first low terrace as a wall.
const EW_FACE0 := 8.0
const EW_FACE1 := 11.0
const RAMP0 := 6.0
const RAMP1 := 12.0
const EDGE_EPS := 0.25
## Convex wall thickness. Original walls are infinitely thin 2D segments vs actor radius (~18 GX).
## Thickness lives on the *low* side so the high terrace does not get a lip to snag on.
const WALL_THICK := 0.24
## Raise the lid above the actor so 3D physics hits a vertical face, not a ledge.
const WALL_TOP_CLEARANCE := 1.4
const _SLATE_UP := 1
const _SLATE_DOWN := 2


static func has_floor(y: float) -> bool:
	return y > NO_FLOOR


static func add_to(root: Node3D, data: WorldData, grid: WorldGrid) -> void:
	if root == null or data == null or grid == null:
		return
	data.bake()
	var body := StaticBody3D.new()
	body.name = "Heightfield"
	body.collision_layer = 1
	body.collision_mask = 0
	for z: int in data.rows:
		for x: int in data.columns:
			var cell := Vector2i(x, z)
			if _uses_solid_column(data, cell):
				_add_column_box(body, data, grid, cell)
			_add_catalog_edge_walls(body, data, grid, cell)
			_add_slate_wall(body, data, grid, cell)
	if body.get_child_count() == 0:
		body.free()
		return
	root.add_child(body)


static func ground_y(data: WorldData, cell: Vector2i, ground_dist: float = 0.0) -> float:
	## Placement helper: unit-center height (`GetBgY_OnlyCenter_FromWpos2`). `ground_dist` is meters subtracted from that height (original passes GX; holes use −1 GX). Terrace fallback so signs still spawn.
	var y: float = height_at(data, cell)
	if not has_floor(y):
		y = float(data.elevation_at(cell)) * FieldCatalog.ACRE_STEP_METERS
	return y - ground_dist


static func ground_y_at(
	data: WorldData, grid: WorldGrid, world_pos: Vector3, ground_dist: float = 0.0
) -> float:
	## `mCoBG_GetBgY_AngleS_FromWpos`: bilinear height at the actual XZ, not the unit center.
	## Catalog water has a floor (original wades). Authored ponds / geometric faces do not.
	if data == null or grid == null:
		return NO_FLOOR
	var cell: Vector2i = grid.world_to_cell(world_pos)
	if not data.is_in_bounds(cell):
		return NO_FLOOR
	var ys: PackedFloat32Array = _cell_floor_ys(data, cell)
	if ys.is_empty():
		return NO_FLOOR
	var c0: Vector3 = grid.cell_corner(cell)
	var cs: float = grid.cell_size
	var fx: float = clampf((world_pos.x - c0.x) / cs, 0.0, 1.0)
	var fz: float = clampf((world_pos.z - c0.z) / cs, 0.0, 1.0)
	var north: float = lerpf(ys[0], ys[1], fx)
	var south: float = lerpf(ys[3], ys[2], fx)
	return lerpf(north, south, fz) - ground_dist


static func revise_xz(
	data: WorldData, grid: WorldGrid, from: Vector3, to: Vector3
) -> Vector3:
	## `mCoBG_CarryOutReverse`: keep XZ on the last walkable side of a wall / water bank.
	if data == null or grid == null:
		return to
	var from_cell: Vector2i = grid.world_to_cell(from)
	var to_cell: Vector2i = grid.world_to_cell(to)
	if _should_restore(data, from_cell, to_cell):
		return Vector3(from.x, _keep_y(data, grid, from), from.z)
	var y: float = ground_y_at(data, grid, to)
	if not has_floor(y):
		return Vector3(from.x, _keep_y(data, grid, from), from.z)
	return Vector3(to.x, y, to.z)


static func height_at(data: WorldData, cell: Vector2i) -> float:
	if data == null or not data.is_in_bounds(cell):
		return NO_FLOOR
	var t: WorldGrid.Terrain = data.terrain_at(cell)
	var unit: Dictionary = _catalog_unit(data, cell)
	if t == WorldGrid.Terrain.BLOCKED:
		return NO_FLOOR
	if t == WorldGrid.Terrain.WATER:
		if unit.is_empty() or not FieldCatalog.is_water_attr(int(unit["a"])):
			return NO_FLOOR
		return FieldCatalog.counts_to_y(int(unit["c"]), int(_acre_elev(data, cell)))
	if t == WorldGrid.Terrain.CLIFF and unit.is_empty():
		return NO_FLOOR
	if not unit.is_empty():
		return FieldCatalog.counts_to_y(int(unit["c"]), int(_acre_elev(data, cell)))
	var shape: int = _shape_at(data, cell)
	if shape >= 0:
		var rel: float = unit_rel_at(
			shape, TownFieldGenerator.is_slope(_type_at(data, cell)), _ux_at(cell) + 0.5, _uz_at(cell) + 0.5
		)
		if rel < 0.0:
			return NO_FLOOR
		return (_acre_elev(data, cell) + rel) * FieldCatalog.ACRE_STEP_METERS
	return float(data.elevation_at(cell)) * FieldCatalog.ACRE_STEP_METERS


static func unit_rel_at(shape: int, slope: bool, fx: float, fz: float) -> float:
	## Relative height above the acre base: 1 = upper terrace, 0 = lower, FACE_HOLE = cliff face.
	var ns_lo: float = RAMP0 if slope else NS_FACE0
	var ns_hi: float = RAMP1 if slope else NS_FACE1
	var ew_lo: float = RAMP0 if slope else EW_FACE0
	var ew_hi: float = RAMP1 if slope else EW_FACE1
	var ns: float = _band(slope, fz, ns_lo, ns_hi, true)
	var ew_w: float = _band(slope, fx, ew_lo, ew_hi, true)
	var ew_e: float = _band(slope, fx, ew_lo, ew_hi, false)
	match shape:
		0:
			return ns
		1:
			return _combine_min(ns, ew_w)
		2:
			return ew_w
		3:
			return _combine_max(ns, ew_w)
		4:
			return _combine_max(ns, ew_e)
		5:
			return ew_e
		6:
			return _combine_min(ns, ew_e)
		_:
			return 0.0


static func _band(slope: bool, s: float, lo: float, hi: float, high_at_low_s: bool) -> float:
	var t: float
	if s <= lo:
		t = 1.0
	elif s >= hi:
		t = 0.0
	elif slope:
		t = 1.0 - (s - lo) / (hi - lo)
	else:
		return FACE_HOLE
	return t if high_at_low_s else 1.0 - t


static func _combine_min(a: float, b: float) -> float:
	if a < 0.0 or b < 0.0:
		return FACE_HOLE
	return minf(a, b)


static func _combine_max(a: float, b: float) -> float:
	if a < 0.0 and b < 0.0:
		return FACE_HOLE
	return maxf(a, b)


static func _cell_floor_ys(data: WorldData, cell: Vector2i) -> PackedFloat32Array:
	var t: WorldGrid.Terrain = data.terrain_at(cell)
	var unit: Dictionary = _catalog_unit(data, cell)
	if t == WorldGrid.Terrain.BLOCKED:
		return PackedFloat32Array()
	if t == WorldGrid.Terrain.WATER:
		if unit.is_empty() or not FieldCatalog.is_water_attr(int(unit["a"])):
			return PackedFloat32Array()
		return _catalog_corners(unit, int(_acre_elev(data, cell)))
	if t == WorldGrid.Terrain.CLIFF and unit.is_empty():
		return PackedFloat32Array()
	if not unit.is_empty():
		return _catalog_corners(unit, int(_acre_elev(data, cell)))
	var center: float = height_at(data, cell)
	if not has_floor(center):
		return PackedFloat32Array()
	var out := PackedFloat32Array()
	out.resize(4)
	var shape: int = _shape_at(data, cell)
	if shape >= 0:
		var slope: bool = TownFieldGenerator.is_slope(_type_at(data, cell))
		var base: float = _acre_elev(data, cell) * FieldCatalog.ACRE_STEP_METERS
		var ux: float = _ux_at(cell)
		var uz: float = _uz_at(cell)
		var rels: Array[float] = [
			unit_rel_at(shape, slope, ux, uz),
			unit_rel_at(shape, slope, ux + 1.0, uz),
			unit_rel_at(shape, slope, ux + 1.0, uz + 1.0),
			unit_rel_at(shape, slope, ux, uz + 1.0),
		]
		for i: int in 4:
			var rel: float = rels[i]
			out[i] = center if rel < 0.0 else base + rel * FieldCatalog.ACRE_STEP_METERS
		return out
	for i: int in 4:
		out[i] = center
	return out


static func _catalog_corners(unit: Dictionary, elev: int) -> PackedFloat32Array:
	var catalog_ys := PackedFloat32Array()
	catalog_ys.resize(4)
	catalog_ys[0] = FieldCatalog.counts_to_y(int(unit["nw"]), elev)
	catalog_ys[1] = FieldCatalog.counts_to_y(int(unit["ne"]), elev)
	catalog_ys[2] = FieldCatalog.counts_to_y(int(unit["se"]), elev)
	catalog_ys[3] = FieldCatalog.counts_to_y(int(unit["sw"]), elev)
	return catalog_ys


static func _keep_y(data: WorldData, grid: WorldGrid, pos: Vector3) -> float:
	var y: float = ground_y_at(data, grid, pos)
	return y if has_floor(y) else pos.y


static func _should_restore(data: WorldData, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if not data.is_in_bounds(to_cell):
		return true
	if _forbids_enter(data, to_cell) and not _forbids_enter(data, from_cell):
		return true
	if from_cell == to_cell:
		return false
	if from_cell.x != to_cell.x:
		if _edge_is_wall(data, from_cell, Vector2i(to_cell.x, from_cell.y)):
			return true
	if from_cell.y != to_cell.y:
		if _edge_is_wall(data, from_cell, Vector2i(from_cell.x, to_cell.y)):
			return true
	if from_cell.x != to_cell.x and from_cell.y != to_cell.y:
		if _edge_is_wall(data, Vector2i(to_cell.x, from_cell.y), to_cell):
			return true
		if _edge_is_wall(data, Vector2i(from_cell.x, to_cell.y), to_cell):
			return true
	return false


static func _forbids_enter(data: WorldData, cell: Vector2i) -> bool:
	if not data.is_in_bounds(cell):
		return true
	var t: WorldGrid.Terrain = data.terrain_at(cell)
	if t == WorldGrid.Terrain.WATER or t == WorldGrid.Terrain.BLOCKED:
		return true
	if t == WorldGrid.Terrain.CLIFF and _catalog_unit(data, cell).is_empty():
		return true
	return false


static func _edge_is_wall(data: WorldData, a: Vector2i, b: Vector2i) -> bool:
	## `mCoBG_SearchWallFlag`: shared-edge corner heights differ.
	if not data.is_in_bounds(a) or not data.is_in_bounds(b):
		return true
	if absi(a.x - b.x) + absi(a.y - b.y) != 1:
		return false
	var ua: Dictionary = _catalog_unit(data, a)
	var ub: Dictionary = _catalog_unit(data, b)
	if not ua.is_empty() and not ub.is_empty():
		return _catalog_edge_delta(data, a, b, ua, ub) >= EDGE_EPS
	var ha: float = height_at(data, a)
	var hb: float = height_at(data, b)
	if not has_floor(ha) or not has_floor(hb):
		return true
	return absf(ha - hb) >= EDGE_EPS


static func _catalog_edge_delta(
	data: WorldData, a: Vector2i, b: Vector2i, ua: Dictionary, ub: Dictionary
) -> float:
	if absi(a.x - b.x) + absi(a.y - b.y) != 1:
		return 0.0
	var ea: int = int(_acre_elev(data, a))
	var eb: int = int(_acre_elev(data, b))
	var a0: float
	var a1: float
	var b0: float
	var b1: float
	if a.x + 1 == b.x:
		a0 = FieldCatalog.counts_to_y(int(ua["ne"]), ea)
		a1 = FieldCatalog.counts_to_y(int(ua["se"]), ea)
		b0 = FieldCatalog.counts_to_y(int(ub["nw"]), eb)
		b1 = FieldCatalog.counts_to_y(int(ub["sw"]), eb)
	elif b.x + 1 == a.x:
		return _catalog_edge_delta(data, b, a, ub, ua)
	elif a.y + 1 == b.y:
		a0 = FieldCatalog.counts_to_y(int(ua["sw"]), ea)
		a1 = FieldCatalog.counts_to_y(int(ua["se"]), ea)
		b0 = FieldCatalog.counts_to_y(int(ub["nw"]), eb)
		b1 = FieldCatalog.counts_to_y(int(ub["ne"]), eb)
	else:
		return _catalog_edge_delta(data, b, a, ub, ua)
	return maxf(absf(a0 - b0), absf(a1 - b1))


static func _shape_at(data: WorldData, cell: Vector2i) -> int:
	return TownFieldGenerator.cliff_shape(_type_at(data, cell))


static func _type_at(data: WorldData, cell: Vector2i) -> int:
	if data.acre_types.size() != TownFieldGenerator.BLOCK_TOTAL:
		return -1
	var bx: int = int(cell.x / WorldGenerator.UT) + 1
	var bz: int = int(cell.y / WorldGenerator.UT) + 1
	if bx < 1 or bx > 5 or bz < 1 or bz > 6:
		return -1
	return int(data.acre_types[bz * TownFieldGenerator.BLOCK_X + bx])


static func _acre_elev(data: WorldData, cell: Vector2i) -> float:
	if data.acre_heights.size() != TownFieldGenerator.BLOCK_TOTAL:
		return float(data.elevation_at(cell))
	var bx: int = int(cell.x / WorldGenerator.UT) + 1
	var bz: int = int(cell.y / WorldGenerator.UT) + 1
	if bx < 1 or bx > 5 or bz < 1 or bz > 6:
		return float(data.elevation_at(cell))
	return float(data.acre_heights[bz * TownFieldGenerator.BLOCK_X + bx])


static func _acre_base_y(data: WorldData, cell: Vector2i) -> float:
	return _acre_elev(data, cell) * FieldCatalog.ACRE_STEP_METERS


static func _visual_at(data: WorldData, cell: Vector2i) -> StringName:
	if data.acre_visuals.size() == TownFieldGenerator.BLOCK_TOTAL:
		var bx: int = int(cell.x / WorldGenerator.UT) + 1
		var bz: int = int(cell.y / WorldGenerator.UT) + 1
		if bx >= 1 and bx <= 5 and bz >= 1 and bz <= 6:
			return StringName(data.acre_visuals[bz * TownFieldGenerator.BLOCK_X + bx])
	return data.acre_visual


static func _catalog_unit(data: WorldData, cell: Vector2i) -> Dictionary:
	if data == null or not data.is_in_bounds(cell):
		return {}
	return FieldCatalog.unit_at(
		_visual_at(data, cell), posmod(cell.x, WorldGenerator.UT), posmod(cell.y, WorldGenerator.UT)
	)


static func _uses_solid_column(data: WorldData, cell: Vector2i) -> bool:
	var t: WorldGrid.Terrain = data.terrain_at(cell)
	if t == WorldGrid.Terrain.BLOCKED:
		return true
	if t == WorldGrid.Terrain.WATER:
		var unit: Dictionary = _catalog_unit(data, cell)
		return unit.is_empty() or not FieldCatalog.is_water_attr(int(unit["a"]))
	if t == WorldGrid.Terrain.CLIFF:
		return _catalog_unit(data, cell).is_empty()
	return false


static func _add_column_box(body: StaticBody3D, data: WorldData, grid: WorldGrid, cell: Vector2i) -> void:
	var t: WorldGrid.Terrain = data.terrain_at(cell)
	var base: float = _acre_base_y(data, cell)
	var y0: float = base
	var y1: float = base + FieldCatalog.ACRE_STEP_METERS + 0.5
	if t == WorldGrid.Terrain.WATER:
		y0 = base - 2.5
		y1 = base + 2.5
	var c0: Vector3 = grid.cell_corner(cell)
	var cs: float = grid.cell_size
	_add_box(
		body,
		Vector3(c0.x + cs * 0.5, (y0 + y1) * 0.5, c0.z + cs * 0.5),
		Vector3(cs, maxf(y1 - y0, 0.2), cs)
	)


static func _add_catalog_edge_walls(
	body: StaticBody3D, data: WorldData, grid: WorldGrid, cell: Vector2i
) -> void:
	if _catalog_unit(data, cell).is_empty():
		return
	var east := Vector2i(cell.x + 1, cell.y)
	if data.is_in_bounds(east):
		_maybe_height_wall(body, data, grid, cell, east, true)
	var south := Vector2i(cell.x, cell.y + 1)
	if data.is_in_bounds(south):
		_maybe_height_wall(body, data, grid, cell, south, false)


static func _maybe_height_wall(
	body: StaticBody3D,
	data: WorldData,
	grid: WorldGrid,
	a: Vector2i,
	b: Vector2i,
	east: bool
) -> void:
	if _uses_solid_column(data, a) and _uses_solid_column(data, b):
		return
	var ua: Dictionary = _catalog_unit(data, a)
	var ub: Dictionary = _catalog_unit(data, b)
	if ua.is_empty() or ub.is_empty():
		return
	## Two slate units: original skips the cardinal segment; the 45° walls cover it.
	if _unit_is_slate(ua) and _unit_is_slate(ub):
		return
	var ua_src: Dictionary = ua
	var ub_src: Dictionary = ub
	var mixed_slate: bool = _unit_is_slate(ua_src) != _unit_is_slate(ub_src)
	var ea: int = int(_acre_elev(data, a))
	var eb: int = int(_acre_elev(data, b))
	var pre0: float
	var pre1: float
	if east:
		pre0 = absf(
			FieldCatalog.counts_to_y(int(ua_src["ne"]), ea)
			- FieldCatalog.counts_to_y(int(ub_src["nw"]), eb)
		)
		pre1 = absf(
			FieldCatalog.counts_to_y(int(ua_src["se"]), ea)
			- FieldCatalog.counts_to_y(int(ub_src["sw"]), eb)
		)
	else:
		pre0 = absf(
			FieldCatalog.counts_to_y(int(ua_src["sw"]), ea)
			- FieldCatalog.counts_to_y(int(ub_src["nw"]), eb)
		)
		pre1 = absf(
			FieldCatalog.counts_to_y(int(ua_src["se"]), ea)
			- FieldCatalog.counts_to_y(int(ub_src["ne"]), eb)
		)
	ua = _flatten_slate_for_edge(ua_src, ub_src, east, true)
	ub = _flatten_slate_for_edge(ub_src, ua_src, east, false)
	## Flatten decides whether a cardinal exists (`UtInf2NormalSlateWallVector`).
	if _catalog_edge_delta(data, a, b, ua, ub) < EDGE_EPS:
		return
	var a0: float
	var a1: float
	var b0: float
	var b1: float
	if east:
		a0 = FieldCatalog.counts_to_y(int(ua["ne"]), ea)
		a1 = FieldCatalog.counts_to_y(int(ua["se"]), ea)
		b0 = FieldCatalog.counts_to_y(int(ub["nw"]), eb)
		b1 = FieldCatalog.counts_to_y(int(ub["sw"]), eb)
	else:
		a0 = FieldCatalog.counts_to_y(int(ua["sw"]), ea)
		a1 = FieldCatalog.counts_to_y(int(ua["se"]), ea)
		b0 = FieldCatalog.counts_to_y(int(ub["nw"]), eb)
		b1 = FieldCatalog.counts_to_y(int(ub["ne"]), eb)
	var y_lo0: float = minf(a0, b0)
	var y_hi0: float = maxf(a0, b0)
	var y_lo1: float = minf(a1, b1)
	var y_hi1: float = maxf(a1, b1)
	if y_hi0 - y_lo0 < EDGE_EPS and y_hi1 - y_lo1 < EDGE_EPS:
		return
	var c0: Vector3 = grid.cell_corner(a)
	var cs: float = grid.cell_size
	var ax: float
	var az: float
	var bx: float
	var bz: float
	if east:
		ax = c0.x + cs
		az = c0.z
		bx = ax
		bz = c0.z + cs
	else:
		ax = c0.x
		az = c0.z + cs
		bx = c0.x + cs
		bz = az
	## Flatten can raise the notch corner and invent a full-edge wall that sits in front of
	## the 45° face. Keep only the half that already had a height jump before flatten.
	if mixed_slate:
		var need0: bool = pre0 >= EDGE_EPS
		var need1: bool = pre1 >= EDGE_EPS
		if need0 and not need1:
			bx = (ax + bx) * 0.5
			bz = (az + bz) * 0.5
			y_lo1 = y_lo0
			y_hi1 = y_hi0
		elif need1 and not need0:
			ax = (ax + bx) * 0.5
			az = (az + bz) * 0.5
			y_lo0 = y_lo1
			y_hi0 = y_hi1
		elif not need0 and not need1:
			return
	var low_hint: Vector2
	if east:
		low_hint = Vector2.RIGHT if (a0 + a1) >= (b0 + b1) else Vector2.LEFT
	else:
		low_hint = Vector2.DOWN if (a0 + a1) >= (b0 + b1) else Vector2.UP
	_add_segment_wall(body, ax, az, bx, bz, y_lo0, y_hi0, y_lo1, y_hi1, low_hint)


static func _add_slate_wall(
	body: StaticBody3D, data: WorldData, grid: WorldGrid, cell: Vector2i
) -> void:
	## `mCoBG_GetUnitVecInf_SlatingWall`: 45° segment across a slate unit.
	if _uses_solid_column(data, cell):
		return
	var unit: Dictionary = _catalog_unit(data, cell)
	if unit.is_empty() or not _unit_is_slate(unit):
		return
	var elev: int = int(_acre_elev(data, cell))
	var nw: float = FieldCatalog.counts_to_y(int(unit["nw"]), elev)
	var ne: float = FieldCatalog.counts_to_y(int(unit["ne"]), elev)
	var se: float = FieldCatalog.counts_to_y(int(unit["se"]), elev)
	var sw: float = FieldCatalog.counts_to_y(int(unit["sw"]), elev)
	var c0: Vector3 = grid.cell_corner(cell)
	var cs: float = grid.cell_size
	var dir: int = _slate_dir(unit)
	if dir == _SLATE_UP:
		var y_lo: float = minf(nw, se)
		var y_hi: float = maxf(nw, se)
		if y_hi - y_lo < EDGE_EPS:
			return
		var hint_up: Vector2 = Vector2(1.0, 1.0) if nw > se else Vector2(-1.0, -1.0)
		_add_segment_wall(body, c0.x, c0.z + cs, c0.x + cs, c0.z, y_lo, y_hi, y_lo, y_hi, hint_up)
	else:
		var y_lo_d: float = minf(sw, ne)
		var y_hi_d: float = maxf(sw, ne)
		if y_hi_d - y_lo_d < EDGE_EPS:
			return
		var hint_down: Vector2 = Vector2(1.0, -1.0) if sw > ne else Vector2(-1.0, 1.0)
		_add_segment_wall(
			body, c0.x, c0.z, c0.x + cs, c0.z + cs, y_lo_d, y_hi_d, y_lo_d, y_hi_d, hint_down
		)


static func _unit_is_slate(unit: Dictionary) -> bool:
	return FieldCatalog.is_slate_unit(int(unit["s"]), int(unit["a"]))


static func _slate_dir(unit: Dictionary) -> int:
	## `mCoBG_SearchSlateDetail`: SE≠NW → SW–NE (`SLATE_UP`); else NW–SE (`SLATE_DOWN`).
	if int(unit["se"]) != int(unit["nw"]):
		return _SLATE_UP
	return _SLATE_DOWN


static func _flatten_slate_for_edge(
	unit: Dictionary, other: Dictionary, east: bool, unit_is_west_or_north: bool
) -> Dictionary:
	## Mixed slate/grass edges: original equalizes the slate unit's shared-edge corners
	## (`UtInf2NormalSlateWallVector`). Geometry then keeps only the half that already had
	## a height jump before flatten, so the notch edge does not grow a full wall in front
	## of the 45° face.
	if not _unit_is_slate(unit) or _unit_is_slate(other):
		return unit
	var out: Dictionary = unit.duplicate()
	var up: bool = _slate_dir(unit) == _SLATE_UP
	if east:
		if unit_is_west_or_north:
			if up:
				out["se"] = out["ne"]
			else:
				out["ne"] = out["se"]
		elif up:
			out["sw"] = out["nw"]
		else:
			out["nw"] = out["sw"]
	elif unit_is_west_or_north:
		if up:
			out["sw"] = out["se"]
		else:
			out["se"] = out["sw"]
	elif up:
		out["ne"] = out["nw"]
	else:
		out["nw"] = out["ne"]
	return out


static func _add_segment_wall(
	body: StaticBody3D,
	ax: float,
	az: float,
	bx: float,
	bz: float,
	y_lo0: float,
	y_hi0: float,
	y_lo1: float,
	y_hi1: float,
	low_hint: Vector2 = Vector2.ZERO
) -> void:
	if y_hi0 < y_lo0:
		var t0: float = y_lo0
		y_lo0 = y_hi0
		y_hi0 = t0
	if y_hi1 < y_lo1:
		var t1: float = y_lo1
		y_lo1 = y_hi1
		y_hi1 = t1
	if y_hi0 - y_lo0 < EDGE_EPS and y_hi1 - y_lo1 < EDGE_EPS:
		return
	var along := Vector2(bx - ax, bz - az)
	var perp := Vector2(-along.y, along.x)
	var plen: float = perp.length()
	if plen < 0.01:
		return
	perp /= plen
	if low_hint.length_squared() > 0.0001 and perp.dot(low_hint) < 0.0:
		perp = -perp
	var ox0: float
	var oz0: float
	var ox1: float
	var oz1: float
	if low_hint.length_squared() > 0.0001:
		ox0 = 0.0
		oz0 = 0.0
		ox1 = perp.x * WALL_THICK
		oz1 = perp.y * WALL_THICK
	else:
		var half: float = WALL_THICK * 0.5
		ox0 = -perp.x * half
		oz0 = -perp.y * half
		ox1 = perp.x * half
		oz1 = perp.y * half
	y_hi0 += WALL_TOP_CLEARANCE
	y_hi1 += WALL_TOP_CLEARANCE
	var uniform: bool = (
		absf(y_lo0 - y_lo1) < EDGE_EPS
		and absf(y_hi0 - y_hi1) < EDGE_EPS
		and (y_hi0 - y_lo0) >= EDGE_EPS
		and (y_hi1 - y_lo1) >= EDGE_EPS
	)
	if uniform:
		_add_oriented_box_wall(
			body, ax, az, bx, bz, (y_lo0 + y_lo1) * 0.5, (y_hi0 + y_hi1) * 0.5, ox0, oz0, ox1, oz1
		)
		return
	_add_prism_trimesh(
		body,
		Vector3(ax + ox0, y_lo0, az + oz0),
		Vector3(ax + ox1, y_lo0, az + oz1),
		Vector3(ax + ox0, y_hi0, az + oz0),
		Vector3(ax + ox1, y_hi0, az + oz1),
		Vector3(bx + ox0, y_lo1, bz + oz0),
		Vector3(bx + ox1, y_lo1, bz + oz1),
		Vector3(bx + ox0, y_hi1, bz + oz0),
		Vector3(bx + ox1, y_hi1, bz + oz1)
	)


static func _add_oriented_box_wall(
	body: StaticBody3D,
	ax: float,
	az: float,
	bx: float,
	bz: float,
	y_lo: float,
	y_hi: float,
	ox0: float,
	oz0: float,
	ox1: float,
	oz1: float
) -> void:
	## Box along the segment. Convex hulls of thin 45° prisms fill the cell square and poke out.
	var x_axis := Vector3(bx - ax, 0.0, bz - az)
	var length: float = x_axis.length()
	if length < 0.01:
		return
	x_axis /= length
	var y_axis := Vector3.UP
	var z_axis: Vector3 = x_axis.cross(y_axis)
	if z_axis.length_squared() < 0.0001:
		return
	z_axis = z_axis.normalized()
	var mid := Vector3(
		(ax + bx) * 0.5 + (ox0 + ox1) * 0.5,
		(y_lo + y_hi) * 0.5,
		(az + bz) * 0.5 + (oz0 + oz1) * 0.5
	)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, maxf(y_hi - y_lo, 0.2), WALL_THICK)
	shape.shape = box
	shape.transform = Transform3D(Basis(x_axis, y_axis, z_axis), mid)
	body.add_child(shape)


static func _add_prism_trimesh(
	body: StaticBody3D,
	h0b: Vector3,
	l0b: Vector3,
	h0t: Vector3,
	l0t: Vector3,
	h1b: Vector3,
	l1b: Vector3,
	h1t: Vector3,
	l1t: Vector3
) -> void:
	## Explicit faces only. A convex hull of the same 8 points fills the gap to the next wall.
	var faces := PackedVector3Array()
	_append_quad(faces, h0b, h1b, h1t, h0t)
	_append_quad(faces, l0b, l0t, l1t, l1b)
	_append_quad(faces, h0b, h0t, l0t, l0b)
	_append_quad(faces, h1b, l1b, l1t, h1t)
	_append_quad(faces, h0b, l0b, l1b, h1b)
	_append_quad(faces, h0t, h1t, l1t, l0t)
	var shape := CollisionShape3D.new()
	var mesh := ConcavePolygonShape3D.new()
	mesh.set_faces(faces)
	shape.shape = mesh
	body.add_child(shape)


static func _append_quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	faces.append(a)
	faces.append(b)
	faces.append(c)
	faces.append(a)
	faces.append(c)
	faces.append(d)


static func _add_box(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)


static func _ux_at(cell: Vector2i) -> float:
	return float(posmod(cell.x, WorldGenerator.UT))


static func _uz_at(cell: Vector2i) -> float:
	return float(posmod(cell.y, WorldGenerator.UT))
