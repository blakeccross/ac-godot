class_name TouchPath
extends RefCounted

## Tap-to-walk routes: A* over the 2 m field units, eight ways, then pulled tight into
## straight legs. A unit is open when it's walkable ground, nothing stands on it and the
## field doesn't forbid it (water, cliffs); a move between side-by-side units is shut by a
## cliff or bank edge; a diagonal needs both of its side moves open, so routes never cut a
## corner. Indoors (no field) only the room's floor and its furniture count.

## Units expanded at most before giving up.
const MAX_NODES := 4000
## A tapped unit that can't be stood on moves to the nearest open one this many rings out.
const GOAL_RINGS := 3
## Spacing of the occupancy samples along a pulled-tight leg.
const LEG_STEP := 0.5


## World points from `from` to `to` (the last is `to` itself, or the open unit nearest it).
## Empty when there is no way there.
static func find(data: WorldData, grid: WorldGrid, from: Vector3, to: Vector3, room: Room = null) -> PackedVector3Array:
	var out := PackedVector3Array()
	if grid == null:
		return out
	var start: Vector2i = grid.world_to_cell(from)
	var want: Vector2i = grid.world_to_cell(to)
	var goal: Vector2i = nearest_open(data, grid, want, start, room)
	if goal == Vector2i(-1, -1):
		return out
	var cells: Array[Vector2i] = _search(data, grid, start, goal, room)
	if cells.is_empty():
		return out
	var points := PackedVector3Array()
	for cell: Vector2i in cells:
		points.append(_floor_point(data, grid, grid.cell_to_world(cell), from.y))
	points[0] = from
	points[points.size() - 1] = _floor_point(data, grid, to, from.y) if goal == want else points[points.size() - 1]
	return _pull_tight(data, grid, points, room)


static func is_open(data: WorldData, grid: WorldGrid, cell: Vector2i, room: Room = null) -> bool:
	if room != null:
		return room.is_inner(cell) and not grid.is_occupied(cell)
	if not grid.is_in_bounds(cell) or not grid.is_walkable(cell) or grid.is_occupied(cell):
		return false
	return data == null or not FieldCollision.forbids_enter(data, cell)


static func can_step(data: WorldData, grid: WorldGrid, a: Vector2i, b: Vector2i, room: Room = null) -> bool:
	var d: Vector2i = b - a
	if absi(d.x) + absi(d.y) == 2:
		var side_x := Vector2i(a.x + d.x, a.y)
		var side_y := Vector2i(a.x, a.y + d.y)
		return (
			is_open(data, grid, side_x, room) and is_open(data, grid, side_y, room)
			and can_step(data, grid, a, side_x, room) and can_step(data, grid, side_x, b, room)
			and can_step(data, grid, a, side_y, room) and can_step(data, grid, side_y, b, room)
		)
	return room != null or data == null or not FieldCollision.edge_is_wall(data, a, b)


## The open unit nearest `want` (ties go to the one nearer `start`), within `GOAL_RINGS`.
static func nearest_open(data: WorldData, grid: WorldGrid, want: Vector2i, start: Vector2i, room: Room = null) -> Vector2i:
	if want == start or is_open(data, grid, want, room):
		return want
	for ring: int in range(1, GOAL_RINGS + 1):
		var best := Vector2i(-1, -1)
		var best_d: float = INF
		for dz: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var c := want + Vector2i(dx, dz)
				if not is_open(data, grid, c, room):
					continue
				var d: float = Vector2(c - start).length()
				if d < best_d:
					best_d = d
					best = c
		if best != Vector2i(-1, -1):
			return best
	return Vector2i(-1, -1)


static func _search(data: WorldData, grid: WorldGrid, start: Vector2i, goal: Vector2i, room: Room) -> Array[Vector2i]:
	var came: Dictionary = {start: start}
	var cost: Dictionary = {start: 0.0}
	var open: Array = [[_h(start, goal), start]]
	var expanded: int = 0
	while not open.is_empty() and expanded < MAX_NODES:
		var best: int = 0
		for i: int in open.size():
			if float(open[i][0]) < float(open[best][0]):
				best = i
		var cur: Vector2i = open[best][1]
		open.remove_at(best)
		if cur == goal:
			var path: Array[Vector2i] = [cur]
			while path[0] != start:
				path.push_front(came[path[0]] as Vector2i)
			return path
		expanded += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var nxt: Vector2i = cur + d
			if not is_open(data, grid, nxt, room) and nxt != goal:
				continue
			if nxt == goal and not is_open(data, grid, nxt, room) and goal != start:
				continue
			if not can_step(data, grid, cur, nxt, room):
				continue
			var g: float = float(cost[cur]) + (1.41421356 if d.x != 0 and d.y != 0 else 1.0)
			if cost.has(nxt) and g >= float(cost[nxt]):
				continue
			cost[nxt] = g
			came[nxt] = cur
			open.append([g + _h(nxt, goal), nxt])
	return []


## Octile distance.
static func _h(a: Vector2i, b: Vector2i) -> float:
	var dx: int = absi(a.x - b.x)
	var dy: int = absi(a.y - b.y)
	return float(maxi(dx, dy)) + 0.41421356 * float(mini(dx, dy))


## From each kept point, skip ahead to the farthest point still in a straight, clear line.
static func _pull_tight(data: WorldData, grid: WorldGrid, points: PackedVector3Array, room: Room) -> PackedVector3Array:
	if points.size() <= 2:
		return points
	var out := PackedVector3Array([points[0]])
	var i: int = 0
	while i < points.size() - 1:
		var j: int = points.size() - 1
		while j > i + 1 and not _leg_clear(data, grid, points[i], points[j], room):
			j -= 1
		out.append(points[j])
		i = j
	return out


static func _leg_clear(data: WorldData, grid: WorldGrid, a: Vector3, b: Vector3, room: Room) -> bool:
	if data != null and FieldCollision.line_hits_wall(data, grid, a, b):
		return false
	var start: Vector2i = grid.world_to_cell(a)
	var steps: int = maxi(1, ceili(Vector2(b.x - a.x, b.z - a.z).length() / LEG_STEP))
	var prev: Vector2i = start
	for k: int in range(1, steps + 1):
		var c: Vector2i = grid.world_to_cell(a.lerp(b, float(k) / float(steps)))
		if c == prev:
			continue
		if c != start and not is_open(data, grid, c, room):
			return false
		if not can_step(data, grid, prev, c, room):
			return false
		prev = c
	return true


static func _floor_point(data: WorldData, grid: WorldGrid, at: Vector3, fallback_y: float) -> Vector3:
	var p := at
	p.y = fallback_y
	if data != null:
		var g: float = FieldCollision.ground_y_at(data, grid, at)
		if FieldCollision.has_floor(g):
			p.y = g
	return p
