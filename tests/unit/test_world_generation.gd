class_name TestWorldGeneration
extends GdUnitTestSuite

## WorldGenerator produces data. WorldBuilder instances scenes.


func before_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = true


func after_test() -> void:
	Game.reset_session()
	Game.notify_title_ready()
	Clock.reset_to_default()
	Clock.paused = false


func test_authored_test_town_has_fixed_layout() -> void:
	var data: WorldData = WorldGenerator.authored_test_town()
	assert_that(data.mode).is_equal(WorldData.Mode.TEST)
	assert_that(data.id).is_equal(&"test_town")
	assert_that(data.terrain_at(Vector2i(12, 3))).is_equal(WorldGrid.Terrain.WATER)
	assert_that(data.terrain_at(Vector2i(0, 0))).is_equal(WorldGrid.Terrain.GRASS)
	assert_that(_building_at(data, &"player_house")).is_equal(Vector2i(7, 1))
	assert_that(_building_at(data, &"acre_shop")).is_equal(Vector2i(12, 1))
	assert_that(_building_at(data, &"npc_house_0")).is_equal(Vector2i(1, 1))
	assert_that(_building(data, &"npc_house_0").resident_id).is_equal(&"filbert")
	assert_that(_object_at(data, &"tree_1")).is_equal(Vector2i(4, 6))
	assert_that(_object_at(data, &"ground_apple")).is_equal(Vector2i(8, 10))
	assert_that(_object_at(data, &"ground_shovel")).is_equal(Vector2i(2, 11))
	assert_that(_object_at(data, &"acre_sign")).is_equal(Vector2i(9, 11))
	assert_that(_object_at(data, &"yard_chair")).is_equal(Vector2i(9, 3))
	assert_that(_object_at(data, &"filbert")).is_equal(Vector2i(10, 9))
	assert_that(_object_at(data, &"pansy_1")).is_equal(Vector2i(6, 10))
	assert_that(_object_at(data, &"ground_sapling")).is_equal(Vector2i(3, 12))
	assert_that(_object_at(data, &"rock_1")).is_equal(Vector2i(3, 8))
	assert_that(_object_at(data, &"house_door")).is_equal(Vector2i(7, 3))
	assert_that(_object_visual(data, &"tree_1")).is_equal(&"TREE_APPLE_FRUIT")
	assert_that(_object_visual(data, &"tree_3")).is_equal(&"TREE")
	assert_that(_building_visual(data, &"player_house")).is_equal(&"obj_s_myhome1")
	assert_that(_building_mesh_facing(data, &"player_house")).is_equal(WorldGrid.Facing.SOUTH)
	assert_that(_building_visual(data, &"acre_shop")).is_equal(&"obj_s_shop1")
	assert_that(data.acre_visual).is_equal(&"grd_s_f_1")
	assert_that(data.player_spawn().cell).is_equal(Vector2i(8, 11))


func test_same_seed_same_fingerprint() -> void:
	var a: WorldData = WorldGenerator.generate(12345)
	var b: WorldData = WorldGenerator.generate(12345)
	assert_str(a.fingerprint()).is_equal(b.fingerprint())
	assert_that(a.mode).is_equal(WorldData.Mode.GENERATED)
	assert_int(a.seed_value).is_equal(12345)
	assert_that(a.acre_visuals).is_equal(b.acre_visuals)
	assert_int(a.grass_pattern).is_equal(b.grass_pattern)


func test_grass_pattern_from_seed_is_stable() -> void:
	var a: int = WorldGenerator.decide_grass_pattern(12345)
	var b: int = WorldGenerator.decide_grass_pattern(12345)
	assert_int(a).is_equal(b)
	assert_int(a).is_greater_equal(0)
	assert_int(a).is_less(WorldData.GRASS_PATTERN_COUNT)
	var other: int = WorldGenerator.decide_grass_pattern(99999)
	## Not guaranteed different, but these seeds differ in practice.
	assert_int(other).is_greater_equal(0)


func test_different_seed_different_fingerprint() -> void:
	var a: WorldData = WorldGenerator.generate(12345)
	var b: WorldData = WorldGenerator.generate(99999)
	assert_str(a.fingerprint()).is_not_equal(b.fingerprint())


func test_generated_town_has_ac_structure() -> void:
	var data: WorldData = WorldGenerator.generate(12345)
	## Full FG town: 5×6 acres × 16 units.
	assert_int(data.columns).is_equal(80)
	assert_int(data.rows).is_equal(96)
	assert_int(data.acre_types.size()).is_equal(70)
	assert_bool(_has_terrain(data, WorldGrid.Terrain.WATER)).is_true()
	assert_bool(_has_terrain(data, WorldGrid.Terrain.SAND)).is_true()
	if _uses_acre_collision(data):
		## Cliff faces are walkable height jumps, not `CLIFF` columns.
		assert_bool(_has_elevation(data)).is_true()
	else:
		assert_bool(_has_terrain(data, WorldGrid.Terrain.CLIFF)).is_true()
	assert_bool(_has_elevation(data)).is_true()
	## B3 house acre (bx=3,bz=2) → unit origin (32, 16). Four plots (`mHS_HOUSE0`–`3`).
	assert_that(_building_at(data, &"player_house")).is_equal(Vector2i(35, 19))
	assert_that(_building_at(data, &"player_house_1")).is_equal(Vector2i(43, 19))
	assert_that(_building_at(data, &"player_house_2")).is_equal(Vector2i(35, 26))
	assert_that(_building_at(data, &"player_house_3")).is_equal(Vector2i(43, 26))
	assert_that(_building_mesh_facing(data, &"player_house")).is_equal(WorldGrid.Facing.WEST)
	assert_that(_building_mesh_facing(data, &"player_house_1")).is_equal(WorldGrid.Facing.SOUTH)
	assert_that(_building_mesh_facing(data, &"player_house_2")).is_equal(WorldGrid.Facing.WEST)
	assert_that(_building_mesh_facing(data, &"player_house_3")).is_equal(WorldGrid.Facing.SOUTH)
	assert_that(_building_at(data, &"acre_shop")).is_not_equal(Vector2i(-1, -1))
	## Shop is on tracks row A (bz=1 → unit y 0..15), not next to the house.
	var shop: Vector2i = _building_at(data, &"acre_shop")
	assert_int(shop.y).is_less(16)
	assert_int(shop.x % 16).is_equal(9)
	assert_bool(shop.y % 16 == 9 or shop.y % 16 == 10).is_true()
	assert_int(int(data.acre_types[1 * 7 + 3])).is_equal(TownFieldGenerator.T_TRACKS_STATION)
	assert_int(int(data.acre_types[2 * 7 + 3])).is_equal(TownFieldGenerator.T_PLAYER_HOUSE)
	assert_int(_kind_count(data, &"tree")).is_greater(0)
	assert_int(_kind_count(data, &"flower")).is_greater(0)
	assert_int(_kind_count(data, &"villager")).is_equal(WorldGenerator.STARTER_NPC_HOUSES)
	## Landmark acres become real buildings (not only signs).
	assert_that(_building_at(data, &"museum")).is_not_equal(Vector2i(-1, -1))
	assert_that(_building_at(data, &"able_sisters")).is_not_equal(Vector2i(-1, -1))
	assert_that(_building_label(data, &"museum")).is_equal("Museum")
	assert_that(_building_label(data, &"able_sisters")).is_equal("Able Sisters")
	assert_that(_building_visual(data, &"player_house")).is_equal(&"obj_s_myhome1")
	assert_that(_building_visual(data, &"player_house_3")).is_equal(&"obj_s_myhome1")
	assert_that(_building_visual(data, &"acre_shop")).is_equal(&"obj_s_shop1")
	assert_that(_building_visual(data, &"museum")).is_equal(&"obj_s_museum")
	assert_that(_building_visual(data, &"able_sisters")).is_equal(&"obj_s_tailor")
	assert_that(_building_visual(data, &"npc_house_0")).is_equal(&"obj_s_house1")
	assert_that(_building_at(data, &"station")).is_not_equal(Vector2i(-1, -1))
	assert_that(_building_visual(data, &"station")).is_equal(&"obj_s_station1")
	var station: BuildingPlacement = _building(data, &"station")
	assert_that(station.footprint).is_equal(Vector2i(1, 1))
	assert_that(station.actor_shift).is_equal(Vector2(-0.5, 0.0))
	## TRAIN_STATION is unit (8, 5) on every station acre; A-3 origin is (32, 0).
	assert_int(station.cell.x % 16).is_equal(8)
	assert_int(station.cell.y % 16).is_equal(5)
	## Museum acre is a unique flat below the cliff (`mRF_FlatBlock2Unique` / T_MUSEUM).
	var museum: Vector2i = _building_at(data, &"museum")
	var mus_bx: int = museum.x / 16 + 1
	var mus_bz: int = museum.y / 16 + 1
	assert_int(int(data.acre_types[mus_bz * 7 + mus_bx])).is_equal(TownFieldGenerator.T_MUSEUM)
	## Able Sisters on beach row F (bz=6). FG item is (9, 4) on ta_1/ta_2 and
	## (9, 5) on ta_3; occupancy NW is (−1, 0) like the shop.
	var able: Vector2i = _building_at(data, &"able_sisters")
	assert_int(able.y).is_greater_equal(80)
	assert_int(able.y).is_less(96)
	assert_int(able.x % 16).is_equal(8)
	assert_bool(able.y % 16 == 4 or able.y % 16 == 5).is_true()
	assert_int(int(data.acre_types[6 * 7 + (able.x / 16 + 1)])).is_equal(
		TownFieldGenerator.T_NEEDLEWORK
	)
	## `mNpc_LOOKS_NUM` starter homes on shuffled SIGN plots, plus one outdoor NPC each.
	assert_int(_npc_house_count(data)).is_equal(WorldGenerator.STARTER_NPC_HOUSES)
	var resident_ids: Dictionary = {}
	var resident_looks: Dictionary = {}
	for o: ObjectPlacement in data.objects:
		if o == null or o.kind != &"villager":
			continue
		var resident: VillagerData = o.payload as VillagerData
		assert_that(resident).is_not_null()
		assert_bool(resident_ids.has(resident.id)).is_false()
		resident_ids[resident.id] = true
		resident_looks[int(resident.personality.looks)] = true
	assert_int(resident_ids.size()).is_equal(WorldGenerator.STARTER_NPC_HOUSES)
	assert_int(resident_looks.size()).is_equal(WorldGenerator.STARTER_NPC_HOUSES)
	for i: int in WorldGenerator.STARTER_NPC_HOUSES:
		var house_id := StringName("npc_house_%d" % i)
		var npc_house: Vector2i = _building_at(data, house_id)
		assert_that(npc_house).is_not_equal(Vector2i(-1, -1))
		var npc_b: BuildingPlacement = _building(data, house_id)
		assert_that(npc_b.footprint).is_equal(Vector2i(3, 3))
		assert_that(npc_b.resident_id).is_not_equal(&"")
		assert_bool(resident_ids.has(npc_b.resident_id)).is_true()
		var sign_cell := Vector2i(npc_house.x + 1, npc_house.y + 1)
		assert_int(sign_cell.x % 16).is_greater(0)
		assert_int(sign_cell.x % 16).is_less(15)
		assert_int(sign_cell.y % 16).is_greater(0)
		assert_int(sign_cell.y % 16).is_less(15)
		for dz: int in range(-1, 2):
			for dx: int in range(-1, 2):
				assert_bool(_tree_at(data, sign_cell + Vector2i(dx, dz))).is_false()
	var spawn: Vector2i = data.player_spawn().cell
	assert_bool(data.is_in_bounds(spawn)).is_true()
	assert_that(data.terrain_at(spawn)).is_not_equal(WorldGrid.Terrain.WATER)
	assert_that(data.terrain_at(spawn)).is_not_equal(WorldGrid.Terrain.CLIFF)
	assert_int(data.acre_visuals.size()).is_equal(70)
	var house_visual: String = data.acre_visuals[2 * 7 + 3]
	if not FieldCatalog.mesh_paths(&"grd_s_f_mh_1").is_empty():
		assert_str(house_visual).starts_with("grd_s_f_mh_")
	for bz: int in range(1, 7):
		for bx: int in range(1, 6):
			var visual: String = data.acre_visuals[bz * 7 + bx]
			if visual.is_empty():
				continue
			assert_str(visual).starts_with("grd_")
			if FieldCatalog.has_acre_collision(StringName(visual)):
				var n_max := 0
				for uz: int in 16:
					for ux: int in 16:
						if int(FieldCatalog.unit_at(StringName(visual), ux, uz)["c"]) >= FieldCatalog.HEIGHT_MAX:
							n_max += 1
				assert_int(n_max).is_less_equal(128)
	if not FieldCatalog.mesh_paths(&"grd_s_e2_1").is_empty():
		for bz: int in range(1, 7):
			assert_str(data.acre_visuals[bz * 7 + 0]).starts_with("grd_s_e")
			assert_str(data.acre_visuals[bz * 7 + 6]).starts_with("grd_s_e")
		assert_str(data.acre_visuals[0 * 7 + 1]).starts_with("grd_s_e1")
		assert_str(data.acre_visuals[0 * 7 + 0]).is_equal("grd_s_e4_1")
		assert_str(data.acre_visuals[0 * 7 + 6]).is_equal("grd_s_e5_1")
	if not FieldCatalog.mesh_paths(&"grd_s_o_1").is_empty():
		## Beach row → exceptional sea under it (`m` → `o`).
		for bx: int in range(0, 7):
			var beach: String = data.acre_visuals[6 * 7 + bx]
			var sea: String = data.acre_visuals[7 * 7 + bx]
			assert_str(sea).is_equal(String(FieldCatalog.ocean_visual_for_beach(StringName(beach))))
			assert_str(sea).contains("_o_")


func test_fg_templates_place_authored_trees() -> void:
	## Disc FG catalog: denser authored layouts + border strip (`mSDI_PullTree`).
	if not FgCatalog.has_catalog():
		return
	var data: WorldData = WorldGenerator.generate(12345)
	assert_int(_kind_count(data, &"tree")).is_greater(40)
	var apple := 0
	var cedar := 0
	var hardwood := 0
	for o: ObjectPlacement in data.objects:
		if o == null or o.kind != &"tree":
			continue
		match o.visual_id:
			&"TREE_APPLE_FRUIT":
				apple += 1
			&"CEDAR_TREE":
				cedar += 1
			&"TREE":
				hardwood += 1
	assert_int(apple).is_greater(0)
	assert_int(cedar).is_greater(0)
	assert_int(hardwood).is_greater(0)
	for bz: int in range(0, 6):
		for uz: int in 16:
			assert_bool(_tree_at(data, Vector2i(0, bz * 16 + uz))).is_false()
			assert_bool(_tree_at(data, Vector2i(79, bz * 16 + uz))).is_false()


func test_generated_town_places_waterfall_when_mesh_exists() -> void:
	if FieldCatalog.mesh_paths(&"obj_fallS").is_empty():
		return
	for seed: int in [12345, 1786784979, 42, 99999]:
		var data: WorldData = WorldGenerator.generate(seed)
		var wf_acres := 0
		for bz: int in range(1, 7):
			for bx: int in range(1, 6):
				var type: int = int(data.acre_types[bz * TownFieldGenerator.BLOCK_X + bx])
				if TownFieldGenerator.is_waterfall_block(type):
					wf_acres += 1
		assert_int(wf_acres).is_greater(0)
		assert_int(_kind_count(data, &"waterfall")).is_equal(wf_acres)
		for o: ObjectPlacement in data.objects:
			if o == null or o.kind != &"waterfall":
				continue
			assert_bool(
				o.visual_id == &"obj_fallS" or o.visual_id == &"obj_fallSE"
			).is_true()
			assert_bool(o.occupy_grid).is_false()
			var bx: int = int(o.cell.x / 16) + 1
			var bz: int = int(o.cell.y / 16) + 1
			var type: int = int(data.acre_types[bz * TownFieldGenerator.BLOCK_X + bx])
			assert_bool(TownFieldGenerator.is_waterfall_block(type)).is_true()
			## Disc templates pin the actor to the cliff sheet — never the old river
			## corridor midpoint (ux 7, uz 8) that floated mid-acre.
			var ut := Vector2i(o.cell.x % 16, o.cell.y % 16)
			assert_bool(ut != Vector2i(7, 8)).is_true()


func test_height_steps_only_on_terrace_faces() -> void:
	## Vertical / bottom-corner river-cliffs must not bump the column (`mRF_GetBlockBase`).
	assert_bool(TownFieldGenerator.raises_height(TownFieldGenerator.T_CLIFF_H)).is_true()
	assert_bool(TownFieldGenerator.raises_height(TownFieldGenerator.T_WF_H)).is_true()
	assert_bool(TownFieldGenerator.raises_height(TownFieldGenerator.T_CLIFF_TR)).is_true()
	assert_bool(TownFieldGenerator.raises_height(TownFieldGenerator.T_WF_TL)).is_true()
	assert_bool(TownFieldGenerator.raises_height(TownFieldGenerator.T_BORDER_CLIFF_LEFT_TRANSITION)).is_true()
	assert_bool(TownFieldGenerator.raises_height(TownFieldGenerator.T_CLIFF_VR)).is_false()
	assert_bool(TownFieldGenerator.raises_height(TownFieldGenerator.T_RIV_CLIFF_VR)).is_false()
	assert_bool(TownFieldGenerator.raises_height(TownFieldGenerator.T_RIV_CLIFF_BL)).is_false()
	assert_bool(TownFieldGenerator.raises_height(TownFieldGenerator.T_WF_BR)).is_false()
	assert_bool(TownFieldGenerator.raises_height(TownFieldGenerator.T_RIVER_S)).is_false()
	assert_int(TownFieldGenerator.T_RIVER_S + TownFieldGenerator.RIVER_BRIDGE_DELTA).is_equal(
		TownFieldGenerator.T_RIVER_S_BRIDGE
	)


func test_each_cliff_band_gets_slopes() -> void:
	## `mRF_SetSlopeBlock` places a slope on each river side of every cliff band
	## (each west `LEFT_TRANSITION`). One pair for the whole town trapped the
	## player above a 2-step drop to the beach.
	for seed: int in [12345, 1786784979, 42, 99999]:
		var data: WorldData = WorldGenerator.generate(seed)
		var bands := 0
		var slopes := 0
		for bz: int in range(TownFieldGenerator.BLOCK_Z - 2):
			if int(data.acre_types[bz * TownFieldGenerator.BLOCK_X]) == (
				TownFieldGenerator.T_BORDER_CLIFF_LEFT_TRANSITION
			):
				bands += 1
		for i: int in data.acre_types.size():
			if TownFieldGenerator.is_slope(int(data.acre_types[i])):
				slopes += 1
		assert_int(bands).is_greater(0)
		assert_int(slopes).is_greater_equal(bands)
	var trapped: WorldData = WorldGenerator.generate(1786784979)
	var lower_slope := false
	for bz: int in range(4, 7):
		for bx: int in range(1, 6):
			var t: int = int(trapped.acre_types[bz * TownFieldGenerator.BLOCK_X + bx])
			if TownFieldGenerator.is_slope(t):
				lower_slope = true
	assert_bool(lower_slope).is_true()


func test_generated_town_map_text_shows_acres() -> void:
	## Console dump: 7×10 block grid, A–F playable, A-3 station / B-3 house.
	var data: WorldData = WorldGenerator.generate(12345)
	var text: String = WorldGenerator.map_text(data)
	assert_str(text).contains("seed=12345")
	assert_str(text).contains("STAT")
	assert_str(text).contains("HOME")
	assert_str(text).contains(" B  ")
	assert_str(text).contains("A-3")
	assert_str(text).contains("player_house")


func test_generated_town_has_river_bridge() -> void:
	## `mRF_SetBridgeBlock` / sea-mouth fallback always leaves at least one `*_BRIDGE` acre.
	var data: WorldData = WorldGenerator.generate(12345)
	var n := 0
	var vis := ""
	for i: int in data.acre_types.size():
		if TownFieldGenerator.is_river_bridge(int(data.acre_types[i])):
			n += 1
			vis = String(data.acre_visuals[i])
	assert_int(n).is_greater(0)
	assert_str(vis).contains("_b_")


func test_generated_towns_include_stone_bridge_combis() -> void:
	## `mRF_SelectBlock` rolls a `data_combi` row of the bridge type. `_b_1` (and
	## some `_b_3`) are stone. Empty visuals used to paint every deck as wood PATH.
	var saw_stone := false
	var saw_wood := false
	for seed: int in 24:
		var data: WorldData = WorldGenerator.generate(2000 + seed)
		for i: int in data.acre_types.size():
			if not TownFieldGenerator.is_river_bridge(int(data.acre_types[i])):
				continue
			var vis := StringName(data.acre_visuals[i])
			assert_str(String(vis)).contains("_b_")
			if FieldCatalog.is_stone_bridge_visual(vis):
				saw_stone = true
			else:
				saw_wood = true
	assert_bool(saw_stone).is_true()
	assert_bool(saw_wood).is_true()


func test_stone_bridge_deck_is_stone_terrain() -> void:
	## Geometric decks and catalog attrs 32–35 both use `Terrain.STONE`, not brown PATH.
	var found := false
	for seed: int in 40:
		var data: WorldData = WorldGenerator.generate(3000 + seed)
		for i: int in data.acre_types.size():
			if not TownFieldGenerator.is_river_bridge(int(data.acre_types[i])):
				continue
			var vis := StringName(data.acre_visuals[i])
			if not FieldCatalog.is_stone_bridge_visual(vis):
				continue
			var bz: int = i / TownFieldGenerator.BLOCK_X
			var bx: int = i % TownFieldGenerator.BLOCK_X
			if bx < 1 or bx > 5 or bz < 1 or bz > 6:
				continue
			var origin := Vector2i((bx - 1) * 16, (bz - 1) * 16)
			var n_stone := 0
			for uz: int in 16:
				for ux: int in 16:
					if data.terrain_at(origin + Vector2i(ux, uz)) == WorldGrid.Terrain.STONE:
						n_stone += 1
			assert_int(n_stone).is_greater(0)
			found = true
			break
		if found:
			break
	assert_bool(found).is_true()


func test_town_field_generator_is_deterministic() -> void:
	var a: Dictionary = TownFieldGenerator.new().generate(42)
	var b: Dictionary = TownFieldGenerator.new().generate(42)
	assert_that(a["blocks"]).is_equal(b["blocks"])
	assert_that(a["heights"]).is_equal(b["heights"])


func test_configure_from_world_copies_terrain() -> void:
	var data: WorldData = WorldGenerator.authored_test_town()
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	assert_int(grid.columns).is_equal(16)
	assert_that(grid.terrain_at(Vector2i(12, 3))).is_equal(WorldGrid.Terrain.WATER)
	assert_that(grid.world_to_cell(Vector3(0, 0, 6))).is_equal(Vector2i(8, 11))


func test_builder_instances_test_town_scenes() -> void:
	var world: Node3D = _shell()
	auto_free(world)
	add_child(world)
	var data: WorldData = WorldGenerator.authored_test_town()
	var grid := WorldGrid.new()
	WorldBuilder.new().build(world, data, grid)
	assert_that(world.get_node_or_null("Buildings/player_house")).is_not_null()
	var player_house: Node3D = world.get_node("Buildings/player_house") as Node3D
	var house_stand: Vector2i = grid.world_to_cell(player_house.position)
	assert_float(player_house.position.y).is_equal_approx(FieldCollision.ground_y(data, house_stand), 0.001)
	assert_float(player_house.position.y).is_less(FieldCollision.height_at(data, house_stand) - 2.0)
	assert_that(world.get_node_or_null("Buildings/acre_shop")).is_not_null()
	assert_that(world.get_node_or_null("Buildings/npc_house_0")).is_not_null()
	assert_that(world.get_node_or_null("Buildings/npc_house_0").get("occupant_id")).is_equal(&"filbert")
	assert_that(world.get_node_or_null("Objects/acre_sign")).is_not_null()
	assert_that(world.get_node_or_null("Objects/yard_chair")).is_not_null()
	assert_that(world.get_node_or_null("Objects/tree_1")).is_not_null()
	assert_that(world.get_node_or_null("Objects/ground_apple")).is_not_null()
	assert_that(world.get_node_or_null("Characters/filbert")).is_not_null()
	assert_that(world.get_node_or_null("Characters/PlayerSpawn")).is_not_null()
	assert_that(world.get_node_or_null("Terrain/MapBound")).is_not_null()
	var spawn_marker: Marker3D = world.get_node("Characters/PlayerSpawn") as Marker3D
	var spawn_cell: Vector2i = data.player_spawn().cell
	var on_ground: Vector3 = grid.cell_to_world(spawn_cell)
	on_ground.y = FieldCollision.ground_y(data, spawn_cell)
	assert_that(spawn_marker.position).is_equal(on_ground)
	assert_that(world.get_node_or_null("Objects/pansy_1")).is_not_null()
	assert_that(world.get_node_or_null("Objects/rock_1")).is_not_null()
	assert_that(world.get_node_or_null("Objects/house_door")).is_not_null()
	assert_that(grid.occupant_at(Vector2i(7, 1))).is_equal(&"player_house")
	assert_that(grid.occupant_at(Vector2i(4, 6))).is_equal(&"tree_1")


func test_builder_places_generated_acre_meshes() -> void:
	if FieldCatalog.mesh_paths(&"grd_s_f_1").is_empty():
		return
	var world: Node3D = _shell()
	auto_free(world)
	add_child(world)
	var data: WorldData = WorldGenerator.generate(12345)
	var grid := WorldGrid.new()
	WorldBuilder.new().build(world, data, grid)
	var acres: Node = world.get_node_or_null("Terrain/Acres")
	assert_that(acres).is_not_null()
	assert_int(acres.get_child_count()).is_greater(20)
	var left_border: Node = acres.get_node_or_null("acre_0_2")
	var right_border: Node = acres.get_node_or_null("acre_6_2")
	if not FieldCatalog.mesh_paths(&"grd_s_e2_1").is_empty():
		assert_that(left_border).is_not_null()
		assert_that(right_border).is_not_null()
		assert_str(String(left_border.get_meta("visual_id"))).starts_with("grd_s_e")
		assert_str(String(right_border.get_meta("visual_id"))).starts_with("grd_s_e")
		var left_pos: Vector3 = (left_border as Node3D).position
		var right_pos: Vector3 = (right_border as Node3D).position
		assert_float(right_pos.x - left_pos.x).is_equal_approx(FieldCatalog.ACRE_METERS * 6.0, 0.01)
		var north: Node = acres.get_node_or_null("acre_3_0")
		assert_that(north).is_not_null()
		assert_str(String(north.get_meta("visual_id"))).starts_with("grd_s_e1")
	if not FieldCatalog.mesh_paths(&"grd_s_o_1").is_empty():
		var south: Node = acres.get_node_or_null("acre_3_7")
		assert_that(south).is_not_null()
		assert_str(String(south.get_meta("visual_id"))).contains("_o_")
	var house_acre: Node = acres.get_node_or_null("acre_3_2")
	assert_that(house_acre).is_not_null()
	assert_that(house_acre.get_node_or_null("GeneratedVisual")).is_not_null()
	assert_that(world.get_node_or_null("Buildings/player_house")).is_not_null()
	assert_that(world.get_node_or_null("Buildings/player_house_1")).is_not_null()
	assert_that(world.get_node_or_null("Buildings/player_house_2")).is_not_null()
	assert_that(world.get_node_or_null("Buildings/player_house_3")).is_not_null()
	assert_that(world.get_node_or_null("Buildings/npc_house_0")).is_not_null()
	var spawned := 0
	for child: Node in world.get_node("Characters").get_children():
		if child is Villager:
			spawned += 1
	assert_int(spawned).is_equal(WorldGenerator.STARTER_NPC_HOUSES)
	var a11: Node3D = acres.get_node_or_null("acre_1_1") as Node3D
	assert_that(a11).is_not_null()
	var expected := grid.cell_corner(Vector2i(0, 0))
	expected.y += float(data.acre_heights[1 * 7 + 1]) * FieldCatalog.ACRE_STEP_METERS
	assert_that(a11.position).is_equal(expected)
	assert_that(world.get_node_or_null("Terrain/Heightfield")).is_null()
	assert_that(world.get_node_or_null("Terrain/WalkFloor")).is_null()
	var spawn_marker: Marker3D = world.get_node("Characters/PlayerSpawn") as Marker3D
	var spawn_cell: Vector2i = data.player_spawn().cell
	assert_float(spawn_marker.position.y).is_equal_approx(FieldCollision.ground_y(data, spawn_cell), 0.001)
	var xz: Vector3 = grid.cell_to_world(spawn_cell)
	assert_float(spawn_marker.position.x).is_equal_approx(xz.x, 0.001)
	assert_float(spawn_marker.position.z).is_equal_approx(xz.z, 0.001)
	var a21: Node3D = acres.get_node_or_null("acre_2_1") as Node3D
	if a21 != null:
		assert_float(a21.position.x - a11.position.x).is_equal_approx(FieldCatalog.ACRE_METERS, 0.01)
		assert_float(a21.position.z).is_equal_approx(a11.position.z, 0.01)


func test_fg_standin_skips_water_and_clears_tanuki_path() -> void:
	var data: WorldData = WorldGenerator.generate(12345)
	for o: ObjectPlacement in data.objects:
		if o == null or o.kind != &"tree":
			continue
		assert_that(data.terrain_at(o.cell)).is_not_equal(WorldGrid.Terrain.WATER)
		assert_that(data.terrain_at(o.cell)).is_not_equal(WorldGrid.Terrain.CLIFF)
	var path_origin: Vector2i = Vector2i(32, 32)
	for uz: int in range(0, 3):
		for ux: int in [7, 8]:
			var cell := path_origin + Vector2i(ux, uz)
			for o: ObjectPlacement in data.objects:
				if o != null and o.kind == &"tree":
					assert_that(o.cell).is_not_equal(cell)


func test_builder_skips_removed_pickup() -> void:
	Game.mark_interactable_removed(&"ground_apple")
	var world: Node3D = _shell()
	auto_free(world)
	add_child(world)
	WorldBuilder.new().build(world, WorldGenerator.authored_test_town(), WorldGrid.new())
	assert_that(world.get_node_or_null("Objects/ground_apple")).is_null()
	assert_that(world.get_node_or_null("Objects/acre_sign")).is_not_null()


func test_game_resolve_respects_mode() -> void:
	Game.world_mode = WorldData.Mode.TEST
	assert_that(Game.resolve_world_data().mode).is_equal(WorldData.Mode.TEST)
	Game.world_mode = WorldData.Mode.GENERATED
	Game.world_seed = 12345
	var generated: WorldData = Game.resolve_world_data()
	assert_that(generated.mode).is_equal(WorldData.Mode.GENERATED)
	assert_str(generated.fingerprint()).is_equal(WorldGenerator.generate(12345).fingerprint())


func _shell() -> Node3D:
	var world := Node3D.new()
	world.name = "World"
	for n: String in ["Terrain", "Objects", "Buildings", "Characters"]:
		var child := Node3D.new()
		child.name = n
		world.add_child(child)
	return world


func _building_at(data: WorldData, id: StringName) -> Vector2i:
	var b: BuildingPlacement = _building(data, id)
	return b.cell if b != null else Vector2i(-1, -1)


func _building(data: WorldData, id: StringName) -> BuildingPlacement:
	for b: BuildingPlacement in data.buildings:
		if b != null and b.id == id:
			return b
	return null


func _building_label(data: WorldData, id: StringName) -> String:
	for b: BuildingPlacement in data.buildings:
		if b != null and b.id == id:
			return b.label
	return ""


func _building_visual(data: WorldData, id: StringName) -> StringName:
	for b: BuildingPlacement in data.buildings:
		if b != null and b.id == id:
			return b.visual_id
	return &""


func _building_mesh_facing(data: WorldData, id: StringName) -> WorldGrid.Facing:
	for b: BuildingPlacement in data.buildings:
		if b != null and b.id == id:
			return b.mesh_facing
	return WorldGrid.Facing.SOUTH


func test_world_object_registry_lists_phase_kinds() -> void:
	## Adding a kind is one registry line + a scene; builder does not hardcode types.
	WorldObjectRegistry.ensure()
	for kind: StringName in [
		&"tree", &"rock", &"flower", &"hole", &"item", &"door", &"building", &"house", &"shop", &"waterfall"
	]:
		assert_bool(WorldObjectRegistry.has_kind(kind)).is_true()
		assert_str(WorldObjectRegistry.scene_path(kind)).is_not_empty()
	var builder_src := FileAccess.get_file_as_string("res://scripts/systems/world_builder.gd")
	assert_str(builder_src).contains("WorldObjectRegistry")
	assert_bool("res://scenes/world/tree.tscn" in builder_src).is_false()
	assert_bool("res://scenes/world/building.tscn" in builder_src).is_false()


func _object_at(data: WorldData, id: StringName) -> Vector2i:
	for o: ObjectPlacement in data.objects:
		if o != null and o.id == id:
			return o.cell
	return Vector2i(-1, -1)


func _object_visual(data: WorldData, id: StringName) -> StringName:
	for o: ObjectPlacement in data.objects:
		if o != null and o.id == id:
			return o.visual_id
	return &""


func _kind_count(data: WorldData, kind: StringName) -> int:
	var n: int = 0
	for o: ObjectPlacement in data.objects:
		if o != null and o.kind == kind:
			n += 1
	return n


func _object_by_kind(data: WorldData, kind: StringName) -> ObjectPlacement:
	for o: ObjectPlacement in data.objects:
		if o != null and o.kind == kind:
			return o
	return null


func _npc_house_count(data: WorldData) -> int:
	var n: int = 0
	for b: BuildingPlacement in data.buildings:
		if b != null and String(b.id).begins_with("npc_house_"):
			n += 1
	return n


func _tree_at(data: WorldData, cell: Vector2i) -> bool:
	for o: ObjectPlacement in data.objects:
		if o != null and o.kind == &"tree" and o.cell == cell:
			return true
	return false


func _has_terrain(data: WorldData, value: WorldGrid.Terrain) -> bool:
	for x: int in data.columns:
		for z: int in data.rows:
			if data.terrain_at(Vector2i(x, z)) == value:
				return true
	return false


func _has_elevation(data: WorldData) -> bool:
	for x: int in data.columns:
		for z: int in data.rows:
			if data.elevation_at(Vector2i(x, z)) > 0:
				return true
	return false


func _uses_acre_collision(data: WorldData) -> bool:
	for visual: String in data.acre_visuals:
		if FieldCatalog.has_acre_collision(StringName(visual)):
			return true
	return false
