class_name BugBg
extends RefCounted

## `aINS_BGcheck` / per-program BG queries against `WorldGrid` + `FieldCollision`.
## `BugActor.Sense.bg` is `probe.bind(grid, layout)` — a `Callable(pos_gx) -> Dictionary`
## the programs read for ground height, walls, water, flowers, and dig/shake state.

const GX_M := FieldCatalog.GX_TO_METERS


static func make_probe(grid: WorldGrid, layout: WorldData) -> Callable:
	if grid == null:
		return Callable()
	return func(pos_gx: Vector3) -> Dictionary:
		return probe(grid, layout, pos_gx)


static func probe(grid: WorldGrid, layout: WorldData, pos_gx: Vector3) -> Dictionary:
	var world: Vector3 = pos_gx * GX_M
	var cell: Vector2i = grid.world_to_cell(world)
	var out: Dictionary = {}

	var ground_m: float = world.y
	if layout != null:
		ground_m = FieldCollision.ground_y(layout, cell, FieldCollision.FG_GROUND_DIST)
	out["ground_y"] = ground_m / GX_M

	var terrain: int = grid.terrain_at(cell) if grid.is_in_bounds(cell) else WorldGrid.Terrain.BLOCKED
	var water: bool = terrain == WorldGrid.Terrain.WATER
	out["water"] = water
	out["in_water"] = water and pos_gx.y <= out["ground_y"] + 1.0
	out["water_y"] = out["ground_y"]
	out["on_ground"] = pos_gx.y <= float(out["ground_y"]) + 0.5

	## Wall: this cell (or, roughly, any 4-neighbour) is unwalkable.
	var blocked: bool = not grid.is_in_bounds(cell) or not _walkable(grid, cell)
	if not blocked:
		for n: Vector2i in grid.neighbors4(cell):
			if not _walkable(grid, n):
				blocked = true
				break
	out["hit_wall_front"] = blocked
	out["hit_wall"] = blocked

	## FG-item flags.
	if layout != null:
		var item: int = FieldCollision.unit_attr_at_cell(layout, cell)
		out["hole"] = _is_hole(item)
	out["on_flower"] = _flower_cell(layout, grid, cell)
	## A dragonfly perch (stake / sign reserve).
	out["perch"] = _perch_cell(layout, cell)
	if bool(out["perch"]):
		out["perch_y"] = float(out["ground_y"]) + 20.0
	return out


static func _walkable(grid: WorldGrid, cell: Vector2i) -> bool:
	if not grid.is_in_bounds(cell):
		return false
	var t: int = grid.terrain_at(cell)
	return t != WorldGrid.Terrain.BLOCKED and t != WorldGrid.Terrain.CLIFF


static func _is_hole(_attr: int) -> bool:
	return false  ## no dig-hole tracking on the grid yet


static func _flower_cell(layout: WorldData, grid: WorldGrid, cell: Vector2i) -> bool:
	if layout == null or grid == null:
		return true
	for obj: Variant in layout.objects:
		if obj == null:
			continue
		var kind: String = String(obj.get("kind"))
		if kind != "flower":
			continue
		if grid.world_to_cell(grid.footprint_center(obj.cell, Vector2i(1, 1))) == cell:
			return true
	return false


static func _perch_cell(layout: WorldData, cell: Vector2i) -> bool:
	if layout == null:
		return false
	for obj: Variant in layout.objects:
		if obj == null:
			continue
		var kind: String = String(obj.get("kind"))
		if kind == "sign" or kind == "stake" or kind == "post":
			if Vector2i(obj.get("cell")) == cell:
				return true
	return false
