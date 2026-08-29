class_name FieldCollision
extends RefCounted

## Walls plus a height query. Behavioral analog of `mCoBG`: each `grd_*` ships a 16×16
## table (center + four corners × 10 GX, attribute, slate). Banks and terraces are
## infinitely thin XZ segments (cardinal height jumps, 45° slate, water/blocked edges).
## Actors are circles against those segments so they slide instead of catching 3D box
## corners. Not physics shapes, not convex hulls, not the `grd_*` triangle mesh.

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
## Player / NPC `BgCheckControll` range is 18 GX (`m_player_common` / `ac_npc_ct`).
const ACTOR_RADIUS := 18.0 * FieldCatalog.GX_TO_METERS
const WALL_ITERS := 4
const SEG_CELL_PAD := 2
const SEG_END_PAD := 0.02
const _SLATE_UP := 1
const _SLATE_DOWN := 2
const _AREA_N := 0
const _AREA_E := 1
const _AREA_S := 2
const _AREA_W := 3


static func has_floor(y: float) -> bool:
	return y > NO_FLOOR


static func add_to(_root: Node3D, _data: WorldData, _grid: WorldGrid) -> void:
	## Terrain walls are kinematic (`revise_xz`). Trees, buildings, and map bounds stay physics.
	pass


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
	## Slate units use flat high/low side heights (`GetBGHeight_Normal_SlateGround`), not a blend
	## across the diagonal — that blend dropped Y into the cliff face mesh.
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
	var unit: Dictionary = _catalog_unit(data, cell)
	if not unit.is_empty() and _unit_is_slate(unit):
		return _slate_ground_y(unit, int(_acre_elev(data, cell)), fx, fz) - ground_dist
	var north: float = lerpf(ys[0], ys[1], fx)
	var south: float = lerpf(ys[3], ys[2], fx)
	return lerpf(north, south, fz) - ground_dist


static func revise_xz(
	data: WorldData,
	grid: WorldGrid,
	from: Vector3,
	to: Vector3,
	radius: float = ACTOR_RADIUS
) -> Vector3:
	## Circle vs thin segments (`WallCheck` + `CarryOutReverse`): slide along cliffs and banks.
	if data == null or grid == null:
		return to
	var to_cell: Vector2i = grid.world_to_cell(to)
	if not data.is_in_bounds(to_cell):
		return Vector3(from.x, _keep_y(data, grid, from), from.z)
	var origin := Vector2(from.x, from.z)
	var pos: Vector2 = _resolve_circle(
		origin, Vector2(to.x, to.z), _nearby_segments(data, grid, from, to), radius
	)
	var resolved := Vector3(pos.x, to.y, pos.y)
	var y: float = ground_y_at(data, grid, resolved)
	if not has_floor(y):
		return Vector3(from.x, _keep_y(data, grid, from), from.z)
	var res_cell: Vector2i = grid.world_to_cell(resolved)
	if _forbids_enter(data, res_cell) and not _forbids_enter(data, grid.world_to_cell(from)):
		return Vector3(from.x, _keep_y(data, grid, from), from.z)
	return Vector3(pos.x, y, pos.y)


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


static func _nearby_segments(
	data: WorldData, grid: WorldGrid, from: Vector3, to: Vector3
) -> Array[Vector4]:
	var seen: Dictionary = {}
	var segs: Array[Vector4] = []
	for p: Vector3 in [from, to]:
		var origin: Vector2i = grid.world_to_cell(p)
		for dz: int in range(-SEG_CELL_PAD, SEG_CELL_PAD + 1):
			for dx: int in range(-SEG_CELL_PAD, SEG_CELL_PAD + 1):
				var cell := Vector2i(origin.x + dx, origin.y + dz)
				if seen.has(cell) or not data.is_in_bounds(cell):
					continue
				seen[cell] = true
				_append_cell_segments(segs, data, grid, cell)
	return segs


static func _append_cell_segments(
	segs: Array[Vector4], data: WorldData, grid: WorldGrid, cell: Vector2i
) -> void:
	var east := Vector2i(cell.x + 1, cell.y)
	if data.is_in_bounds(east):
		_append_cardinal(segs, data, grid, cell, east, true)
	var south := Vector2i(cell.x, cell.y + 1)
	if data.is_in_bounds(south):
		_append_cardinal(segs, data, grid, cell, south, false)
	_append_slate(segs, data, grid, cell)


static func _append_cardinal(
	segs: Array[Vector4],
	data: WorldData,
	grid: WorldGrid,
	a: Vector2i,
	b: Vector2i,
	east: bool
) -> void:
	var attr_wall: bool = _forbids_enter(data, a) != _forbids_enter(data, b)
	var ua: Dictionary = _catalog_unit(data, a)
	var ub: Dictionary = _catalog_unit(data, b)
	var ends: PackedVector2Array = _edge_ends(grid, a, east)
	if ua.is_empty() or ub.is_empty():
		if attr_wall or _edge_is_wall(data, a, b):
			_push_seg(segs, ends[0], ends[1])
		return
	if _unit_is_slate(ua) and _unit_is_slate(ub):
		if attr_wall:
			_push_seg(segs, ends[0], ends[1])
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
	var height_wall: bool = _catalog_edge_delta(data, a, b, ua, ub) >= EDGE_EPS
	if not height_wall:
		if attr_wall:
			_push_seg(segs, ends[0], ends[1])
		return
	if mixed_slate:
		var need0: bool = pre0 >= EDGE_EPS
		var need1: bool = pre1 >= EDGE_EPS
		if need0 and not need1:
			ends[1] = (ends[0] + ends[1]) * 0.5
		elif need1 and not need0:
			ends[0] = (ends[0] + ends[1]) * 0.5
		elif not need0 and not need1:
			if attr_wall:
				_push_seg(segs, _edge_ends(grid, a, east)[0], _edge_ends(grid, a, east)[1])
			return
	_push_seg(segs, ends[0], ends[1])


static func _append_slate(
	segs: Array[Vector4], data: WorldData, grid: WorldGrid, cell: Vector2i
) -> void:
	## `mCoBG_GetUnitVecInf_SlatingWall`: 45° segment across a slate unit.
	if _forbids_enter(data, cell):
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
	if _slate_dir(unit) == _SLATE_UP:
		if maxf(nw, se) - minf(nw, se) < EDGE_EPS:
			return
		_push_seg(segs, Vector2(c0.x, c0.z + cs), Vector2(c0.x + cs, c0.z))
	else:
		if maxf(sw, ne) - minf(sw, ne) < EDGE_EPS:
			return
		_push_seg(segs, Vector2(c0.x, c0.z), Vector2(c0.x + cs, c0.z + cs))


static func _edge_ends(grid: WorldGrid, a: Vector2i, east: bool) -> PackedVector2Array:
	var c0: Vector3 = grid.cell_corner(a)
	var cs: float = grid.cell_size
	var out := PackedVector2Array()
	if east:
		out.append(Vector2(c0.x + cs, c0.z))
		out.append(Vector2(c0.x + cs, c0.z + cs))
	else:
		out.append(Vector2(c0.x, c0.z + cs))
		out.append(Vector2(c0.x + cs, c0.z + cs))
	return out


static func _push_seg(segs: Array[Vector4], a: Vector2, b: Vector2) -> void:
	var along: Vector2 = b - a
	var length: float = along.length()
	if length < 0.01:
		return
	along /= length
	a -= along * SEG_END_PAD
	b += along * SEG_END_PAD
	segs.append(Vector4(a.x, a.y, b.x, b.y))


static func _resolve_circle(
	origin: Vector2, dest: Vector2, segs: Array[Vector4], radius: float
) -> Vector2:
	var pos: Vector2 = dest
	for _i: int in WALL_ITERS:
		var moved := false
		for seg: Vector4 in segs:
			var next: Vector2 = _separate_segment(
				origin, pos, Vector2(seg.x, seg.y), Vector2(seg.z, seg.w), radius
			)
			if next.distance_squared_to(pos) > 0.00000001:
				pos = next
				moved = true
		if not moved:
			break
	return pos


static func _separate_segment(
	origin: Vector2, pos: Vector2, a: Vector2, b: Vector2, radius: float
) -> Vector2:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return pos
	var n: Vector2 = Vector2(-ab.y, ab.x) / sqrt(len_sq)
	var from_d: float = (origin - a).dot(n)
	if from_d < 0.0:
		n = -n
		from_d = -from_d
	if from_d < 0.001:
		if (pos - a).dot(n) < 0.0:
			n = -n
	var t: float = clampf((pos - a).dot(ab) / len_sq, 0.0, 1.0)
	if t > 0.0001 and t < 0.9999:
		var d: float = (pos - a).dot(n)
		if d < radius:
			return pos + n * (radius - d)
		return pos
	var closest: Vector2 = a + ab * t
	var delta: Vector2 = pos - closest
	var dist: float = delta.length()
	if dist >= radius:
		return pos
	if dist < 0.0001:
		return closest + n * radius
	return closest + delta / dist * radius


static func _unit_is_slate(unit: Dictionary) -> bool:
	## Wall / slate-height use the collision `slate_flag` bit only. Attr 63 is slope paint
	## (`is_slate_unit` in FieldCatalog) and must keep bilinear height, not a 45° wall.
	return int(unit["s"]) != 0


static func _slate_dir(unit: Dictionary) -> int:
	## `mCoBG_SearchSlateDetail`: SE≠NW → SW–NE (`SLATE_UP`); else NW–SE (`SLATE_DOWN`).
	if int(unit["se"]) != int(unit["nw"]):
		return _SLATE_UP
	return _SLATE_DOWN


static func _unit_area(fx: float, fz: float) -> int:
	## `mCoBG_GetUnitArea` on unit-centered XZ (our fx/fz are 0–1 from the NW corner).
	var x: float = fx - 0.5
	var z: float = fz - 0.5
	if x < z:
		return _AREA_S if z > -x else _AREA_W
	return _AREA_E if z > -x else _AREA_N


static func _slate_ground_y(unit: Dictionary, elev: int, fx: float, fz: float) -> float:
	## `mCoBG_GetAreaYSlatingUnit`: one flat height per side of the 45° wall.
	var area: int = _unit_area(fx, fz)
	if _slate_dir(unit) == _SLATE_UP:
		if area == _AREA_S or area == _AREA_E:
			return FieldCatalog.counts_to_y(int(unit["se"]), elev)
		return FieldCatalog.counts_to_y(int(unit["nw"]), elev)
	if area == _AREA_N or area == _AREA_E:
		return FieldCatalog.counts_to_y(int(unit["ne"]), elev)
	return FieldCatalog.counts_to_y(int(unit["sw"]), elev)


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


static func _ux_at(cell: Vector2i) -> float:
	return float(posmod(cell.x, WorldGenerator.UT))


static func _uz_at(cell: Vector2i) -> float:
	return float(posmod(cell.y, WorldGenerator.UT))
