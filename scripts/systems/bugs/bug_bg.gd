class_name BugBg
extends RefCounted

## `aINS_BGcheck` / per-program BG queries against `WorldGrid` + `FieldCollision`.
## `BugActor.Sense.bg` is `probe.bind(grid, layout)` — a `Callable(pos_gx) -> Dictionary`
## the programs read for ground height, walls, water, flowers, and dig/shake state.

const GX_M := FieldCatalog.GX_TO_METERS
## Half-span of the slope sample for `rise_ahead`, GX (a quarter unit).
const SLOPE_PROBE_GX := 10.0
## `mCoBG_MakeOneColumnCollisionData`: FG item columns (trees 19, stumps 18, rocks …).
const COLUMN_GX := 20.0


static func make_probe(grid: WorldGrid, layout: WorldData) -> Callable:
	if grid == null:
		return Callable()
	return func(pos_gx: Vector3) -> Dictionary:
		return probe(grid, layout, pos_gx)


## Ground-only sampler for `BugActor._bg_check` (runs every frame for every insect, so
## none of `probe`'s object scans).
static func make_ground(grid: WorldGrid, layout: WorldData) -> Callable:
	if grid == null:
		return Callable()
	return func(pos_gx: Vector3) -> Dictionary:
		return ground(grid, layout, pos_gx)


## `mCoBG_GetBgY_AngleS_FromWpos` at the insect's XZ — the sloped surface the terrain draws
## and the player walks, not the unit's flat centre height. Water units report the bed as
## `ground_y` and the surface `WATER_DEPTH_GX` above it.
static func ground(grid: WorldGrid, layout: WorldData, pos_gx: Vector3) -> Dictionary:
	var world: Vector3 = pos_gx * GX_M
	var ground_y: float = pos_gx.y
	if layout != null:
		ground_y = FieldCollision.ground_y_at(layout, grid, world) / GX_M
	var cell: Vector2i = grid.world_to_cell(world)
	var water: bool = grid.is_in_bounds(cell) and grid.terrain_at(cell) == WorldGrid.Terrain.WATER
	return {"ground_y": ground_y, "water": water, "water_y": ground_y + BugActor.WATER_DEPTH_GX}


## Ground pitch at `pos_gx` along the facing `yaw` as `sin(angle)`: positive when the ground
## rises ahead. `mCoBG_GetBgY_AngleS_FromWpos`'s angle for the jump boost.
static func rise_ahead(grid: WorldGrid, layout: WorldData, pos_gx: Vector3, yaw: float) -> float:
	if grid == null or layout == null:
		return 0.0
	var d := Vector3(sin(yaw), 0.0, cos(yaw)) * SLOPE_PROBE_GX
	var ahead: float = float(ground(grid, layout, pos_gx + d)["ground_y"])
	var behind: float = float(ground(grid, layout, pos_gx - d)["ground_y"])
	return sin(atan2(ahead - behind, 2.0 * SLOPE_PROBE_GX))


static func probe(grid: WorldGrid, layout: WorldData, pos_gx: Vector3) -> Dictionary:
	var world: Vector3 = pos_gx * GX_M
	var cell: Vector2i = grid.world_to_cell(world)
	var out: Dictionary = ground(grid, layout, pos_gx)
	var water: bool = bool(out["water"])
	## Surface only exists over water; the dive programs drown at `pos.y <= water_y`.
	if not water:
		out["water_y"] = -1e9
	out["in_water"] = water and pos_gx.y <= float(out["water_y"])
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
	return has_kind(layout, cell, &"flower")


static func _perch_cell(layout: WorldData, cell: Vector2i) -> bool:
	if layout == null:
		return false
	for obj: ObjectPlacement in objects_at(layout, cell):
		if obj.kind == &"sign" or obj.kind == &"stake" or obj.kind == &"post":
			return true
	return false


# ---- unit FG queries (`mFI_GetUnitFG`) -------------------------------------

## Cell → objects on it, rebuilt when the layout's object list changes.
static var _index_layout_id: int = 0
static var _index_count: int = -1
static var _index: Dictionary = {}


static func objects_at(layout: WorldData, cell: Vector2i) -> Array:
	if layout == null:
		return []
	var id: int = layout.get_instance_id()
	if id != _index_layout_id or layout.objects.size() != _index_count:
		_index_layout_id = id
		_index_count = layout.objects.size()
		_index = {}
		for obj: ObjectPlacement in layout.objects:
			if obj == null:
				continue
			if not _index.has(obj.cell):
				_index[obj.cell] = []
			(_index[obj.cell] as Array).append(obj)
	return _index.get(cell, [])


static func has_kind(layout: WorldData, cell: Vector2i, kind: StringName) -> bool:
	for obj: ObjectPlacement in objects_at(layout, cell):
		if obj.kind == kind:
			return true
	return false


## `*unit == FLOWER_PANSIES0` (`aICH_rest_check`). The layout keeps only the flower's
## visual, so this is the white-pansy visual (shared with the white cosmos / red tulip).
static func is_pansy0(layout: WorldData, cell: Vector2i) -> bool:
	for obj: ObjectPlacement in objects_at(layout, cell):
		if obj.kind == &"flower" and obj.visual_id == &"FLOWER_PANSIES0":
			return true
	return false


## `mFI_CheckFGNpcOn`: an empty unit, a flower, grass, a sapling or a dropped item —
## anything without a collision column (trees, rocks, signs, structures).
static func npc_on(grid: WorldGrid, layout: WorldData, cell: Vector2i) -> bool:
	if grid != null and not grid.is_in_bounds(cell):
		return false
	for obj: ObjectPlacement in objects_at(layout, cell):
		match obj.kind:
			&"tree", &"rock", &"sign", &"reserve", &"structure", &"stake", &"post", &"fence", \
			&"waterfall", &"prop":
				return false
	return true


## `*fg == CEDAR_TREE` (the cicada / beetle / cockroach climb table). Only the plain grown
## cedar — the decomp misses the bells / furniture / bee / lights variants.
static func is_cedar(layout: WorldData, cell: Vector2i) -> bool:
	for obj: ObjectPlacement in objects_at(layout, cell):
		if obj.kind == &"tree" and obj.visual_id == &"CEDAR_TREE":
			return true
	return false


## `fg_p == NULL || IS_ITEM_TREE_STUMP(*fg_p)` (`aIMN_check_cut_tree`): the tree on this
## unit is gone or felled.
static func tree_cut(layout: WorldData, cell: Vector2i) -> bool:
	if layout == null:
		return false
	for obj: ObjectPlacement in objects_at(layout, cell):
		if obj.kind != &"tree":
			continue
		var pid: StringName = obj.persist_id if obj.persist_id != &"" else obj.id
		return Game != null and Game.is_stump(pid)
	return true


## `DUMMY_RESERVE`: the unit a villager's house sign reserves (dragonflies perch on it).
static func is_reserve(layout: WorldData, cell: Vector2i) -> bool:
	return has_kind(layout, cell, &"reserve") or _perch_cell(layout, cell)


## `mCoBG_CheckWaterAttribute` for the unit under `pos_gx`.
static func water_at(grid: WorldGrid, pos_gx: Vector3) -> bool:
	if grid == null:
		return false
	var cell: Vector2i = grid.world_to_cell(pos_gx * GX_M)
	return grid.is_in_bounds(cell) and grid.terrain_at(cell) == WorldGrid.Terrain.WATER


## `mCoBG_GetBgY_OnlyCenter_FromWpos(pos, 0)`: the unit's centre (keep) height, GX.
static func unit_center_y(grid: WorldGrid, layout: WorldData, pos_gx: Vector3, fallback: float) -> float:
	if grid == null or layout == null:
		return fallback
	var cell: Vector2i = grid.world_to_cell(pos_gx * GX_M)
	if not layout.is_in_bounds(cell):
		return fallback
	var y: float = FieldCollision.ground_y(layout, cell)
	return y / GX_M if FieldCollision.has_floor(y) else fallback


## `bg_collision_check.result.hit_wall & mCoBG_HIT_WALL_FRONT`: a bank / cliff / column
## within `range_gx` ahead along `yaw`, or the next unit is off the field.
static func wall_front(grid: WorldGrid, layout: WorldData, pos_gx: Vector3, yaw: float, range_gx: float) -> bool:
	if grid == null:
		return false
	var ahead: Vector3 = pos_gx + Vector3(sin(yaw), 0.0, cos(yaw)) * range_gx
	var cell: Vector2i = grid.world_to_cell(ahead * GX_M)
	if not grid.is_in_bounds(cell):
		return true
	var t: int = grid.terrain_at(cell)
	if t == WorldGrid.Terrain.BLOCKED:
		return true
	if cell != grid.world_to_cell(pos_gx * GX_M) and not npc_on(grid, layout, cell):
		## Tree / rock / sign columns stand ~20 GX; a flyer above one passes over it.
		if pos_gx.y < unit_center_y(grid, layout, ahead, pos_gx.y) + COLUMN_GX:
			return true
	if layout != null and FieldCollision.line_hits_wall(layout, grid, pos_gx * GX_M, ahead * GX_M):
		return true
	return false
