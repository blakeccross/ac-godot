class_name BugHabitats
extends RefCounted

## Finds spawn cells for each `BugData.Habitat` from `WorldData` and `WorldGrid`.
## Behavioral analog of `aSOI_ins_make_insect_normal_range_data` placement rules.

class Site:
	var cell: Vector2i = Vector2i(-1, -1)
	var habitat: BugData.Habitat = BugData.Habitat.FLYING
	var anchor: Vector3 = Vector3.ZERO


static func tree_sites(layout: WorldData, grid: WorldGrid) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	for obj: ObjectPlacement in layout.objects:
		if obj == null or obj.kind != &"tree":
			continue
		var site := Site.new()
		site.cell = obj.cell
		site.habitat = BugData.Habitat.TREE
		site.anchor = grid.footprint_center(obj.cell, Vector2i(1, 1))
		site.anchor.y = FieldCollision.ground_y(layout, obj.cell)
		out.append(site)
	return out


static func sites_near(
	layout: WorldData, grid: WorldGrid, player_position: Vector3, radius: float
) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	var seen: Dictionary = {}
	for obj: ObjectPlacement in layout.objects:
		if obj == null:
			continue
		var hab: int = _habitat_for_kind(obj.kind)
		if hab < 0:
			continue
		var at: Vector3 = grid.cell_to_world(obj.cell)
		if at.distance_to(player_position) > radius:
			continue
		var key: Vector2i = obj.cell
		if seen.has(key):
			continue
		seen[key] = true
		var site := Site.new()
		site.cell = obj.cell
		site.habitat = hab as BugData.Habitat
		site.anchor = at
		out.append(site)
	for cell: Vector2i in _ground_cells(layout, grid, player_position, radius):
		if seen.has(cell):
			continue
		seen[cell] = true
		var ground := Site.new()
		ground.cell = cell
		ground.habitat = BugData.Habitat.FLYING
		ground.anchor = grid.cell_to_world(cell)
		out.append(ground)
	for cell: Vector2i in _water_cells(layout, grid, player_position, radius):
		if seen.has(cell):
			continue
		seen[cell] = true
		var water := Site.new()
		water.cell = cell
		water.habitat = BugData.Habitat.WATER
		water.anchor = grid.cell_to_world(cell)
		out.append(water)
	return out


static func pick_site(
	layout: WorldData,
	grid: WorldGrid,
	player_position: Vector3,
	radius: float,
	want: BugData.Habitat,
	rng: RandomNumberGenerator
) -> Site:
	var candidates: Array[Site] = []
	for site: Site in sites_near(layout, grid, player_position, radius):
		if site.habitat == want or want == BugData.Habitat.FLYING:
			candidates.append(site)
	if candidates.is_empty():
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _habitat_for_kind(kind: StringName) -> int:
	match kind:
		&"flower":
			return BugData.Habitat.FLOWER
		&"tree":
			return BugData.Habitat.TREE
		&"rock":
			return BugData.Habitat.ROCK
		_:
			return -1


static func _ground_cells(
	layout: WorldData, grid: WorldGrid, player_position: Vector3, radius: float
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x: int in layout.columns:
		for z: int in layout.rows:
			var cell := Vector2i(x, z)
			var terrain: WorldGrid.Terrain = layout.terrain_at(cell)
			if terrain != WorldGrid.Terrain.GRASS and terrain != WorldGrid.Terrain.SOIL:
				continue
			if grid.is_occupied(cell):
				continue
			var at: Vector3 = grid.cell_to_world(cell)
			if at.distance_to(player_position) > radius:
				continue
			out.append(cell)
	return out


static func _water_cells(
	layout: WorldData, grid: WorldGrid, player_position: Vector3, radius: float
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in layout.water_cells:
		var at: Vector3 = grid.cell_to_world(cell)
		if at.distance_to(player_position) > radius:
			continue
		out.append(cell)
	return out
