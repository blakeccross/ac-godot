class_name BugHabitats
extends RefCounted

## Finds valid spawn cells per `aSOI_SPAWN_AREA_*` from `WorldData` / `WorldGrid`.
## Mirrors `aSOI_make_live_ut` + `aSOI_chk_live_area_data` placement categories.
## Decomp places insects in the player's **entered acre** (`next_bx` / `next_bz`), not a
## radius around the player.

class Site:
	var cell: Vector2i = Vector2i(-1, -1)
	var spawn_area: int = -1
	var habitat: BugData.Habitat = BugData.Habitat.FLYING
	var anchor: Vector3 = Vector3.ZERO


static func resolve_spawn_area(
	spawn_area: int, layout: WorldData, grid: WorldGrid, acre: Vector2i
) -> int:
	## `aSOI_ins_change_how_to_make`: flowers preferred, else flying.
	if spawn_area != 12:
		return spawn_area
	if not _flower_sites(layout, grid, acre).is_empty():
		return 1
	return 3


static func has_spawn_area(
	spawn_area: int,
	layout: WorldData,
	grid: WorldGrid,
	acre: Vector2i,
	_occupied: Callable,
	raining: bool
) -> bool:
	var resolved: int = resolve_spawn_area(spawn_area, layout, grid, acre)
	if not BugSpawnTable.weather_allows(resolved, raining):
		return false
	return not sites_for_spawn_area(
		resolved, layout, grid, acre, func(_cell: Vector2i) -> bool: return false, raining
	).is_empty()


static func sites_for_spawn_area(
	spawn_area: int,
	layout: WorldData,
	grid: WorldGrid,
	acre: Vector2i,
	occupied: Callable,
	raining: bool
) -> Array[Site]:
	var resolved: int = resolve_spawn_area(spawn_area, layout, grid, acre)
	if not BugSpawnTable.weather_allows(resolved, raining):
		return []
	match resolved:
		0:
			return _filter_open(_tree_sites(layout, grid, acre), occupied)
		1, 2:
			return _filter_open(_flower_sites(layout, grid, acre), occupied)
		3:
			return _filter_open(_flying_sites(layout, grid, acre), occupied)
		4:
			return _filter_open(_ground_sites(layout, grid, acre), occupied)
		5:
			return _filter_open(_bush_sites(layout, grid, acre), occupied)
		6:
			return _filter_open(_near_water_sites(layout, grid, acre), occupied)
		7:
			return _filter_open(_water_sites(layout, grid, acre), occupied)
		8:
			return _filter_open(_rock_sites(layout, grid, acre), occupied)
		9:
			return _filter_open(_underground_sites(layout, grid, acre), occupied)
		_:
			return []


static func pick_site(sites: Array[Site], rng: RandomNumberGenerator) -> Site:
	if sites.is_empty():
		return null
	return sites[rng.randi_range(0, sites.size() - 1)]


static func tree_sites(layout: WorldData, grid: WorldGrid) -> Array[Site]:
	return _tree_sites(layout, grid, Vector2i(-1, -1))


static func acre_of_world_pos(grid: WorldGrid, position: Vector3) -> Vector2i:
	if grid == null:
		return Vector2i(-1, -1)
	return VillagerWalk.block_from_cell(grid.world_to_cell(position))


static func cell_in_acre(cell: Vector2i, acre: Vector2i) -> bool:
	if acre.x < 0:
		return true
	return VillagerWalk.block_from_cell(cell) == acre


static func _filter_open(sites: Array[Site], occupied: Callable) -> Array[Site]:
	var out: Array[Site] = []
	for site: Site in sites:
		if occupied.call(site.cell):
			continue
		out.append(site)
	return out


static func _tree_sites(layout: WorldData, grid: WorldGrid, acre: Vector2i) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	for obj: ObjectPlacement in layout.objects:
		if obj == null or obj.kind != &"tree":
			continue
		if not cell_in_acre(obj.cell, acre):
			continue
		out.append(_object_site(obj, layout, grid, 0, BugData.Habitat.TREE))
	return out


static func _flower_sites(layout: WorldData, grid: WorldGrid, acre: Vector2i) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	for obj: ObjectPlacement in layout.objects:
		if obj == null or obj.kind != &"flower":
			continue
		if not cell_in_acre(obj.cell, acre):
			continue
		out.append(_object_site(obj, layout, grid, 1, BugData.Habitat.FLOWER))
	return out


static func _rock_sites(layout: WorldData, grid: WorldGrid, acre: Vector2i) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	for obj: ObjectPlacement in layout.objects:
		if obj == null or obj.kind != &"rock":
			continue
		if not cell_in_acre(obj.cell, acre):
			continue
		out.append(_object_site(obj, layout, grid, 8, BugData.Habitat.ROCK))
	return out


static func _object_site(
	obj: ObjectPlacement, layout: WorldData, grid: WorldGrid, spawn_area: int, habitat: BugData.Habitat
) -> Site:
	var site := Site.new()
	site.cell = obj.cell
	site.spawn_area = spawn_area
	site.habitat = habitat
	site.anchor = grid.footprint_center(obj.cell, Vector2i(1, 1))
	site.anchor.y = FieldCollision.ground_y(layout, obj.cell)
	return site


static func _flying_sites(layout: WorldData, grid: WorldGrid, acre: Vector2i) -> Array[Site]:
	return _open_terrain_sites(layout, grid, acre, 3, BugData.Habitat.FLYING)


static func _ground_sites(layout: WorldData, grid: WorldGrid, acre: Vector2i) -> Array[Site]:
	return _open_terrain_sites(layout, grid, acre, 4, BugData.Habitat.GROUND)


static func _bush_sites(layout: WorldData, grid: WorldGrid, acre: Vector2i) -> Array[Site]:
	## No bush terrain yet — reuse grass until bush FG exists.
	return _open_terrain_sites(layout, grid, acre, 5, BugData.Habitat.BUSH)


static func _open_terrain_sites(
	layout: WorldData,
	grid: WorldGrid,
	acre: Vector2i,
	spawn_area: int,
	habitat: BugData.Habitat
) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	var bounds: Rect2i = _acre_cell_bounds(layout, acre)
	for x: int in range(bounds.position.x, bounds.end.x):
		for z: int in range(bounds.position.y, bounds.end.y):
			var cell := Vector2i(x, z)
			if not _is_open_ground(layout, grid, cell):
				continue
			var at: Vector3 = grid.cell_to_world(cell)
			at.y = FieldCollision.ground_y(layout, cell)
			var site := Site.new()
			site.cell = cell
			site.spawn_area = spawn_area
			site.habitat = habitat
			site.anchor = at
			out.append(site)
	return out


static func _water_sites(layout: WorldData, grid: WorldGrid, acre: Vector2i) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	for cell: Vector2i in layout.water_cells:
		if not layout.is_in_bounds(cell) or not cell_in_acre(cell, acre):
			continue
		var at: Vector3 = grid.cell_to_world(cell)
		var site := Site.new()
		site.cell = cell
		site.spawn_area = 7
		site.habitat = BugData.Habitat.WATER
		site.anchor = at
		out.append(site)
	return out


static func _near_water_sites(layout: WorldData, grid: WorldGrid, acre: Vector2i) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	var seen: Dictionary = {}
	for cell: Vector2i in layout.water_cells:
		for neighbor: Vector2i in _neighbors4(cell):
			if not layout.is_in_bounds(neighbor) or not cell_in_acre(neighbor, acre):
				continue
			if seen.has(neighbor):
				continue
			if layout.terrain_at(neighbor) == WorldGrid.Terrain.WATER:
				continue
			if not _is_open_ground(layout, grid, neighbor):
				continue
			seen[neighbor] = true
			var at: Vector3 = grid.cell_to_world(neighbor)
			at.y = FieldCollision.ground_y(layout, neighbor)
			var site := Site.new()
			site.cell = neighbor
			site.spawn_area = 6
			site.habitat = BugData.Habitat.NEAR_WATER
			site.anchor = at
			out.append(site)
	return out


static func _underground_sites(layout: WorldData, grid: WorldGrid, acre: Vector2i) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	for key: String in Game.hole_interactables:
		var parts: PackedStringArray = key.split("_")
		if parts.size() < 3:
			continue
		var cell := Vector2i(int(parts[1]), int(parts[2]))
		if not layout.is_in_bounds(cell) or not cell_in_acre(cell, acre):
			continue
		var at: Vector3 = grid.cell_to_world(cell)
		at.y = FieldCollision.ground_y(layout, cell)
		var site := Site.new()
		site.cell = cell
		site.spawn_area = 9
		site.habitat = BugData.Habitat.UNDERGROUND
		site.anchor = at
		out.append(site)
	return out


static func _acre_cell_bounds(layout: WorldData, acre: Vector2i) -> Rect2i:
	if acre.x < 0 or layout == null:
		return Rect2i(0, 0, layout.columns if layout != null else 0, layout.rows if layout != null else 0)
	var origin := Vector2i((acre.x - 1) * WorldGenerator.UT, (acre.y - 1) * WorldGenerator.UT)
	var size := Vector2i(WorldGenerator.UT, WorldGenerator.UT)
	var clipped := Rect2i(origin, size).intersection(Rect2i(0, 0, layout.columns, layout.rows))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		## Small layouts (test town) sit in one logical acre — use the whole map.
		return Rect2i(0, 0, layout.columns, layout.rows)
	return clipped


static func _is_open_ground(layout: WorldData, grid: WorldGrid, cell: Vector2i) -> bool:
	if not layout.is_in_bounds(cell):
		return false
	var terrain: WorldGrid.Terrain = layout.terrain_at(cell)
	if terrain == WorldGrid.Terrain.WATER or terrain == WorldGrid.Terrain.CLIFF:
		return false
	if grid != null and grid.is_occupied(cell):
		return false
	return true


static func _neighbors4(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + Vector2i(1, 0),
		cell + Vector2i(-1, 0),
		cell + Vector2i(0, 1),
		cell + Vector2i(0, -1),
	]
