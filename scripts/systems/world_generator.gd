class_name WorldGenerator
extends RefCounted

## Town layout. New Game uses TownFieldGenerator (mRF-style acres) then rasterizes FG units.

const DEFAULT_SEED := 12345
const UT := 16
const FG_X := 5
const FG_Z := 6
## FG_TYPE_GRD_S_F_MH_* / FG_TYPE_0069 place HOUSE0 at unit (3, 3). Actor ct adds
## +20 GX X/Z (`aMHS_posX_table[0]`), the center of a 2×2 whose NW is that unit.
const HOUSE0_UT := Vector2i(3, 3)
## SHOP0 is (10, 9) on `grd_s_t_sh_1` and (10, 10) on `_2`/`_3`. Actor ct adds
## −20 X, +20 Z, so the 2×2 NW is (SHOP0.x − 1, SHOP0.z).
const SHOP0_UT := Vector2i(10, 10)
const SHOP0_UT_SH1 := Vector2i(10, 9)

const _APPLE := preload("res://data/items/apple.tres")
const _APPLE_TREE := preload("res://data/plants/apple_tree.tres")
const _HARDWOOD := preload("res://data/plants/hardwood_tree.tres")
const _CEDAR := preload("res://data/plants/cedar_tree.tres")
const _PALM := preload("res://data/plants/palm_tree.tres")
const _PIP := preload("res://data/villagers/pip.tres")
const _CHAIR := preload("res://data/furniture/wood_chair.tres")


static func authored_test_town() -> WorldData:
	var data := WorldData.new()
	data.id = &"test_town"
	data.display_name = "Test Town"
	data.mode = WorldData.Mode.TEST
	data.seed_value = 0
	data.columns = 16
	data.rows = 16
	data.cell_size = 2.0
	data.acre_visual = &"grd_s_f_1"
	data.water_cells = [
		Vector2i(12, 3), Vector2i(13, 3), Vector2i(12, 4), Vector2i(13, 4)
	]
	data.buildings = [
		_building(&"player_house", &"house", Vector2i(7, 1), Vector2i(2, 2), true, &"obj_s_house1"),
		_building(&"acre_shop", &"shop", Vector2i(12, 1), Vector2i(2, 2), false, &"obj_s_shop1"),
	]
	data.objects = [
		_object(&"tree_1", &"tree", Vector2i(4, 6), _APPLE_TREE, &"TREE_APPLE_FRUIT"),
		_object(&"tree_2", &"tree", Vector2i(12, 5), _APPLE_TREE, &"TREE_APPLE_FRUIT"),
		_object(&"tree_3", &"tree", Vector2i(5, 12), _HARDWOOD, &"TREE"),
		_item(&"ground_apple", Vector2i(8, 10), _APPLE),
		_sign(&"acre_sign", Vector2i(9, 11), "Welcome to the acre."),
		_object(&"yard_chair", &"furniture", Vector2i(9, 3), _CHAIR, &"int_sum_chair01"),
		_object(&"pansy_1", &"flower", Vector2i(6, 10), null, &"FLOWER_PANSIES0"),
		_object(&"rock_1", &"rock", Vector2i(3, 8), null, &"ROCK_A"),
		_villager(&"pip", Vector2i(10, 9), _PIP),
	]
	data.spawn_points = [_spawn(&"player", Vector2i(8, 11), 0.0)]
	data.bake()
	return data


static func generate(seed_value: int = DEFAULT_SEED) -> WorldData:
	var field: Dictionary = TownFieldGenerator.new().generate(seed_value)
	var blocks: PackedByteArray = field["blocks"]
	var heights: PackedByteArray = field["heights"]
	var data := WorldData.new()
	data.id = &"generated"
	data.display_name = "Town %d" % seed_value
	data.mode = WorldData.Mode.GENERATED
	data.seed_value = seed_value
	data.columns = FG_X * UT
	data.rows = FG_Z * UT
	data.cell_size = 2.0
	data.acre_visual = &""
	data.acre_types = blocks.duplicate()
	data.acre_heights = heights.duplicate()
	data.acre_visuals = _pick_acre_visuals(blocks, seed_value)
	data.bake()
	_rasterize_acres(data, blocks, heights)
	_place_structure_buildings(data, blocks)
	_place_fg_props(data, blocks, seed_value)
	_pull_border_trees(data)
	_clear_house_path(data)
	data.bake()
	return data


static func _pick_acre_visuals(blocks: PackedByteArray, seed_value: int) -> PackedStringArray:
	var visuals := PackedStringArray()
	visuals.resize(TownFieldGenerator.BLOCK_TOTAL)
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_value as int) ^ 0xC0FFEE
	for i: int in TownFieldGenerator.BLOCK_TOTAL:
		var type: int = int(blocks[i])
		var pick: StringName = FieldCatalog.acre_for_block_type(type, int(rng.randi()))
		visuals[i] = String(pick)
	return visuals


static func _block(blocks: PackedByteArray, bx: int, bz: int) -> int:
	return int(blocks[bz * TownFieldGenerator.BLOCK_X + bx])


static func _height(heights: PackedByteArray, bx: int, bz: int) -> int:
	return int(heights[bz * TownFieldGenerator.BLOCK_X + bx])


static func _fg_origin(bx: int, bz: int) -> Vector2i:
	## FG acre (bx 1..5, bz 1..6) → unit origin in WorldData.
	return Vector2i((bx - 1) * UT, (bz - 1) * UT)


static func _rasterize_acres(data: WorldData, blocks: PackedByteArray, heights: PackedByteArray) -> void:
	for bz: int in range(1, 7):
		for bx: int in range(1, 6):
			var type: int = _block(blocks, bx, bz)
			var elev: int = _height(heights, bx, bz)
			var origin: Vector2i = _fg_origin(bx, bz)
			var visual := &""
			if data.acre_visuals.size() == TownFieldGenerator.BLOCK_TOTAL:
				visual = StringName(data.acre_visuals[bz * TownFieldGenerator.BLOCK_X + bx])
			_paint_acre(data, origin, type, elev, visual)


static func _paint_acre(
	data: WorldData, origin: Vector2i, type: int, elev: int, visual: StringName = &""
) -> void:
	if FieldCatalog.has_acre_collision(visual):
		_paint_from_catalog(data, origin, elev, visual)
		return
	for uz: int in UT:
		for ux: int in UT:
			var cell := Vector2i(origin.x + ux, origin.y + uz)
			data.set_elevation_cell(cell, elev)
			data.set_terrain_cell(cell, WorldGrid.Terrain.GRASS)
	if TownFieldGenerator.is_beach(type):
		for uz: int in UT:
			for ux: int in UT:
				data.set_terrain_cell(Vector2i(origin.x + ux, origin.y + uz), WorldGrid.Terrain.SAND)
	if TownFieldGenerator.is_riverish(type):
		_paint_river_corridor(data, origin, type)
	if TownFieldGenerator.is_cliffish(type):
		_paint_cliff_acre(data, origin, type, elev)
	if type == TownFieldGenerator.T_TRACKS_STATION or type == TownFieldGenerator.T_TRACKS_DUMP \
			or type == TownFieldGenerator.T_TRACKS_SHOP or type == TownFieldGenerator.T_TRACKS_POST \
			or type == TownFieldGenerator.T_TRACKS_RIVER:
		for ux: int in UT:
			var cell := Vector2i(origin.x + ux, origin.y + 2)
			if data.terrain_at(cell) == WorldGrid.Terrain.GRASS:
				data.set_terrain_cell(cell, WorldGrid.Terrain.PATH)


static func _paint_from_catalog(data: WorldData, origin: Vector2i, elev: int, visual: StringName) -> void:
	## `mFM_SetBG` copies this acre's `collision[16][16]` with the mesh. Do not guess strips.
	for uz: int in UT:
		for ux: int in UT:
			var cell := Vector2i(origin.x + ux, origin.y + uz)
			var unit: Dictionary = FieldCatalog.unit_at(visual, ux, uz)
			var attr: int = int(unit.get("a", 0))
			var center: int = int(unit.get("c", FieldCatalog.LAND_COUNTS))
			var terrace: int = 1 if center >= 10 else 0
			data.set_elevation_cell(cell, elev + terrace)
			if FieldCatalog.is_water_attr(attr):
				data.set_terrain_cell(cell, WorldGrid.Terrain.WATER)
				data.set_elevation_cell(cell, elev)
			elif FieldCatalog.is_hole_attr(attr):
				data.set_terrain_cell(cell, WorldGrid.Terrain.CLIFF)
			elif FieldCatalog.is_sand_attr(attr):
				data.set_terrain_cell(cell, WorldGrid.Terrain.SAND)
			elif FieldCatalog.is_slate_unit(int(unit.get("s", 0)), attr) or _uneven_corners(unit):
				data.set_terrain_cell(cell, WorldGrid.Terrain.PATH)
			else:
				data.set_terrain_cell(cell, WorldGrid.Terrain.GRASS)


static func _uneven_corners(unit: Dictionary) -> bool:
	var nw: int = int(unit.get("nw", FieldCatalog.LAND_COUNTS))
	var ne: int = int(unit.get("ne", FieldCatalog.LAND_COUNTS))
	var se: int = int(unit.get("se", FieldCatalog.LAND_COUNTS))
	var sw: int = int(unit.get("sw", FieldCatalog.LAND_COUNTS))
	return nw != ne or ne != se or se != sw


static func _paint_river_corridor(data: WorldData, origin: Vector2i, type: int) -> void:
	## One-acre river: vertical strip for south-ish, horizontal for east/west.
	var southish: bool = (
		type == TownFieldGenerator.T_RIVER_S
		or type == TownFieldGenerator.T_RIVER_SE
		or type == TownFieldGenerator.T_RIVER_SW
		or type == TownFieldGenerator.T_BEACH_RIVER
		or type == TownFieldGenerator.T_TRACKS_RIVER
		or type == TownFieldGenerator.T_BORDER_CLIFF_RIVER
		or (type >= TownFieldGenerator.T_WF_H and type <= TownFieldGenerator.T_WF_W_BL)
	)
	var eastish: bool = (
		type == TownFieldGenerator.T_RIVER_E
		or type == TownFieldGenerator.T_RIVER_ES
		or type == TownFieldGenerator.T_RIVER_SE
	)
	var westish: bool = (
		type == TownFieldGenerator.T_RIVER_W
		or type == TownFieldGenerator.T_RIVER_WS
		or type == TownFieldGenerator.T_RIVER_SW
	)
	if southish or (not eastish and not westish):
		var x0: int = origin.x + 6
		for uz: int in UT:
			for dx: int in 4:
				data.set_terrain_cell(Vector2i(x0 + dx, origin.y + uz), WorldGrid.Terrain.WATER)
	if eastish:
		var z0: int = origin.y + 6
		for ux: int in UT:
			for dz: int in 4:
				data.set_terrain_cell(Vector2i(origin.x + ux, z0 + dz), WorldGrid.Terrain.WATER)
	if westish:
		var z0: int = origin.y + 6
		for ux: int in UT:
			for dz: int in 4:
				data.set_terrain_cell(Vector2i(origin.x + ux, z0 + dz), WorldGrid.Terrain.WATER)


static func _paint_cliff_acre(data: WorldData, origin: Vector2i, type: int, elev: int) -> void:
	## High/low terraces follow `grd_s_c*` (high on the inside of the cliff winding).
	## Face units are walls; slope acres get a slate-style PATH ramp instead.
	var shape: int = TownFieldGenerator.cliff_shape(type)
	if shape < 0:
		return
	var slope: bool = TownFieldGenerator.is_slope(type)
	for uz: int in UT:
		for ux: int in UT:
			var cell := Vector2i(origin.x + ux, origin.y + uz)
			var rel: float = FieldCollision.unit_rel_at(shape, slope, float(ux) + 0.5, float(uz) + 0.5)
			var water: bool = data.terrain_at(cell) == WorldGrid.Terrain.WATER
			if rel < 0.0:
				if not water:
					data.set_terrain_cell(cell, WorldGrid.Terrain.CLIFF)
				data.set_elevation_cell(cell, elev)
			elif slope and rel > 0.05 and rel < 0.95:
				if not water:
					data.set_terrain_cell(cell, WorldGrid.Terrain.PATH)
				data.set_elevation_cell(cell, elev)
			else:
				data.set_elevation_cell(cell, elev + (1 if rel >= 0.5 else 0))


static func _place_structure_buildings(data: WorldData, blocks: PackedByteArray) -> void:
	## B3 player HOUSE0 (bx=3,bz=2), shop on tracks. FG unit + structure actor offset.
	var house_origin: Vector2i = _fg_origin(3, 2)
	var house_cell := house_origin + HOUSE0_UT
	data.buildings.append(
		_building(&"player_house", &"house", house_cell, Vector2i(2, 2), true, &"obj_s_house1")
	)
	data.spawn_points = [_spawn(&"player", Vector2i(house_cell.x + 1, house_cell.y + 4), 0.0)]
	for bz: int in range(1, 7):
		for bx: int in range(1, 6):
			var type: int = _block(blocks, bx, bz)
			var origin: Vector2i = _fg_origin(bx, bz)
			var center := Vector2i(origin.x + 7, origin.y + 7)
			match type:
				TownFieldGenerator.T_TRACKS_SHOP:
					var shop0: Vector2i = _shop0_unit(data, bx, bz)
					data.buildings.append(
						_building(
							&"acre_shop",
							&"shop",
							origin + Vector2i(shop0.x - 1, shop0.y),
							Vector2i(2, 2),
							false,
							&"obj_s_shop1"
						)
					)
				TownFieldGenerator.T_TRACKS_STATION:
					data.objects.append(_sign(&"station_sign", center, "Train Station"))
				TownFieldGenerator.T_TRACKS_POST:
					data.objects.append(_sign(&"post_sign", center, "Post Office"))
				TownFieldGenerator.T_MUSEUM:
					data.objects.append(_sign(&"museum_sign", center, "Museum"))
				TownFieldGenerator.T_POLICE:
					data.objects.append(_sign(&"police_sign", center, "Police Station"))
				TownFieldGenerator.T_SHRINE:
					data.objects.append(_sign(&"well_sign", center, "Wishing Well"))
				TownFieldGenerator.T_NEEDLEWORK:
					data.objects.append(_sign(&"able_sign", center, "Able Sisters"))
				TownFieldGenerator.T_PORT:
					data.objects.append(_sign(&"dock_sign", center, "Dock"))


static func _shop0_unit(data: WorldData, bx: int, bz: int) -> Vector2i:
	if data.acre_visuals.size() != TownFieldGenerator.BLOCK_TOTAL:
		return SHOP0_UT
	var visual := String(data.acre_visuals[bz * TownFieldGenerator.BLOCK_X + bx])
	if visual.ends_with("sh_1"):
		return SHOP0_UT_SH1
	return SHOP0_UT


static func _place_fg_props(data: WorldData, blocks: PackedByteArray, seed_value: int) -> void:
	## Prefer disc FG templates (`mFM_InitFgCombiSaveData`); scatter only as fallback.
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_value as int) ^ 0x9E3779B9
	if FgCatalog.has_catalog():
		_place_from_fg_templates(data, blocks, rng)
		_change_tree_to_fruit(data, rng)
		_change_tree_to_cedar(data, rng)
		## Most outdoor FG templates are tree-heavy; a few flats still get flower beds.
		if _kind_count(data, &"flower") == 0:
			_scatter_backup_flowers(data, blocks, rng)
	else:
		_place_fg_props_scatter(data, blocks, rng)
	var apple_cell := _first_open_near_spawn(data, 5)
	if apple_cell != Vector2i(-1, -1):
		data.objects.append(_item(&"ground_apple", apple_cell, _APPLE))
	var villager_cell := _first_open_near_spawn(data, 8)
	if villager_cell != Vector2i(-1, -1):
		data.objects.append(_villager(&"pip", villager_cell, _PIP))


static func _place_from_fg_templates(
	data: WorldData, blocks: PackedByteArray, rng: RandomNumberGenerator
) -> void:
	var tree_n := 0
	var flower_n := 0
	var rock_n := 0
	for bz: int in range(1, 7):
		for bx: int in range(1, 6):
			var type: int = _block(blocks, bx, bz)
			var origin: Vector2i = _fg_origin(bx, bz)
			var visual := _acre_visual(data, bx, bz)
			var fg_id: int = FgCatalog.pick_fg_id(visual, type, int(rng.randi()))
			if fg_id < 0:
				continue
			var items: PackedInt32Array = FgCatalog.items(fg_id)
			if items.size() != FgCatalog.ITEMS_PER_ACRE:
				continue
			for uz: int in UT:
				for ux: int in UT:
					var item_id: int = items[uz * UT + ux]
					var place: Dictionary = FgCatalog.placement_for_item(item_id)
					if place.is_empty():
						continue
					var cell := origin + Vector2i(ux, uz)
					if _occupied(data, cell):
						continue
					var kind: StringName = place["kind"]
					var vis: StringName = place["visual"]
					match kind:
						&"tree":
							var payload: Resource = _tree_payload(String(place.get("tree", "hardwood")))
							data.objects.append(
								_object(StringName("tree_%d" % tree_n), &"tree", cell, payload, vis)
							)
							tree_n += 1
						&"flower":
							data.objects.append(
								_object(StringName("flower_%d" % flower_n), &"flower", cell, null, vis)
							)
							flower_n += 1
						&"rock":
							data.objects.append(
								_object(StringName("rock_%d" % rock_n), &"rock", cell, null, vis)
							)
							rock_n += 1


static func _scatter_backup_flowers(
	data: WorldData, blocks: PackedByteArray, rng: RandomNumberGenerator
) -> void:
	var flower_n := 0
	for bz: int in range(1, 7):
		for bx: int in range(1, 6):
			var type: int = _block(blocks, bx, bz)
			if type != TownFieldGenerator.T_FLAT:
				continue
			_scatter_flowers(data, rng, _fg_origin(bx, bz), 3, flower_n)
			flower_n += 3
			if flower_n >= 12:
				return


static func _kind_count(data: WorldData, kind: StringName) -> int:
	var n := 0
	for o: ObjectPlacement in data.objects:
		if o != null and o.kind == kind:
			n += 1
	return n


static func _place_fg_props_scatter(
	data: WorldData, blocks: PackedByteArray, rng: RandomNumberGenerator
) -> void:
	var tree_n := 0
	var flower_n := 0
	var rock_n := 0
	for bz: int in range(1, 7):
		for bx: int in range(1, 6):
			var type: int = _block(blocks, bx, bz)
			var origin: Vector2i = _fg_origin(bx, bz)
			if type == TownFieldGenerator.T_PLAYER_HOUSE:
				continue
			if TownFieldGenerator.is_beach(type):
				_scatter_palms(data, rng, origin, 3)
				continue
			if TownFieldGenerator.is_riverish(type) and not TownFieldGenerator.is_cliffish(type):
				_scatter_trees(data, rng, origin, 4, bz, tree_n)
				tree_n += 4
				continue
			if type == TownFieldGenerator.T_FLAT or type == TownFieldGenerator.T_MUSEUM \
					or type == TownFieldGenerator.T_POLICE or type == TownFieldGenerator.T_SHRINE:
				var n: int = 8 if bz <= 3 else 6
				_scatter_trees(data, rng, origin, n, bz, tree_n)
				tree_n += n
				_scatter_flowers(data, rng, origin, 4, flower_n)
				flower_n += 4
				if rng.randi() % 3 == 0:
					_scatter_rocks(data, rng, origin, 1, rock_n)
					rock_n += 1


static func _change_tree_to_fruit(data: WorldData, rng: RandomNumberGenerator) -> void:
	## `mAGrw_ChangeTree2FruitTree`: per FG Z-row, convert 1 TREE on each of 2 random X acres.
	for bz: int in range(1, 7):
		var bx0: int = rng.randi_range(1, 5)
		var bx1: int = rng.randi_range(1, 4)
		if bx1 >= bx0:
			bx1 += 1
		_convert_one_hardwood_in_acre(data, bx0, bz, &"TREE_APPLE_FRUIT", _APPLE_TREE)
		_convert_one_hardwood_in_acre(data, bx1, bz, &"TREE_APPLE_FRUIT", _APPLE_TREE)


static func _change_tree_to_cedar(data: WorldData, rng: RandomNumberGenerator) -> void:
	## `mAGrw_ChangeTree2Cedar`: A/B/C rows convert up to 6 / 4 / 2 TREE → CEDAR per acre.
	var caps: Array[int] = [6, 4, 2]
	for i: int in caps.size():
		var bz: int = i + 1
		for bx: int in range(1, 6):
			_convert_n_hardwood_in_acre(data, bx, bz, caps[i], &"CEDAR_TREE", _CEDAR, rng)


static func _convert_one_hardwood_in_acre(
	data: WorldData, bx: int, bz: int, visual: StringName, payload: Resource
) -> void:
	var origin: Vector2i = _fg_origin(bx, bz)
	for o: ObjectPlacement in data.objects:
		if o == null or o.kind != &"tree":
			continue
		if o.visual_id != &"TREE":
			continue
		if o.cell.x < origin.x or o.cell.x >= origin.x + UT:
			continue
		if o.cell.y < origin.y or o.cell.y >= origin.y + UT:
			continue
		o.visual_id = visual
		o.payload = payload
		return


static func _convert_n_hardwood_in_acre(
	data: WorldData,
	bx: int,
	bz: int,
	count: int,
	visual: StringName,
	payload: Resource,
	rng: RandomNumberGenerator
) -> void:
	if count <= 0:
		return
	var origin: Vector2i = _fg_origin(bx, bz)
	var candidates: Array[ObjectPlacement] = []
	for o: ObjectPlacement in data.objects:
		if o == null or o.kind != &"tree" or o.visual_id != &"TREE":
			continue
		if o.cell.x < origin.x or o.cell.x >= origin.x + UT:
			continue
		if o.cell.y < origin.y or o.cell.y >= origin.y + UT:
			continue
		candidates.append(o)
	var n: int = mini(count, candidates.size())
	for i: int in n:
		var idx: int = rng.randi_range(i, candidates.size() - 1)
		var tmp: ObjectPlacement = candidates[i]
		candidates[i] = candidates[idx]
		candidates[idx] = tmp
		candidates[i].visual_id = visual
		candidates[i].payload = payload


static func _pull_border_trees(data: WorldData) -> void:
	## `mSDI_PullTree`: strip west column of left FG acres and east column of right FG acres.
	var blocked: Dictionary = {}
	for bz: int in range(1, 7):
		var left: Vector2i = _fg_origin(1, bz)
		var right: Vector2i = _fg_origin(5, bz)
		for uz: int in UT:
			blocked[left + Vector2i(0, uz)] = true
			blocked[right + Vector2i(UT - 1, uz)] = true
	var keep: Array[ObjectPlacement] = []
	for o: ObjectPlacement in data.objects:
		if o != null and o.kind == &"tree" and blocked.has(o.cell):
			continue
		if o != null:
			keep.append(o)
	data.objects = keep


static func _acre_visual(data: WorldData, bx: int, bz: int) -> StringName:
	if data.acre_visuals.size() != TownFieldGenerator.BLOCK_TOTAL:
		return data.acre_visual
	return StringName(data.acre_visuals[bz * TownFieldGenerator.BLOCK_X + bx])


static func _tree_payload(kind: String) -> Resource:
	match kind:
		"cedar":
			return _CEDAR
		"apple":
			return _APPLE_TREE
		"palm":
			return _PALM
		_:
			return _HARDWOOD


static func _scatter_trees(
	data: WorldData, rng: RandomNumberGenerator, origin: Vector2i, count: int, bz: int, id_base: int
) -> void:
	var placed := 0
	var guard := 0
	while placed < count and guard < count * 12:
		guard += 1
		var cell := Vector2i(origin.x + rng.randi_range(1, UT - 2), origin.y + rng.randi_range(1, UT - 2))
		if not _is_open_grass(data, cell):
			continue
		if _too_close_to_spawn(data, cell, 3):
			continue
		var vis: StringName
		var payload: Resource
		if bz <= 3 and rng.randi() % 5 == 0:
			vis = &"CEDAR_TREE"
			payload = _CEDAR
		elif rng.randi() % 4 == 0:
			vis = &"TREE_APPLE_FRUIT"
			payload = _APPLE_TREE
		else:
			vis = &"TREE"
			payload = _HARDWOOD
		data.objects.append(
			_object(StringName("tree_%d" % (id_base + placed)), &"tree", cell, payload, vis)
		)
		placed += 1


static func _scatter_palms(data: WorldData, rng: RandomNumberGenerator, origin: Vector2i, count: int) -> void:
	var placed := 0
	var guard := 0
	while placed < count and guard < 40:
		guard += 1
		var cell := Vector2i(origin.x + rng.randi_range(1, UT - 2), origin.y + rng.randi_range(1, UT - 2))
		if data.terrain_at(cell) != WorldGrid.Terrain.SAND:
			continue
		if not _attr_allows_palm(data, cell):
			continue
		if _occupied(data, cell):
			continue
		data.objects.append(
			_object(StringName("palm_%d_%d" % [origin.x, placed]), &"tree", cell, _PALM, &"TREE_PALM_FRUIT")
		)
		placed += 1


static func _scatter_flowers(
	data: WorldData, rng: RandomNumberGenerator, origin: Vector2i, count: int, id_base: int
) -> void:
	var flowers: Array[StringName] = [&"FLOWER_PANSIES0", &"FLOWER_PANSIES1", &"FLOWER_PANSIES2"]
	var placed := 0
	var guard := 0
	while placed < count and guard < 40:
		guard += 1
		var cell := Vector2i(origin.x + rng.randi_range(1, UT - 2), origin.y + rng.randi_range(1, UT - 2))
		if not _is_open_grass(data, cell):
			continue
		data.objects.append(
			_object(
				StringName("flower_%d" % (id_base + placed)),
				&"flower",
				cell,
				null,
				flowers[placed % flowers.size()]
			)
		)
		placed += 1


static func _scatter_rocks(
	data: WorldData, rng: RandomNumberGenerator, origin: Vector2i, count: int, id_base: int
) -> void:
	var rocks: Array[StringName] = [&"ROCK_A", &"ROCK_B", &"ROCK_C", &"ROCK_D", &"ROCK_E"]
	var placed := 0
	var guard := 0
	while placed < count and guard < 20:
		guard += 1
		var cell := Vector2i(origin.x + rng.randi_range(1, UT - 2), origin.y + rng.randi_range(1, UT - 2))
		if not _is_open_grass(data, cell):
			continue
		data.objects.append(
			_object(
				StringName("rock_%d" % (id_base + placed)),
				&"rock",
				cell,
				null,
				rocks[rng.randi_range(0, rocks.size() - 1)]
			)
		)
		placed += 1


static func _clear_house_path(data: WorldData) -> void:
	## `mFI_PullTanukiPathTrees` / `mSDI_PullTreeUnderPlayerBlock`: C-3 (`fg[2][2]`),
	## units ux 7–8 and uz 0–2 (door faces south into the next acre).
	var blocked: Dictionary = {}
	var path_origin: Vector2i = _fg_origin(3, 3)
	for uz: int in range(0, 3):
		for ux: int in [7, 8]:
			var cell := path_origin + Vector2i(ux, uz)
			blocked[cell] = true
			if data.terrain_at(cell) == WorldGrid.Terrain.GRASS:
				data.set_terrain_cell(cell, WorldGrid.Terrain.PATH)
	var keep: Array[ObjectPlacement] = []
	for o: ObjectPlacement in data.objects:
		if o == null:
			continue
		if o.kind == &"tree" and blocked.has(o.cell):
			continue
		keep.append(o)
	data.objects = keep


static func _is_open_grass(data: WorldData, cell: Vector2i) -> bool:
	if not data.is_in_bounds(cell):
		return false
	if data.terrain_at(cell) != WorldGrid.Terrain.GRASS:
		return false
	if not _attr_allows_plant(data, cell):
		return false
	return not _occupied(data, cell)


static func _attr_allows_plant(data: WorldData, cell: Vector2i) -> bool:
	var unit: Dictionary = _unit_at_cell(data, cell)
	if unit.is_empty():
		return true
	return FieldCatalog.is_plantable_attr(int(unit.get("a", 0)))


static func _attr_allows_palm(data: WorldData, cell: Vector2i) -> bool:
	var unit: Dictionary = _unit_at_cell(data, cell)
	if unit.is_empty():
		return true
	return FieldCatalog.is_sand_attr(int(unit.get("a", 0)))


static func _unit_at_cell(data: WorldData, cell: Vector2i) -> Dictionary:
	var visual := _visual_at_cell(data, cell)
	if visual == &"":
		return {}
	return FieldCatalog.unit_at(visual, posmod(cell.x, UT), posmod(cell.y, UT))


static func _visual_at_cell(data: WorldData, cell: Vector2i) -> StringName:
	if data.acre_visuals.size() == TownFieldGenerator.BLOCK_TOTAL:
		var bx: int = cell.x / UT + 1
		var bz: int = cell.y / UT + 1
		if bx >= 1 and bx <= 5 and bz >= 1 and bz <= 6:
			return StringName(data.acre_visuals[bz * TownFieldGenerator.BLOCK_X + bx])
	return data.acre_visual


static func _occupied(data: WorldData, cell: Vector2i) -> bool:
	for b: BuildingPlacement in data.buildings:
		if b == null:
			continue
		if _in_footprint(cell, b.cell, b.footprint):
			return true
	for o: ObjectPlacement in data.objects:
		if o == null or not o.occupy_grid:
			continue
		if _in_footprint(cell, o.cell, o.footprint):
			return true
	for s: SpawnPoint in data.spawn_points:
		if s != null and s.cell == cell:
			return true
	return false


static func _in_footprint(cell: Vector2i, anchor: Vector2i, size: Vector2i) -> bool:
	return (
		cell.x >= anchor.x
		and cell.y >= anchor.y
		and cell.x < anchor.x + maxi(size.x, 1)
		and cell.y < anchor.y + maxi(size.y, 1)
	)


static func _too_close_to_spawn(data: WorldData, cell: Vector2i, radius: int) -> bool:
	var spawn: SpawnPoint = data.player_spawn()
	return absi(cell.x - spawn.cell.x) + absi(cell.y - spawn.cell.y) < radius


static func _first_open_near_spawn(data: WorldData, radius: int) -> Vector2i:
	var spawn: Vector2i = data.player_spawn().cell
	for z: int in range(spawn.y - radius, spawn.y + radius + 1):
		for x: int in range(spawn.x - radius, spawn.x + radius + 1):
			var cell := Vector2i(x, z)
			if cell == spawn:
				continue
			if _is_open_grass(data, cell):
				return cell
	return Vector2i(-1, -1)


static func _building(
	id: StringName, kind: StringName, cell: Vector2i, footprint: Vector2i, occupy: bool, visual_id: StringName = &""
) -> BuildingPlacement:
	var b := BuildingPlacement.new()
	b.id = id
	b.kind = kind
	b.cell = cell
	b.footprint = footprint
	b.occupy_grid = occupy
	b.visual_id = visual_id if visual_id != &"" else FieldCatalog.default_visual(kind)
	return b


static func _object(
	id: StringName, kind: StringName, cell: Vector2i, payload: Resource, visual_id: StringName = &""
) -> ObjectPlacement:
	var o := ObjectPlacement.new()
	o.id = id
	o.kind = kind
	o.cell = cell
	o.payload = payload
	o.visual_id = visual_id if visual_id != &"" else FieldCatalog.default_visual(kind)
	return o


static func _item(id: StringName, cell: Vector2i, item: ItemData) -> ObjectPlacement:
	var o := _object(id, &"item", cell, item)
	o.persist_id = id
	return o


static func _sign(id: StringName, cell: Vector2i, message: String) -> ObjectPlacement:
	var o := _object(id, &"sign", cell, null)
	o.message = message
	return o


static func _villager(id: StringName, cell: Vector2i, villager: VillagerData) -> ObjectPlacement:
	var o := _object(id, &"villager", cell, villager)
	o.occupy_grid = false
	return o


static func _spawn(id: StringName, cell: Vector2i, yaw: float) -> SpawnPoint:
	var s := SpawnPoint.new()
	s.id = id
	s.cell = cell
	s.yaw = yaw
	return s
