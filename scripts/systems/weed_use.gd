class_name WeedUse
extends RefCounted

## Weeds (`GRASS_A`–`GRASS_C`, `mAGrw_SetGrass`). Every daily renewal sows five per day since
## the last one (`mAGrw_GRASS_PER_DAY`, counting the day itself); each lands in a random acre
## that still has a free fully-plantable unit (`mCoBG_PLANT4`: grass ground), on a random one
## of those units, cycling a shuffled table of four of each kind. Pulling one
## (`m_player_main_remove_grass`) just clears the unit. Not an autoload.

const SCENE := "res://scenes/world/weed.tscn"
const VISUALS: Array[StringName] = [&"obj_zassou_a", &"obj_zassou_b", &"obj_zassou_c"]
const PER_DAY := 5
## `mAGrw_MakeGrassTable`: 4 × A, 4 × B, 4 × C, shuffled each renewal.
const TABLE_EACH := 4
## `ply_1_zassou1`; the weed comes out on frame 17 (`ChangeFGNumber_Remove_grass`).
const PULL_ANIM := &"ply_1_zassou1"
const PULL_FRAME := 17.0


static func persist_id(cell: Vector2i) -> StringName:
	return StringName("weed_%d_%d" % [cell.x, cell.y])


static func cell_from_persist(id: StringName) -> Vector2i:
	var s := String(id)
	if not s.begins_with("weed_"):
		return Vector2i(-1, -1)
	var parts: PackedStringArray = s.substr(5).split("_")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


static func is_weed(id: StringName) -> bool:
	return Game.weeds.has(String(id))


static func count() -> int:
	return Game.weeds.size()


## `mAGrw_GetGrassMax`: renewals crossed since the last grow, each worth five.
static func amount_for(days: int) -> int:
	return maxi(days, 0) * PER_DAY


## `mAGrw_GetChangeAbleGrass`: empty, not a raised plaza tile, and grass that lets a plant
## grow all the way.
static func can_grow(grid: WorldGrid, layout: WorldData, cell: Vector2i) -> bool:
	if grid == null or not grid.is_in_bounds(cell) or grid.is_occupied(cell):
		return false
	if FieldCollision.is_raised_plus(cell):
		return false
	if layout != null:
		var attr: int = FieldCollision.unit_attr_at_cell(layout, cell)
		if attr >= 0:
			return FieldCatalog.plant_class(attr) == FieldCatalog.PLANT_FULL
	return grid.terrain_at(cell) == WorldGrid.Terrain.GRASS


## `mAGrw_SetGrass`: sow `amount` weeds over the town; returns how many took root.
static func grow(world: Node, grid: WorldGrid, layout: WorldData, amount: int, rng: RandomNumberGenerator) -> int:
	if grid == null or amount <= 0 or Game.clear_grass:
		return 0
	## Candidate units, grouped by acre (16×16 units).
	var by_acre: Dictionary = {}
	for z: int in grid.rows:
		for x: int in grid.columns:
			var cell := Vector2i(x, z)
			if can_grow(grid, layout, cell):
				var acre := Vector2i(x / 16, z / 16)
				if not by_acre.has(acre):
					by_acre[acre] = []
				(by_acre[acre] as Array).append(cell)
	var table: Array[int] = []
	for kind: int in 3:
		for _i: int in TABLE_EACH:
			table.append(kind)
	for i: int in table.size():
		var j: int = rng.randi_range(0, table.size() - 1)
		var t: int = table[i]
		table[i] = table[j]
		table[j] = t
	var placed: int = 0
	var acres: Array = by_acre.keys()
	for n: int in amount:
		if acres.is_empty():
			break
		var acre: Vector2i = acres[rng.randi_range(0, acres.size() - 1)]
		var cells: Array = by_acre[acre]
		var pick: int = rng.randi_range(0, cells.size() - 1)
		var cell: Vector2i = cells[pick]
		cells.remove_at(pick)
		if cells.is_empty():
			acres.erase(acre)
		if _put(world, grid, cell, table[n % table.size()]):
			placed += 1
	return placed


static func restore(world: Node, grid: WorldGrid) -> void:
	if grid == null:
		return
	for key: Variant in Game.weeds.keys():
		var pid := StringName(str(key))
		var cell: Vector2i = cell_from_persist(pid)
		if not grid.is_in_bounds(cell):
			continue
		if grid.is_occupied(cell) and grid.occupant_at(cell) != pid:
			continue
		if not grid.is_occupied(cell):
			if not grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT):
				continue
		_instance(world, grid, cell, pid, int(Game.weeds[key]))


## `Remove_grass` frame 17: the unit is empty again.
static func pull(host: Node, ctx: InteractionContext) -> bool:
	if host == null:
		return false
	var pid: StringName = host.get("persist_id") as StringName
	if pid == &"" or not is_weed(pid):
		return false
	Game.weeds.erase(String(pid))
	var grid: WorldGrid = ctx.world.get("grid") as WorldGrid if ctx != null and ctx.world != null else null
	if grid != null:
		grid.remove(pid)
	if ctx != null:
		ctx.release_occupant(pid)
	return true


## `mAGrw_ClearGrass`: every weed gone at once.
static func clear_all(world: Node, grid: WorldGrid) -> void:
	for key: Variant in Game.weeds.keys():
		var pid := StringName(str(key))
		if grid != null:
			grid.remove(pid)
	Game.weeds.clear()
	if world != null and world.get_tree() != null:
		for node: Node in world.get_tree().get_nodes_in_group("weed"):
			node.queue_free()


static func _put(world: Node, grid: WorldGrid, cell: Vector2i, kind: int) -> bool:
	var pid: StringName = persist_id(cell)
	if not grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT):
		return false
	Game.weeds[String(pid)] = kind
	_instance(world, grid, cell, pid, kind)
	return true


static func _instance(world: Node, grid: WorldGrid, cell: Vector2i, pid: StringName, kind: int) -> void:
	if world == null:
		return
	var objects: Node = world.get_node_or_null("Objects")
	if objects == null or not ResourceLoader.exists(SCENE):
		return
	var host: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	host.set("persist_id", pid)
	host.set("occupant_id", pid)
	host.set("visual_id", VISUALS[clampi(kind, 0, 2)])
	objects.add_child(host)
	var pos: Vector3 = grid.cell_to_world(cell)
	if "layout" in world and world.layout != null:
		pos.y = FieldCollision.ground_y(world.layout as WorldData, cell, FieldCollision.FG_GROUND_DIST)
	host.global_position = pos
