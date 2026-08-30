class_name WorldGenerator
extends RefCounted

## Town layout. New Game uses TownFieldGenerator (mRF-style acres) then rasterizes FG units.

const DEFAULT_SEED := 12345
const UT := 16
const FG_X := 5
const FG_Z := 6
## FG_TYPE_GRD_S_F_MH_* / FG_TYPE_0069: four player plots on B-3 (`mHS_HOUSE0`–`3`).
## Actor ct: west +20 X, east −20 X; both +20 Z (`aMHS_posX_table`).
const HOUSE0_UT := Vector2i(3, 3)
const HOUSE1_UT := Vector2i(12, 3)
const HOUSE2_UT := Vector2i(3, 10)
const HOUSE3_UT := Vector2i(12, 10)
## SHOP0 is (10, 9) on `grd_s_t_sh_1` and (10, 10) on `_2`/`_3`. Actor ct adds
## −20 X, +20 Z, so the 2×2 NW is (SHOP0.x − 1, SHOP0.z).
const SHOP0_UT := Vector2i(10, 10)
const SHOP0_UT_SH1 := Vector2i(10, 9)
## TRAIN_STATION is (8, 5) on every `FG_TYPE_GRD_S_T_ST1_*`. `aSTA_actor_ct` is −20 X only.
const STATION_UT := Vector2i(8, 5)
## NEEDLEWORK_SHOP is (9, 4) on `grd_s_m_ta_1`/`_2` and (9, 5) on `_3`.
## `aNW_actor_ct` is −20 X, +20 Z — same 2×2 as the shop (`nw_off` (−1, 0)).
const NEEDLEWORK_UT := Vector2i(9, 4)
const NEEDLEWORK_UT_TA3 := Vector2i(9, 5)
## New-game villagers: one per personality (`mNpc_LOOKS_NUM` / `mNpc_InitNpcAllInfo`).
const STARTER_NPC_HOUSES := 6

const _APPLE := preload("res://data/items/apple.tres")
const _SHOVEL := preload("res://data/items/shovel.tres")
const _AXE := preload("res://data/items/axe.tres")
const _NET := preload("res://data/items/net.tres")
const _ROD := preload("res://data/items/fishing_rod.tres")
const _CAN := preload("res://data/items/watering_can.tres")
const _APPLE_TREE := preload("res://data/plants/apple_tree.tres")
const _HARDWOOD := preload("res://data/plants/hardwood_tree.tres")
const _CEDAR := preload("res://data/plants/cedar_tree.tres")
const _PALM := preload("res://data/plants/palm_tree.tres")
const _PANSY := preload("res://data/plants/pansy.tres")
const _SAPLING := preload("res://data/items/apple_sapling.tres")
const _FILBERT := preload("res://data/villagers/filbert.tres")
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
		_building(&"player_house", &"house", Vector2i(7, 1), Vector2i(2, 2), true, &"obj_s_myhome1"),
		_building(&"acre_shop", &"shop", Vector2i(12, 1), Vector2i(2, 2), false, &"obj_s_shop1"),
		_filbert_house(),
	]
	data.objects = [
		_object(&"tree_1", &"tree", Vector2i(4, 6), _APPLE_TREE, &"TREE_APPLE_FRUIT"),
		_object(&"tree_2", &"tree", Vector2i(12, 5), _APPLE_TREE, &"TREE_APPLE_FRUIT"),
		_object(&"tree_3", &"tree", Vector2i(5, 12), _HARDWOOD, &"TREE"),
		_item(&"ground_apple", Vector2i(8, 10), _APPLE),
		_item(&"ground_shovel", Vector2i(2, 11), _SHOVEL),
		_item(&"ground_axe", Vector2i(2, 12), _AXE),
		_item(&"ground_net", Vector2i(1, 11), _NET),
		_item(&"ground_rod", Vector2i(1, 12), _ROD),
		_item(&"ground_can", Vector2i(3, 11), _CAN),
		_item(&"ground_sapling", Vector2i(3, 12), _SAPLING),
		_sign(&"acre_sign", Vector2i(9, 11), "Welcome to the acre."),
		_object(&"yard_chair", &"furniture", Vector2i(9, 3), _CHAIR, &"int_sum_chair01"),
		_object(&"pansy_1", &"flower", Vector2i(6, 10), _PANSY, &"FLOWER_PANSIES0"),
		_object(&"rock_1", &"rock", Vector2i(3, 8), null, &"ROCK_A"),
		_door(&"house_door", Vector2i(7, 3), "House"),
		_villager(&"filbert", Vector2i(10, 9), _FILBERT),
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
	data.bake()
	return data


static func map_text(data: WorldData) -> String:
	## ASCII 7×10 acre map (`mFM` block grid). Rows A–F are the playable field.
	if data == null:
		return ""
	if data.acre_types.size() != TownFieldGenerator.BLOCK_TOTAL:
		return "%s (%dx%d)" % [data.display_name, data.columns, data.rows]
	var lines: PackedStringArray = PackedStringArray()
	lines.append(
		"=== %s  seed=%d ===" % [data.display_name, data.seed_value]
	)
	lines.append("     0     1     2     3     4     5     6")
	for bz: int in TownFieldGenerator.BLOCK_Z:
		var row_id: String = char(64 + bz) if bz >= 1 and bz <= 6 else str(bz)
		var cells: PackedStringArray = PackedStringArray()
		for bx: int in TownFieldGenerator.BLOCK_X:
			var i: int = bz * TownFieldGenerator.BLOCK_X + bx
			var abbrev: String = TownFieldGenerator.acre_abbrev(int(data.acre_types[i]))
			var h: int = 0
			if data.acre_heights.size() == TownFieldGenerator.BLOCK_TOTAL:
				h = int(data.acre_heights[i])
			cells.append("%s:%d" % [abbrev, h])
		lines.append("%2s  %s" % [row_id, "  ".join(cells)])
	var extras: PackedStringArray = PackedStringArray()
	for b: BuildingPlacement in data.buildings:
		if b == null:
			continue
		var bx: int = b.cell.x / UT + 1
		var bz: int = b.cell.y / UT + 1
		if bz >= 1 and bz <= 6 and bx >= 1 and bx <= 5:
			extras.append("  %s-%d  %s" % [char(64 + bz), bx, b.id])
	if not extras.is_empty():
		lines.append("Structures:")
		lines.append_array(extras)
	return "\n".join(lines)


static func _pick_acre_visuals(blocks: PackedByteArray, seed_value: int) -> PackedStringArray:
	var visuals := PackedStringArray()
	visuals.resize(TownFieldGenerator.BLOCK_TOTAL)
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_value as int) ^ 0xC0FFEE
	## `mRF_SelectBlock` / `l_use_data`: prefer a combi this town has not used yet.
	var used := PackedStringArray()
	for i: int in TownFieldGenerator.BLOCK_TOTAL:
		var type: int = int(blocks[i])
		var pick: StringName = FieldCatalog.acre_for_block_type(type, int(rng.randi()), used)
		visuals[i] = String(pick)
		if not String(pick).is_empty():
			used.append(String(pick))
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
		if TownFieldGenerator.is_river_bridge(type):
			_paint_bridge_deck(data, origin, visual)
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
			elif FieldCatalog.is_stone_bridge_attr(attr):
				data.set_terrain_cell(cell, WorldGrid.Terrain.STONE)
			elif FieldCatalog.is_wood_bridge_attr(attr):
				data.set_terrain_cell(cell, WorldGrid.Terrain.PATH)
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
		or type == TownFieldGenerator.T_RIVER_S_BRIDGE
		or type == TownFieldGenerator.T_RIVER_SE_BRIDGE
		or type == TownFieldGenerator.T_RIVER_SW_BRIDGE
		or type == TownFieldGenerator.T_BEACH_RIVER
		or type == TownFieldGenerator.T_BEACH_RIVER_BRIDGE
		or type == TownFieldGenerator.T_TRACKS_RIVER
		or type == TownFieldGenerator.T_BORDER_CLIFF_RIVER
		or (type >= TownFieldGenerator.T_WF_H and type <= TownFieldGenerator.T_WF_W_BL)
	)
	var eastish: bool = (
		type == TownFieldGenerator.T_RIVER_E
		or type == TownFieldGenerator.T_RIVER_ES
		or type == TownFieldGenerator.T_RIVER_SE
		or type == TownFieldGenerator.T_RIVER_E_BRIDGE
		or type == TownFieldGenerator.T_RIVER_ES_BRIDGE
		or type == TownFieldGenerator.T_RIVER_SE_BRIDGE
	)
	var westish: bool = (
		type == TownFieldGenerator.T_RIVER_W
		or type == TownFieldGenerator.T_RIVER_WS
		or type == TownFieldGenerator.T_RIVER_SW
		or type == TownFieldGenerator.T_RIVER_W_BRIDGE
		or type == TownFieldGenerator.T_RIVER_WS_BRIDGE
		or type == TownFieldGenerator.T_RIVER_SW_BRIDGE
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


static func _paint_bridge_deck(data: WorldData, origin: Vector2i, visual: StringName = &"") -> void:
	## Geometric stand-in when `grd_*` collision is missing. Wood vs stone follows
	## the combi BG (`bridge_2_tex` / `bridge_1_tex`), same as `mCoBG_ATTRIBUTE_*`.
	var deck: WorldGrid.Terrain = (
		WorldGrid.Terrain.STONE if FieldCatalog.is_stone_bridge_visual(visual) else WorldGrid.Terrain.PATH
	)
	for uz: int in range(5, 7):
		for ux: int in range(5, 11):
			var cell := Vector2i(origin.x + ux, origin.y + uz)
			if data.terrain_at(cell) == WorldGrid.Terrain.WATER:
				data.set_terrain_cell(cell, deck)


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
	## Acre-type fallbacks use the same actor_ct offsets as FG templates (`FgCatalog`).
	var house_origin: Vector2i = _fg_origin(3, 2)
	_place_structure_item(data, house_origin, HOUSE0_UT, FgCatalog.ITEM_HOUSE0)
	_place_structure_item(data, house_origin, HOUSE1_UT, FgCatalog.ITEM_HOUSE1)
	_place_structure_item(data, house_origin, HOUSE2_UT, FgCatalog.ITEM_HOUSE2)
	_place_structure_item(data, house_origin, HOUSE3_UT, FgCatalog.ITEM_HOUSE3)
	var house_cell: Vector2i = _building_cell(data, &"player_house")
	data.spawn_points = [_spawn(&"player", Vector2i(house_cell.x + 1, house_cell.y + 4), 0.0)]
	var unique_ut := Vector2i(7, 7)
	for bz: int in range(1, 7):
		for bx: int in range(1, 6):
			var type: int = _block(blocks, bx, bz)
			var origin: Vector2i = _fg_origin(bx, bz)
			match type:
				TownFieldGenerator.T_TRACKS_SHOP:
					_place_structure_item(data, origin, _shop0_unit(data, bx, bz), FgCatalog.ITEM_SHOP0)
				TownFieldGenerator.T_TRACKS_STATION:
					_place_structure_item(data, origin, STATION_UT, FgCatalog.ITEM_TRAIN_STATION)
				TownFieldGenerator.T_TRACKS_POST:
					_place_structure_item(data, origin, unique_ut, FgCatalog.ITEM_POST_OFFICE)
				TownFieldGenerator.T_MUSEUM:
					_place_structure_item(data, origin, unique_ut, FgCatalog.ITEM_MUSEUM)
				TownFieldGenerator.T_POLICE:
					_place_structure_item(data, origin, unique_ut, FgCatalog.ITEM_POLICE_STATION)
				TownFieldGenerator.T_SHRINE:
					_place_structure_item(data, origin, unique_ut, FgCatalog.ITEM_WISHING_WELL)
				TownFieldGenerator.T_NEEDLEWORK:
					_place_structure_item(
						data, origin, _needlework_unit(data, bx, bz), FgCatalog.ITEM_NEEDLEWORK_SHOP
					)
				TownFieldGenerator.T_PORT:
					data.objects.append(_sign(&"dock_sign", origin + unique_ut, "Dock"))


static func _shop0_unit(data: WorldData, bx: int, bz: int) -> Vector2i:
	if data.acre_visuals.size() != TownFieldGenerator.BLOCK_TOTAL:
		return SHOP0_UT
	var visual := String(data.acre_visuals[bz * TownFieldGenerator.BLOCK_X + bx])
	if visual.ends_with("sh_1"):
		return SHOP0_UT_SH1
	return SHOP0_UT


static func _needlework_unit(data: WorldData, bx: int, bz: int) -> Vector2i:
	if data.acre_visuals.size() != TownFieldGenerator.BLOCK_TOTAL:
		return NEEDLEWORK_UT
	var visual := String(data.acre_visuals[bz * TownFieldGenerator.BLOCK_X + bx])
	if visual.ends_with("ta_3"):
		return NEEDLEWORK_UT_TA3
	return NEEDLEWORK_UT


static func _place_structure_item(
	data: WorldData, origin: Vector2i, ut: Vector2i, item_id: int
) -> void:
	var place: Dictionary = FgCatalog.placement_for_item(item_id)
	if place.is_empty():
		return
	_apply_fg_structure(data, origin + ut, place)


static func _place_fg_props(data: WorldData, blocks: PackedByteArray, seed_value: int) -> void:
	## Prefer disc FG templates (`mFM_InitFgCombiSaveData`); scatter only as fallback.
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_value as int) ^ 0x9E3779B9
	var reserves: Array[Vector2i] = []
	if FgCatalog.has_catalog():
		reserves = _place_from_fg_templates(data, blocks, rng)
	else:
		_place_fg_props_scatter(data, blocks, rng)
	## `mSDI_PullTree` / `mFI_PullTanukiPathTrees` before fruit/cedar (`mSDI_StartInitNew`).
	_pull_border_trees(data)
	_clear_house_path(data)
	if FgCatalog.has_catalog():
		_change_tree_to_fruit(data, rng)
		_change_tree_to_cedar(data, rng)
		## Most outdoor FG templates are tree-heavy; a few flats still get flower beds.
		if _kind_count(data, &"flower") == 0:
			_scatter_backup_flowers(data, blocks, rng)
	var apple_cell := _first_open_near_spawn(data, 5)
	if apple_cell != Vector2i(-1, -1):
		data.objects.append(_item(&"ground_apple", apple_cell, _APPLE))
	_place_villager_homes(data, reserves, rng)
	_place_starter_villagers(data, rng)
	_remove_objects_under_buildings(data)


static func _place_from_fg_templates(
	data: WorldData, blocks: PackedByteArray, rng: RandomNumberGenerator
) -> Array[Vector2i]:
	## Returns SIGN reserve cells (`mNT_IS_RESERVE`) for villager house assignment.
	var reserves: Array[Vector2i] = []
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
					var kind: StringName = place["kind"]
					match kind:
						&"reserve":
							reserves.append(cell)
						&"structure":
							_apply_fg_structure(data, cell, place)
						&"tree":
							## Copy the template cell even if an acre-type building still sits on
							## a placeholder unit; houses later overwrite the SIGN 3×3.
							var payload: Resource = _tree_payload(String(place.get("tree", "hardwood")))
							data.objects.append(
								_object(
									StringName("tree_%d" % tree_n),
									&"tree",
									cell,
									payload,
									place["visual"]
								)
							)
							tree_n += 1
						&"flower":
							data.objects.append(
								_object(
									StringName("flower_%d" % flower_n),
									&"flower",
									cell,
									_PANSY,
									place["visual"]
								)
							)
							flower_n += 1
						&"rock":
							data.objects.append(
								_object(
									StringName("rock_%d" % rock_n), &"rock", cell, null, place["visual"]
								)
							)
							rock_n += 1
	return reserves


static func _apply_fg_structure(data: WorldData, cell: Vector2i, place: Dictionary) -> void:
	## Refine acre-type buildings to FG unit + actor NW offset when the template has them.
	var bkind: StringName = place.get("building", &"building")
	var label: String = String(place.get("label", ""))
	var vis: StringName = place.get("visual", &"")
	var foot: Vector2i = place.get("foot", Vector2i(2, 2))
	var nw: Vector2i = place.get("nw_off", Vector2i.ZERO)
	var door_verb: StringName = place.get("door_verb", &"enter")
	var facing: WorldGrid.Facing = place.get("facing", WorldGrid.Facing.SOUTH) as WorldGrid.Facing
	var mesh_facing: WorldGrid.Facing = place.get("mesh_facing", facing) as WorldGrid.Facing
	var actor_shift: Vector2 = place.get("actor_shift", Vector2.ZERO)
	var occupy: bool = bool(place.get("occupy", true))
	var anchor: Vector2i = cell + nw
	var id: StringName = &""
	if place.has("id"):
		id = place["id"] as StringName
	if id == &"":
		match label:
			"Museum":
				id = &"museum"
			"Able Sisters":
				id = &"able_sisters"
			"Post Office":
				id = &"post_office"
			"Police Station":
				id = &"police"
			"Wishing Well":
				id = &"wishing_well"
			"Shop":
				id = &"acre_shop"
			"House":
				id = &"player_house"
			"Train Station":
				id = &"station"
			_:
				id = StringName("structure_%d_%d" % [cell.x, cell.y])
	## Replace matching acre-type placeholder when present.
	for i: int in data.buildings.size():
		var b: BuildingPlacement = data.buildings[i]
		if b != null and b.id == id:
			b.cell = anchor
			b.footprint = foot
			b.kind = bkind
			b.visual_id = vis
			b.label = label
			b.door_verb = door_verb
			b.facing = facing
			b.mesh_facing = mesh_facing
			b.actor_shift = actor_shift
			b.occupy_grid = occupy
			return
	data.buildings.append(
		_labeled_building(
			id, bkind, anchor, foot, occupy, vis, label, door_verb, facing, actor_shift, mesh_facing
		)
	)


static func _place_villager_homes(
	data: WorldData, reserves: Array[Vector2i], rng: RandomNumberGenerator
) -> void:
	## Decomp: shuffle SIGN reserves, assign `mNpc_LOOKS_NUM` starter homes
	## (`mNpc_SetNpcHome` / `mNpc_BuildHouseBeforeFieldct`). Starter animals
	## spawn in the yard (`_place_starter_villagers`).
	var plots: Array[Vector2i] = []
	for r: Vector2i in reserves:
		if _sign_fits_house(r):
			plots.append(r)
	if plots.is_empty():
		plots = _synthetic_house_plots(data, rng)
	## Fisher–Yates (`mNpc_MakeRandTable` is a different shuffle; same “pick N plots”).
	for i: int in range(plots.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = plots[i]
		plots[i] = plots[j]
		plots[j] = tmp
	var placed := 0
	for reserve: Vector2i in plots:
		if placed >= STARTER_NPC_HOUSES:
			break
		if not _sign_fits_house(reserve):
			continue
		if _house_plot_blocked(data, reserve):
			continue
		## House FG item sits on the SIGN unit; `aHUS_actor_ct` has no extra offset.
		## RSV occupies the 3×3 around that unit (`mNpc_BuildHouseBeforeFieldct`).
		var house_cell := Vector2i(reserve.x - 1, reserve.y - 1)
		## Overwrite template trees/rocks/flowers in the 3×3, same as `set_fg[]`.
		_remove_objects_in_house_plot(data, reserve)
		data.buildings.append(
			_labeled_building(
				StringName("npc_house_%d" % placed),
				&"house",
				house_cell,
				Vector2i(3, 3),
				true,
				&"obj_s_house1",
				"House"
			)
		)
		placed += 1


static func _place_starter_villagers(data: WorldData, rng: RandomNumberGenerator) -> void:
	## `mNpc_InitNpcAllInfo` / `mNpc_DecideLivingNpcMax`: `now_npc_max = mNpc_LOOKS_NUM`,
	## one starter per looks from a shuffled pool. Homes were already shuffled.
	var houses: Array[BuildingPlacement] = []
	for b: BuildingPlacement in data.buildings:
		if b != null and String(b.id).begins_with("npc_house_"):
			houses.append(b)
	houses.sort_custom(
		func(a: BuildingPlacement, b: BuildingPlacement) -> bool: return String(a.id) < String(b.id)
	)
	var picked: Array[VillagerData] = VillagerCatalog.pick_starters(rng, STARTER_NPC_HOUSES)
	var n: int = mini(houses.size(), picked.size())
	for i: int in n:
		var house: BuildingPlacement = houses[i]
		var villager: VillagerData = picked[i]
		house.resident_id = villager.id
		if villager.display_name != "":
			house.label = "%s's House" % villager.display_name
		var cell: Vector2i = _yard_cell(data, house.cell, house.footprint)
		data.objects.append(_villager(villager.id, cell, villager))


static func _yard_cell(data: WorldData, house_nw: Vector2i, footprint: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = [
		Vector2i(house_nw.x + footprint.x / 2, house_nw.y + footprint.y),
		Vector2i(house_nw.x + footprint.x, house_nw.y + footprint.y / 2),
		Vector2i(house_nw.x - 1, house_nw.y + footprint.y / 2),
		Vector2i(house_nw.x + footprint.x / 2, house_nw.y - 1),
	]
	for cell: Vector2i in candidates:
		if not data.is_in_bounds(cell):
			continue
		if data.terrain_at(cell) == WorldGrid.Terrain.WATER:
			continue
		if data.terrain_at(cell) == WorldGrid.Terrain.CLIFF:
			continue
		return cell
	return Vector2i(house_nw.x + 1, house_nw.y + 1)


static func _sign_fits_house(reserve: Vector2i) -> bool:
	## `mNpc_BuildHouseBeforeFieldct`: SIGN ut must be 1..14 so the 3×3 stays in-acre.
	var ux: int = posmod(reserve.x, UT)
	var uz: int = posmod(reserve.y, UT)
	return ux > 0 and ux < UT - 1 and uz > 0 and uz < UT - 1


static func _house_plot_blocked(data: WorldData, sign: Vector2i) -> bool:
	## Skip a SIGN whose 3×3 would sit on an existing occupied building.
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var cell: Vector2i = sign + Vector2i(dx, dz)
			for b: BuildingPlacement in data.buildings:
				if b == null or not b.occupy_grid:
					continue
				if _in_footprint(cell, b.cell, b.footprint):
					return true
	return false


static func _remove_objects_in_house_plot(data: WorldData, sign: Vector2i) -> void:
	var blocked: Dictionary = {}
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			blocked[sign + Vector2i(dx, dz)] = true
	var keep: Array[ObjectPlacement] = []
	for o: ObjectPlacement in data.objects:
		if o != null and blocked.has(o.cell):
			continue
		if o != null:
			keep.append(o)
	data.objects = keep


static func _remove_objects_under_buildings(data: WorldData) -> void:
	## FG copy can land a tree on an acre-type placeholder unit; drop it after
	## structures settle (`mNpc_BuildHouseBeforeFieldct` `mPB_keep_item`).
	var keep: Array[ObjectPlacement] = []
	for o: ObjectPlacement in data.objects:
		if o == null:
			continue
		var under := false
		for b: BuildingPlacement in data.buildings:
			if b == null or not b.occupy_grid:
				continue
			if _in_footprint(o.cell, b.cell, b.footprint):
				under = true
				break
		if not under:
			keep.append(o)
	data.objects = keep


static func _synthetic_house_plots(data: WorldData, rng: RandomNumberGenerator) -> Array[Vector2i]:
	## Fallback when FG catalog has no SIGN* items: open grass on flat acres away from B3.
	var out: Array[Vector2i] = []
	for _i: int in 40:
		var cell := Vector2i(rng.randi_range(4, data.columns - 5), rng.randi_range(20, data.rows - 8))
		if not _sign_fits_house(cell):
			continue
		if _near_player_house(data, cell, 12):
			continue
		if not _is_open_grass(data, cell):
			continue
		if not _is_open_grass(data, Vector2i(cell.x, cell.y + 1)):
			continue
		out.append(cell)
		if out.size() >= 6:
			break
	return out


static func _building_cell(data: WorldData, id: StringName) -> Vector2i:
	for b: BuildingPlacement in data.buildings:
		if b != null and b.id == id:
			return b.cell
	return Vector2i(35, 19)


static func _near_player_house(data: WorldData, cell: Vector2i, radius: int) -> bool:
	for b: BuildingPlacement in data.buildings:
		if b == null or not String(b.id).begins_with("player_house"):
			continue
		if absi(cell.x - b.cell.x) + absi(cell.y - b.cell.y) < radius:
			return true
	return false


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
				_PANSY,
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
	id: StringName,
	kind: StringName,
	cell: Vector2i,
	footprint: Vector2i,
	occupy: bool,
	visual_id: StringName = &"",
	mesh_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
) -> BuildingPlacement:
	return _labeled_building(
		id, kind, cell, footprint, occupy, visual_id, "", &"enter", WorldGrid.Facing.SOUTH, Vector2.ZERO, mesh_facing
	)


static func _labeled_building(
	id: StringName,
	kind: StringName,
	cell: Vector2i,
	footprint: Vector2i,
	occupy: bool,
	visual_id: StringName,
	label: String,
	door_verb: StringName = &"enter",
	facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH,
	actor_shift: Vector2 = Vector2.ZERO,
	mesh_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
) -> BuildingPlacement:
	var b := BuildingPlacement.new()
	b.id = id
	b.kind = kind
	b.cell = cell
	b.footprint = footprint
	b.occupy_grid = occupy
	b.visual_id = visual_id if visual_id != &"" else FieldCatalog.default_visual(kind)
	b.label = label
	b.door_verb = door_verb
	b.facing = facing
	b.actor_shift = actor_shift
	b.mesh_facing = mesh_facing
	return b


static func _filbert_house() -> BuildingPlacement:
	var house: BuildingPlacement = _building(
		&"npc_house_0", &"house", Vector2i(1, 1), Vector2i(2, 2), true, &"obj_s_house1"
	)
	house.resident_id = &"filbert"
	house.label = "Filbert's House"
	return house


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


static func _door(id: StringName, cell: Vector2i, label: String) -> ObjectPlacement:
	var o := _object(id, &"door", cell, null)
	o.message = label
	o.occupy_grid = false
	return o


static func _spawn(id: StringName, cell: Vector2i, yaw: float) -> SpawnPoint:
	var s := SpawnPoint.new()
	s.id = id
	s.cell = cell
	s.yaw = yaw
	return s
