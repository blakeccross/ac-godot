class_name BugHabitats
extends RefCounted

## Finds valid spawn units per `aSOI_SPAWN_AREA_*` from `WorldData` / `WorldGrid`.
## Mirrors `aSOI_chk_live_area_data` (can this acre host the area at all?) and
## `aSOI_make_live_ut` (which units may it be born on). Decomp places insects in the
## player's **entered acre** (`next_bx` / `next_bz`), only on the inner 12×12 units
## (`ut` 2..13 — the two-unit rim of every acre never hosts a birth), not a radius
## around the player.
##
## Spawn-area numbers are the decomp enum (`ac_set_ovl_insect.h`), unchanged:
## 0 ON_TREE, 1 ON_FLOWER, 2 RAINING_ON_FLOWER, 3 FLYING, 4 ON_GROUND, 5 IN_BUSH,
## 6 FLYING_NEAR_WATER, 7 ON_WATER, 8 ON_CANDY, 9 ON_TRASH, 10 UNDER_ROCK,
## 11 UNDERGROUND, 12 FLYING_NEAR_FLOWERS_OR_AROUND, 13 NOTHING.

const AREA_ON_TREE := 0
const AREA_ON_FLOWER := 1
const AREA_RAINING_ON_FLOWER := 2
const AREA_FLYING := 3
const AREA_ON_GROUND := 4
const AREA_IN_BUSH := 5
const AREA_FLYING_NEAR_WATER := 6
const AREA_ON_WATER := 7
const AREA_ON_CANDY := 8
const AREA_ON_TRASH := 9
const AREA_UNDER_ROCK := 10
const AREA_UNDERGROUND := 11
const AREA_FLYING_NEAR_FLOWERS := 12
const AREA_NOTHING := 13
const AREA_NUM := 14

## `aSOI_make_live_ut`: units 2..(UT_NUM − 3) of the acre.
const RIM_UNITS := 2

## `mCoBG_ATTRIBUTE_*` the spawn checks read.
const ATTR_SOIL1 := 5
const ATTR_BUSH := 9
const ATTR_WATER := 12
const ATTR_RIVER_NE := 21
const ATTR_SEA := 24
## `mCoBG_CheckHole_OrgAttr`: units a hole can be dug in (HOLE, GRASS0-2, SOIL0-2, SAND,
## and the sand / river-bank / cliff-grass variants).
const HOLE_ATTRS: Array[int] = [
	10, 0, 1, 2, 4, 5, 6, 22, 25, 26, 36, 43, 44, 45, 46, 59, 60, 61, 62
]

## `aSOI_tree_check`: the FG ids a tree-borne insect is born on. Saplings / young trees,
## palms, harvested fruit trees (`*_NOFRUIT_*`) and the bee tree (`TREE_BEES`) are not.
const SPAWN_TREE_FG: Array[StringName] = [
	&"TREE", &"TREE_FTR", &"TREE_LIGHTS", &"TREE_BELLS",
	&"TREE_APPLE_FRUIT", &"TREE_ORANGE_FRUIT", &"TREE_PEACH_FRUIT", &"TREE_PEAR_FRUIT",
	&"TREE_CHERRY_FRUIT",
	&"TREE_1000BELLS", &"TREE_10000BELLS", &"TREE_30000BELLS", &"TREE_100BELLS",
	&"CEDAR_TREE", &"CEDAR_TREE_BELLS", &"CEDAR_TREE_FTR", &"CEDAR_TREE_LIGHTS",
	&"GOLD_TREE", &"GOLD_TREE_BELLS", &"GOLD_TREE_FTR", &"GOLD_TREE_SHOVEL",
]
## `ITM_FOOD_CANDY` / `ITM_KABU_SPOILED` lying on a unit.
const CANDY_ITEM := &"candy"
const TRASH_ITEM := &"spoiled_turnips"


class Site:
	var cell: Vector2i = Vector2i(-1, -1)
	var spawn_area: int = -1
	var habitat: BugData.Habitat = BugData.Habitat.FLYING
	var anchor: Vector3 = Vector3.ZERO


## `aSOI_ins_change_how_to_make`: FLYING_NEAR_FLOWERS_OR_AROUND becomes ON_FLOWER when the
## acre has a flower, else FLYING.
static func resolve_spawn_area(
	spawn_area: int, layout: WorldData, grid: WorldGrid, acre: Vector2i
) -> int:
	if spawn_area != AREA_FLYING_NEAR_FLOWERS:
		return spawn_area
	if not _flower_sites(layout, grid, acre).is_empty():
		return AREA_ON_FLOWER
	return AREA_FLYING


## `aSOI_chk_live_area_data[area].chk_live_area_proc`: can this acre host `spawn_area`
## under the current weather? `weather` is `Game.weather` (`&"rain"`, `&"snow"`, …);
## when empty it is read from `Game`.
static func has_spawn_area(
	spawn_area: int,
	layout: WorldData,
	grid: WorldGrid,
	acre: Vector2i,
	_occupied: Callable,
	raining: bool,
	weather: StringName = &""
) -> bool:
	var w: StringName = _weather(raining, weather)
	match spawn_area:
		AREA_ON_FLOWER:
			## `_type_flower`: any flower, not while it rains.
			return w != &"rain" and not _flower_sites(layout, grid, acre).is_empty()
		AREA_RAINING_ON_FLOWER:
			## `_type_flower_rain`: only while it rains.
			return w == &"rain" and not _flower_sites(layout, grid, acre).is_empty()
		AREA_FLYING_NEAR_FLOWERS:
			## `_type_flower_or_free`: true only when a flower is there; on a flowerless
			## acre the entries fall back to FLYING (checked on their own), and while it
			## rains they are dropped.
			return w != &"rain" and not _flower_sites(layout, grid, acre).is_empty()
		AREA_ON_CANDY, AREA_ON_TRASH:
			## `_type_free_without_rain_and_snow`.
			if w == &"rain" or w == &"snow":
				return false
			return not _sites(spawn_area, layout, grid, acre).is_empty()
		AREA_ON_WATER:
			## `_type_pond`: only a pool acre, or one with no river / waterfall / sea.
			if not acre_allows_pond(layout, acre):
				return false
			return not _sites(spawn_area, layout, grid, acre).is_empty()
		AREA_NOTHING:
			return true
		_:
			return not _sites(spawn_area, layout, grid, acre).is_empty()


## `aSOI_make_live_ut` for a spawn area the scheduler already picked (FLYING_NEAR_FLOWERS
## resolved first). `occupied` filters units another insect already took this entry.
static func sites_for_spawn_area(
	spawn_area: int,
	layout: WorldData,
	grid: WorldGrid,
	acre: Vector2i,
	occupied: Callable,
	_raining: bool = false
) -> Array[Site]:
	var resolved: int = resolve_spawn_area(spawn_area, layout, grid, acre)
	return _filter_open(_sites(resolved, layout, grid, acre), occupied)


static func pick_site(sites: Array[Site], rng: RandomNumberGenerator) -> Site:
	## `aSOI_get_live_ut`: `(int)(fqrand() * num_live_ut)`.
	if sites.is_empty():
		return null
	return sites[mini(int(rng.randf() * float(sites.size())), sites.size() - 1)]


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


## `mRF_BLOCKKIND_*` gate of `aSOI_ins_chk_live_area_type_pond`: pond skaters are born in
## the river pool acre, or in an acre with no river, waterfall or sea at all.
static func acre_allows_pond(layout: WorldData, acre: Vector2i) -> bool:
	var type: int = acre_type(layout, acre)
	if type < 0:
		return true
	if TownFieldGenerator.is_pool(type):
		return true
	return not _is_river_or_marine(type)


static func acre_type(layout: WorldData, acre: Vector2i) -> int:
	if layout == null or layout.acre_types.size() != TownFieldGenerator.BLOCK_TOTAL:
		return -1
	if acre.x < 0 or acre.x >= TownFieldGenerator.BLOCK_X:
		return -1
	if acre.y < 0 or acre.y >= TownFieldGenerator.BLOCK_Z:
		return -1
	return int(layout.acre_types[acre.y * TownFieldGenerator.BLOCK_X + acre.x])


## `unit_attribute` of a unit; placeholder acres with no `.col.json` fall back to the
## coarse terrain enum.
static func unit_attr(layout: WorldData, cell: Vector2i) -> int:
	if layout == null or not layout.is_in_bounds(cell):
		return -1
	var a: int = FieldCollision.unit_attr_at_cell(layout, cell)
	if a >= 0:
		return a
	match layout.terrain_at(cell):
		WorldGrid.Terrain.GRASS:
			return 0
		WorldGrid.Terrain.SOIL:
			return 4
		WorldGrid.Terrain.PATH:
			return 6
		WorldGrid.Terrain.STONE:
			return 7
		WorldGrid.Terrain.WATER:
			return ATTR_WATER
		WorldGrid.Terrain.SAND:
			return 22
		_:
			return -1


## Whether the spawn checks see rain (`Common_Get(weather) == mEnv_WEATHER_RAIN`).
static func is_raining(raining: bool, weather: StringName = &"") -> bool:
	return _weather(raining, weather) == &"rain"


# ---- internals ---------------------------------------------------------

static func _weather(raining: bool, weather: StringName) -> StringName:
	if raining:
		return &"rain"
	if weather != &"":
		return weather
	var w: StringName = Game.weather if Game != null else &"clear"
	## A caller that says "not raining" wins over a rainy session.
	return &"clear" if w == &"rain" else w


static func _sites(spawn_area: int, layout: WorldData, grid: WorldGrid, acre: Vector2i) -> Array[Site]:
	match spawn_area:
		AREA_ON_TREE:
			return _tree_sites(layout, grid, acre)
		AREA_ON_FLOWER, AREA_RAINING_ON_FLOWER:
			return _flower_sites(layout, grid, acre, spawn_area)
		AREA_FLYING:
			return _unit_sites(layout, grid, acre, spawn_area, BugData.Habitat.FLYING)
		AREA_ON_GROUND:
			return _unit_sites(layout, grid, acre, spawn_area, BugData.Habitat.GROUND)
		AREA_IN_BUSH:
			return _unit_sites(layout, grid, acre, spawn_area, BugData.Habitat.BUSH)
		AREA_FLYING_NEAR_WATER:
			return _unit_sites(layout, grid, acre, spawn_area, BugData.Habitat.NEAR_WATER)
		AREA_ON_WATER:
			return _unit_sites(layout, grid, acre, spawn_area, BugData.Habitat.WATER)
		AREA_ON_CANDY:
			return _item_sites(layout, grid, acre, CANDY_ITEM, spawn_area)
		AREA_ON_TRASH:
			return _item_sites(layout, grid, acre, TRASH_ITEM, spawn_area)
		AREA_UNDER_ROCK:
			return _object_kind_sites(layout, grid, acre, &"rock", spawn_area, BugData.Habitat.ROCK)
		AREA_UNDERGROUND:
			return _unit_sites(layout, grid, acre, spawn_area, BugData.Habitat.UNDERGROUND)
		_:
			return []


static func _filter_open(sites: Array[Site], occupied: Callable) -> Array[Site]:
	if not occupied.is_valid():
		return sites
	var out: Array[Site] = []
	for site: Site in sites:
		if occupied.call(site.cell):
			continue
		out.append(site)
	return out


## `aSOI_SPAWN_CATEGORY_UT_ATTRIBUTE` (and FLYING's `EMPTY_NO` FG / UNDERGROUND's hole
## attribute + empty FG): one site per matching inner unit.
static func _unit_sites(
	layout: WorldData, grid: WorldGrid, acre: Vector2i, spawn_area: int, habitat: BugData.Habitat
) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	var bounds: Rect2i = _acre_inner_bounds(layout, acre)
	var fg: Dictionary = {}
	if spawn_area == AREA_FLYING or spawn_area == AREA_UNDERGROUND:
		fg = _fg_cells(layout)
	for z: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, z)
			if not _unit_matches(spawn_area, layout, grid, cell, fg):
				continue
			var site := Site.new()
			site.cell = cell
			site.spawn_area = spawn_area
			site.habitat = habitat
			site.anchor = grid.cell_to_world(cell)
			site.anchor.y = FieldCollision.ground_y(layout, cell)
			out.append(site)
	return out


static func _unit_matches(
	spawn_area: int, layout: WorldData, grid: WorldGrid, cell: Vector2i, fg: Dictionary
) -> bool:
	match spawn_area:
		AREA_FLYING:
			return _fg_empty(grid, cell, fg)
		AREA_UNDERGROUND:
			return _fg_empty(grid, cell, fg) and unit_attr(layout, cell) in HOLE_ATTRS
	var attr: int = unit_attr(layout, cell)
	if attr < 0:
		return false
	match spawn_area:
		AREA_ON_GROUND:
			## GRASS0-3 / SOIL0-1, or bush.
			return attr <= ATTR_SOIL1 or attr == ATTR_BUSH
		AREA_IN_BUSH:
			return attr == ATTR_BUSH
		AREA_FLYING_NEAR_WATER:
			## `mCoBG_CheckWaterAttribute`: river / pond / waterfall, or the sea.
			return (attr >= ATTR_WATER and attr <= ATTR_RIVER_NE) or attr == ATTR_SEA
		AREA_ON_WATER:
			return attr >= ATTR_WATER and attr <= ATTR_RIVER_NE
	return false


static func _fg_empty(grid: WorldGrid, cell: Vector2i, fg: Dictionary) -> bool:
	if fg.has(cell):
		return false
	return grid == null or not grid.is_occupied(cell)


## Every unit a field item sits on (`fg_item != EMPTY_NO`): live layout objects, planted
## plants and dug holes.
static func _fg_cells(layout: WorldData) -> Dictionary:
	var out: Dictionary = {}
	if layout != null:
		for obj: ObjectPlacement in layout.objects:
			if obj == null or _object_removed(obj):
				continue
			for dx: int in maxi(obj.footprint.x, 1):
				for dz: int in maxi(obj.footprint.y, 1):
					out[obj.cell + Vector2i(dx, dz)] = true
	if Game != null:
		for key: Variant in Game.plant_states.keys():
			var pid := StringName(str(key))
			if Game.is_interactable_removed(pid):
				continue
			var cell: Vector2i = _record_cell(pid)
			if cell.x >= 0:
				out[cell] = true
		for key: String in Game.hole_interactables:
			var parts: PackedStringArray = key.split("_")
			if parts.size() >= 3 and parts[1].is_valid_int() and parts[2].is_valid_int():
				out[Vector2i(int(parts[1]), int(parts[2]))] = true
	return out


## `aSOI_SPAWN_CATEGORY_TREE`: layout trees and grown planted trees that pass
## `aSOI_tree_check`.
static func _tree_sites(layout: WorldData, grid: WorldGrid, acre: Vector2i) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	var bounds: Rect2i = _acre_inner_bounds(layout, acre)
	var seen: Dictionary = {}
	for obj: ObjectPlacement in layout.objects:
		if obj == null or obj.kind != &"tree":
			continue
		if not _in_inner(obj.cell, bounds, acre) or _object_removed(obj):
			continue
		var pid: StringName = _object_persist(obj)
		var rec: Dictionary = PlantGrowth.record(pid)
		if rec.is_empty():
			if not is_spawn_tree_fg(obj.visual_id):
				continue
		elif not _record_is_spawn_tree(pid, rec):
			continue
		seen[obj.cell] = true
		out.append(_site_at(obj.cell, &"tree", layout, grid, AREA_ON_TREE, BugData.Habitat.TREE))
	for pid: StringName in _plant_record_ids(PlantData.Kind.TREE):
		var cell: Vector2i = _record_cell(pid)
		if seen.has(cell) or not _in_inner(cell, bounds, acre):
			continue
		if not _record_is_spawn_tree(pid, PlantGrowth.record(pid)):
			continue
		seen[cell] = true
		out.append(_site_at(cell, &"tree", layout, grid, AREA_ON_TREE, BugData.Habitat.TREE))
	return out


static func is_spawn_tree_fg(visual: StringName) -> bool:
	return visual in SPAWN_TREE_FG


static func _record_is_spawn_tree(pid: StringName, rec: Dictionary) -> bool:
	if rec.is_empty() or Game.is_stump(pid) or Game.is_interactable_removed(pid):
		return false
	var plant: PlantData = PlantGrowth.plant_data(StringName(str(rec.get(PlantGrowth.KEY_PLANT, ""))))
	if plant == null or plant.kind != PlantData.Kind.TREE:
		return false
	if plant.family == PlantData.Family.PALM:
		return false
	if PlantGrowth.pipeline(rec, plant) != PlantGrowth.Pipeline.HARVESTABLE:
		return false
	## `TREE_BEES` is its own FG id, missing from `aSOI_tree_check`.
	if PlantGrowth.shake_content_of(rec) == TreeUse.Content.BEES:
		return false
	## Fruit trees only while bearing (`TREE_*_FRUIT`); `*_NOFRUIT_*` are not listed.
	if plant.fruit != null and not PlantGrowth.fruit_ready(rec, plant):
		return false
	return true


## `FLOWER_PANSIES0 … FLOWER_COSMOS2` (blooms, not `FLOWER_LEAVES_*`).
static func _flower_sites(
	layout: WorldData, grid: WorldGrid, acre: Vector2i, spawn_area: int = AREA_ON_FLOWER
) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	var bounds: Rect2i = _acre_inner_bounds(layout, acre)
	var seen: Dictionary = {}
	for obj: ObjectPlacement in layout.objects:
		if obj == null or obj.kind != &"flower":
			continue
		if not _in_inner(obj.cell, bounds, acre) or _object_removed(obj):
			continue
		var pid: StringName = _object_persist(obj)
		var rec: Dictionary = PlantGrowth.record(pid)
		if not rec.is_empty() and not _record_is_bloom(rec):
			continue
		seen[obj.cell] = true
		out.append(_site_at(obj.cell, &"flower", layout, grid, spawn_area, BugData.Habitat.FLOWER))
	for pid: StringName in _plant_record_ids(PlantData.Kind.FLOWER):
		var cell: Vector2i = _record_cell(pid)
		if seen.has(cell) or not _in_inner(cell, bounds, acre):
			continue
		if not _record_is_bloom(PlantGrowth.record(pid)):
			continue
		seen[cell] = true
		out.append(_site_at(cell, &"flower", layout, grid, spawn_area, BugData.Habitat.FLOWER))
	return out


static func _record_is_bloom(rec: Dictionary) -> bool:
	var plant: PlantData = PlantGrowth.plant_data(StringName(str(rec.get(PlantGrowth.KEY_PLANT, ""))))
	if plant == null or plant.kind != PlantData.Kind.FLOWER:
		return false
	var visual := String(PlantGrowth.visual_id(rec, plant))
	return visual.begins_with("FLOWER_") and not visual.begins_with("FLOWER_LEAVES")


static func _object_kind_sites(
	layout: WorldData,
	grid: WorldGrid,
	acre: Vector2i,
	kind: StringName,
	spawn_area: int,
	habitat: BugData.Habitat
) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	var bounds: Rect2i = _acre_inner_bounds(layout, acre)
	for obj: ObjectPlacement in layout.objects:
		if obj == null or obj.kind != kind:
			continue
		if not _in_inner(obj.cell, bounds, acre) or _object_removed(obj):
			continue
		out.append(_site_at(obj.cell, kind, layout, grid, spawn_area, habitat))
	return out


static func _item_sites(
	layout: WorldData, grid: WorldGrid, acre: Vector2i, item_id: StringName, spawn_area: int
) -> Array[Site]:
	var out: Array[Site] = []
	if layout == null or grid == null:
		return out
	var bounds: Rect2i = _acre_inner_bounds(layout, acre)
	var seen: Dictionary = {}
	for obj: ObjectPlacement in layout.objects:
		if obj == null or obj.kind != &"item" or not (obj.payload is ItemData):
			continue
		if (obj.payload as ItemData).id != item_id:
			continue
		if not _in_inner(obj.cell, bounds, acre) or _object_removed(obj):
			continue
		seen[obj.cell] = true
		out.append(_site_at(obj.cell, &"item", layout, grid, spawn_area, BugData.Habitat.GROUND))
	## Items the player dropped are pickups in the scene, not layout objects.
	for cell: Vector2i in _pickup_cells(grid, item_id):
		if seen.has(cell) or not _in_inner(cell, bounds, acre):
			continue
		seen[cell] = true
		out.append(_site_at(cell, &"item", layout, grid, spawn_area, BugData.Habitat.GROUND))
	return out


static func _pickup_cells(grid: WorldGrid, item_id: StringName) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or grid == null:
		return out
	for node: Node in tree.get_nodes_in_group(&"interactable"):
		var n3 := node as Node3D
		if n3 == null or not n3.is_inside_tree() or not (&"item" in n3):
			continue
		var data := n3.get(&"item") as ItemData
		if data == null or data.id != item_id:
			continue
		out.append(grid.world_to_cell(n3.global_position))
	return out


static func _site_at(
	cell: Vector2i,
	kind: StringName,
	layout: WorldData,
	grid: WorldGrid,
	spawn_area: int,
	habitat: BugData.Habitat
) -> Site:
	## `aSOI_ins_make_sub`: the unit's centre.
	var site := Site.new()
	site.cell = cell
	site.spawn_area = spawn_area
	site.habitat = habitat
	site.anchor = grid.footprint_center(cell, Vector2i(1, 1))
	site.anchor.y = FieldCollision.ground_y(layout, cell, FieldCollision.fg_ground_dist(kind))
	return site


static func _object_persist(obj: ObjectPlacement) -> StringName:
	return obj.persist_id if obj.persist_id != &"" else obj.id


static func _object_removed(obj: ObjectPlacement) -> bool:
	if Game == null:
		return false
	var pid: StringName = _object_persist(obj)
	return Game.is_interactable_removed(pid) or Game.is_stump(pid)


static func _plant_record_ids(kind: PlantData.Kind) -> Array[StringName]:
	var out: Array[StringName] = []
	if Game == null:
		return out
	for key: Variant in Game.plant_states.keys():
		var pid := StringName(str(key))
		if Game.is_interactable_removed(pid) or Game.is_stump(pid):
			continue
		var rec: Dictionary = PlantGrowth.record(pid)
		var plant: PlantData = PlantGrowth.plant_data(StringName(str(rec.get(PlantGrowth.KEY_PLANT, ""))))
		if plant != null and plant.kind == kind:
			out.append(pid)
	return out


static func _record_cell(pid: StringName) -> Vector2i:
	var rec: Dictionary = PlantGrowth.record(pid)
	var cell := Vector2i(
		int(rec.get(PlantGrowth.KEY_CELL_X, -1)), int(rec.get(PlantGrowth.KEY_CELL_Z, -1))
	)
	if cell.x < 0:
		cell = PlantGrowth.cell_from_persist(pid)
	return cell


static func _in_inner(cell: Vector2i, bounds: Rect2i, _acre: Vector2i) -> bool:
	return bounds.has_point(cell)


## The acre's inner units (`ut` 2..13). Layouts smaller than one acre (test town) use
## the whole map.
static func _acre_inner_bounds(layout: WorldData, acre: Vector2i) -> Rect2i:
	if layout == null:
		return Rect2i()
	var whole := Rect2i(0, 0, layout.columns, layout.rows)
	if acre.x < 0:
		return whole
	var origin := Vector2i((acre.x - 1) * WorldGenerator.UT, (acre.y - 1) * WorldGenerator.UT)
	var full := Rect2i(origin, Vector2i(WorldGenerator.UT, WorldGenerator.UT))
	if full.intersection(whole).size.x <= 0 or full.intersection(whole).size.y <= 0:
		## Small layouts (test town) sit in one logical acre — use the whole map.
		return whole
	var inner := Rect2i(
		origin + Vector2i(RIM_UNITS, RIM_UNITS),
		Vector2i(WorldGenerator.UT - 2 * RIM_UNITS, WorldGenerator.UT - 2 * RIM_UNITS)
	)
	return inner.intersection(whole)


## `mRF_block_info[type] & (RIVER | WATERFALL | MARINE)` for our acre ids.
static func _is_river_or_marine(type: int) -> bool:
	## `BORDER_CLIFF_RIVER` carries only `RIVER0` (no `RIVER` bit) in `mRF_block_info`, so
	## skaters may be born there.
	if type == TownFieldGenerator.T_TRACKS_RIVER:
		return true
	if type >= TownFieldGenerator.T_WF_H and type <= TownFieldGenerator.T_WF_W_BL:
		return true
	if type >= TownFieldGenerator.T_RIVER_S and type <= TownFieldGenerator.T_RIVER_WS_BRIDGE:
		return true
	if TownFieldGenerator.is_beach(type):
		return true
	if (
		type == TownFieldGenerator.T_BORDER_CLIFF_OCEAN_LEFT
		or type == TownFieldGenerator.T_BORDER_CLIFF_OCEAN_RIGHT
	):
		return true
	return type >= TownFieldGenerator.T_OCEAN and type != TownFieldGenerator.T_LIGHTHOUSE
