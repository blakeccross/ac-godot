class_name WaterBodies
extends RefCounted

## Connected runs of water cells, so a fish shadow stays in the pond it spawned in instead
## of swimming overland into the next one. Not an autoload.
##
## The original never needs this: `mCoBG` gives every unit a water attribute and fish just
## respect wall segments. We only get the coarse `WorldGrid.Terrain.WATER` enum on authored
## acres, so the bodies get flood-filled once when the field loads.
##
## Kind is a classification, not a spawn table — `docs/decomp_notes/fishing.md` keeps the
## river / sea / pond species split out of scope. It exists so ocean bodies can hold the
## larger sizes and a four-cell pond does not sprout an XXL.
##
## When `WorldData` is available, sea (`attr` 24) is flood-filled separately from river /
## waterfall / pool water (`attr` 12–21). Without that split, a river mouth that touches the
## beach sea becomes one giant OCEAN and river-only fish never spawn in the river.

enum Kind { POND, RIVER, OCEAN }

## Family used only while flood-filling so sea and freshwater do not merge.
enum _Family { FRESH, SEA, UNKNOWN }

## `FieldCatalog.is_water_attr` splits river from sea by attribute; with only the terrain
## enum we go by shape. The sea runs off the field edge and is broad in both directions;
## a river also leaves the field but stays narrow, which is what separates them.
const OCEAN_MIN_CELLS := 24
const OCEAN_MIN_WIDTH := 4
## Longer than this on its major axis relative to its minor axis and it reads as flowing.
const RIVER_ASPECT := 2.5


class Body:
	var kind: Kind = Kind.POND
	var cells: Array[Vector2i] = []
	var bounds: Rect2i = Rect2i()
	## Flow direction in radians, along the body's major axis. Ponds do not flow.
	var flow_yaw: float = 0.0
	var flows: bool = false

	func contains(cell: Vector2i) -> bool:
		return cells.has(cell)

	func size() -> int:
		return cells.size()


static func find(grid: WorldGrid, layout: WorldData = null) -> Array[Body]:
	var out: Array[Body] = []
	if grid == null:
		return out
	var seen: Dictionary = {}
	for z: int in grid.rows:
		for x: int in grid.columns:
			var cell := Vector2i(x, z)
			if seen.has(cell) or grid.terrain_at(cell) != WorldGrid.Terrain.WATER:
				continue
			var body: Body = _fill(grid, layout, cell, seen)
			if not body.cells.is_empty():
				out.append(body)
	return out


static func body_at(bodies: Array[Body], cell: Vector2i) -> Body:
	for body: Body in bodies:
		if body.contains(cell):
			return body
	return null


## Largest size class this body can plausibly hold. A puddle should not contain an XXL.
static func size_ceiling(body: Body) -> FishData.SizeClass:
	if body == null:
		return FishData.SizeClass.XXS
	match body.kind:
		Kind.OCEAN:
			return FishData.SizeClass.WHALE
		Kind.RIVER:
			return FishData.SizeClass.XL
		_:
			return FishData.SizeClass.L if body.size() >= 8 else FishData.SizeClass.S


static func _fill(grid: WorldGrid, layout: WorldData, start: Vector2i, seen: Dictionary) -> Body:
	var body := Body.new()
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	var min_cell: Vector2i = start
	var max_cell: Vector2i = start
	var touches_edge: bool = false
	var start_family: _Family = _family_at(layout, start)
	var sea_cells := 0
	var fresh_cells := 0
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		body.cells.append(cell)
		match _family_at(layout, cell):
			_Family.SEA:
				sea_cells += 1
			_Family.FRESH:
				fresh_cells += 1
			_:
				pass
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
		if cell.x == 0 or cell.y == 0 or cell.x == grid.columns - 1 or cell.y == grid.rows - 1:
			touches_edge = true
		for next: Vector2i in grid.neighbors4(cell):
			if seen.has(next) or grid.terrain_at(next) != WorldGrid.Terrain.WATER:
				continue
			## Keep sea and freshwater as separate bodies when attrs are known.
			if start_family != _Family.UNKNOWN and _family_at(layout, next) != start_family:
				continue
			seen[next] = true
			queue.append(next)
	body.bounds = Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)
	body.kind = _classify(body, touches_edge, sea_cells, fresh_cells)
	## Water flows down its long axis. Fish hold station facing upstream, so this is the
	## axis `FishShadow` turns to; a still pond leaves them free to face anywhere.
	body.flows = body.kind == Kind.RIVER
	body.flow_yaw = 0.0 if body.bounds.size.y >= body.bounds.size.x else PI * 0.5
	return body


static func _classify(body: Body, touches_edge: bool, sea_cells: int, fresh_cells: int) -> Kind:
	## Prefer the unit attribute when the catalog is present: a beach strip of sea water is
	## ocean even if it is too small for the shape heuristic, and a long river stays a river
	## even when it touches the map edge next to the sea.
	if sea_cells > 0 and sea_cells >= fresh_cells:
		return Kind.OCEAN
	if fresh_cells > 0 and sea_cells == 0:
		var span: Vector2i = body.bounds.size
		var major: int = maxi(span.x, span.y)
		var minor: int = maxi(mini(span.x, span.y), 1)
		if float(major) / float(minor) >= RIVER_ASPECT:
			return Kind.RIVER
		return Kind.POND
	var span2: Vector2i = body.bounds.size
	var major2: int = maxi(span2.x, span2.y)
	var minor2: int = maxi(mini(span2.x, span2.y), 1)
	if touches_edge and body.size() >= OCEAN_MIN_CELLS and minor2 >= OCEAN_MIN_WIDTH:
		return Kind.OCEAN
	if float(major2) / float(minor2) >= RIVER_ASPECT:
		return Kind.RIVER
	return Kind.POND


static func _family_at(layout: WorldData, cell: Vector2i) -> _Family:
	if layout == null:
		return _Family.UNKNOWN
	var attr: int = _attr_at(layout, cell)
	if FieldCatalog.is_sea_attr(attr):
		return _Family.SEA
	if attr >= 0 and FieldCatalog.is_water_attr(attr):
		return _Family.FRESH
	## Terrain marked water without a unit row (authored strips): freshwater, so it does
	## not merge into a neighboring sea acre when attrs are only half-known.
	if layout.is_in_bounds(cell) and layout.terrain_at(cell) == WorldGrid.Terrain.WATER:
		return _Family.FRESH
	return _Family.UNKNOWN


static func _attr_at(layout: WorldData, cell: Vector2i) -> int:
	if layout == null:
		return -1
	var visual: StringName = &""
	if layout.acre_visuals.size() == TownFieldGenerator.BLOCK_TOTAL:
		var bx: int = int(floor(float(cell.x) / float(WorldGenerator.UT))) + 1
		var bz: int = int(floor(float(cell.y) / float(WorldGenerator.UT))) + 1
		if bx >= 0 and bx < TownFieldGenerator.BLOCK_X and bz >= 0 and bz < TownFieldGenerator.BLOCK_Z:
			visual = StringName(layout.acre_visuals[bz * TownFieldGenerator.BLOCK_X + bx])
	elif layout.acre_visual != &"":
		visual = layout.acre_visual
	if visual == &"":
		return -1
	var unit: Dictionary = FieldCatalog.unit_at(
		visual, posmod(cell.x, WorldGenerator.UT), posmod(cell.y, WorldGenerator.UT)
	)
	if unit.is_empty():
		return -1
	return int(unit.get("a", -1))
