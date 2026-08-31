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

enum Kind { POND, RIVER, OCEAN }

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


static func find(grid: WorldGrid) -> Array[Body]:
	var out: Array[Body] = []
	if grid == null:
		return out
	var seen: Dictionary = {}
	for z: int in grid.rows:
		for x: int in grid.columns:
			var cell := Vector2i(x, z)
			if seen.has(cell) or grid.terrain_at(cell) != WorldGrid.Terrain.WATER:
				continue
			var body: Body = _fill(grid, cell, seen)
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


static func _fill(grid: WorldGrid, start: Vector2i, seen: Dictionary) -> Body:
	var body := Body.new()
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	var min_cell: Vector2i = start
	var max_cell: Vector2i = start
	var touches_edge: bool = false
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		body.cells.append(cell)
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
		if cell.x == 0 or cell.y == 0 or cell.x == grid.columns - 1 or cell.y == grid.rows - 1:
			touches_edge = true
		for next: Vector2i in grid.neighbors4(cell):
			if seen.has(next) or grid.terrain_at(next) != WorldGrid.Terrain.WATER:
				continue
			seen[next] = true
			queue.append(next)
	body.bounds = Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)
	body.kind = _classify(body, touches_edge)
	## Water flows down its long axis. Fish hold station facing upstream, so this is the
	## axis `FishShadow` turns to; a still pond leaves them free to face anywhere.
	body.flows = body.kind == Kind.RIVER
	body.flow_yaw = 0.0 if body.bounds.size.y >= body.bounds.size.x else PI * 0.5
	return body


static func _classify(body: Body, touches_edge: bool) -> Kind:
	var span: Vector2i = body.bounds.size
	var major: int = maxi(span.x, span.y)
	var minor: int = maxi(mini(span.x, span.y), 1)
	if touches_edge and body.size() >= OCEAN_MIN_CELLS and minor >= OCEAN_MIN_WIDTH:
		return Kind.OCEAN
	if float(major) / float(minor) >= RIVER_ASPECT:
		return Kind.RIVER
	return Kind.POND
