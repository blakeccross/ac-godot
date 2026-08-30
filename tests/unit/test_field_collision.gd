class_name TestFieldCollision
extends GdUnitTestSuite

## Unit heightfield analog of `mCoBG` (terraces + slate ramps), not `grd_*` triangles.


func before_test() -> void:
	FieldCollision.clear_caches()


func after_test() -> void:
	FieldCollision.clear_caches()


func test_horizontal_cliff_is_high_north() -> void:
	assert_float(FieldCollision.unit_rel_at(0, false, 8.0, 2.0)).is_equal(1.0)
	assert_float(FieldCollision.unit_rel_at(0, false, 8.0, 14.0)).is_equal(0.0)
	assert_float(FieldCollision.unit_rel_at(0, false, 8.0, 11.0)).is_equal(FieldCollision.FACE_HOLE)


func test_vertical_cliffs_are_high_on_inside() -> void:
	assert_float(FieldCollision.unit_rel_at(2, false, 2.0, 8.0)).is_equal(1.0)
	assert_float(FieldCollision.unit_rel_at(2, false, 14.0, 8.0)).is_equal(0.0)
	assert_float(FieldCollision.unit_rel_at(2, false, 9.0, 8.0)).is_equal(FieldCollision.FACE_HOLE)
	assert_float(FieldCollision.unit_rel_at(2, false, 11.5, 8.0)).is_equal(0.0)
	assert_float(FieldCollision.unit_rel_at(5, false, 14.0, 8.0)).is_equal(1.0)
	assert_float(FieldCollision.unit_rel_at(5, false, 2.0, 8.0)).is_equal(0.0)


func test_slope_interpolates_instead_of_wall() -> void:
	var mid: float = FieldCollision.unit_rel_at(0, true, 8.0, 9.0)
	assert_float(mid).is_greater(0.0)
	assert_float(mid).is_less(1.0)
	assert_float(FieldCollision.unit_rel_at(0, true, 8.0, 2.0)).is_equal(1.0)
	assert_float(FieldCollision.unit_rel_at(0, true, 8.0, 14.0)).is_equal(0.0)


func test_corner_shapes() -> void:
	assert_float(FieldCollision.unit_rel_at(1, false, 2.0, 2.0)).is_equal(1.0)
	assert_float(FieldCollision.unit_rel_at(1, false, 14.0, 14.0)).is_equal(0.0)
	assert_float(FieldCollision.unit_rel_at(6, false, 14.0, 2.0)).is_equal(1.0)
	assert_float(FieldCollision.unit_rel_at(6, false, 2.0, 14.0)).is_equal(0.0)
	assert_float(FieldCollision.unit_rel_at(3, false, 2.0, 2.0)).is_equal(1.0)
	assert_float(FieldCollision.unit_rel_at(3, false, 14.0, 14.0)).is_equal(0.0)


func test_cliff_shape_maps_block_types() -> void:
	assert_int(TownFieldGenerator.cliff_shape(TownFieldGenerator.T_CLIFF_H)).is_equal(0)
	assert_int(TownFieldGenerator.cliff_shape(TownFieldGenerator.T_CLIFF_VR)).is_equal(2)
	assert_int(TownFieldGenerator.cliff_shape(TownFieldGenerator.T_SLOPE_H + 2)).is_equal(2)
	assert_int(TownFieldGenerator.cliff_shape(TownFieldGenerator.T_WF_H)).is_equal(0)
	assert_int(TownFieldGenerator.cliff_shape(TownFieldGenerator.T_FLAT)).is_equal(-1)


func test_height_at_uses_terraces_and_holes() -> void:
	var data: WorldData = WorldGenerator.generate(12345)
	var checked := false
	for bz: int in range(1, 7):
		for bx: int in range(1, 6):
			var type: int = int(data.acre_types[bz * 7 + bx])
			var shape: int = TownFieldGenerator.cliff_shape(type)
			if shape < 0:
				continue
			var origin := Vector2i((bx - 1) * 16, (bz - 1) * 16)
			var slope: bool = TownFieldGenerator.is_slope(type)
			var visual := StringName(data.acre_visuals[bz * 7 + bx])
			var catalog: bool = FieldCatalog.has_acre_collision(visual)
			if shape == 0:
				var north: Vector2i = origin + Vector2i(8, 2)
				var south: Vector2i = origin + Vector2i(8, 14)
				var hn: float = FieldCollision.height_at(data, north)
				var hs: float = FieldCollision.height_at(data, south)
				if FieldCollision.has_floor(hn) and FieldCollision.has_floor(hs) and hn != hs:
					assert_float(hn).is_greater(hs)
					checked = true
				if slope:
					var ramp: Vector2i = origin + Vector2i(8, 9)
					if data.terrain_at(ramp) != WorldGrid.Terrain.WATER:
						assert_that(data.terrain_at(ramp)).is_equal(WorldGrid.Terrain.PATH)
						var hr: float = FieldCollision.height_at(data, ramp)
						if FieldCollision.has_floor(hn) and FieldCollision.has_floor(hs):
							assert_float(hr).is_greater(hs)
							assert_float(hr).is_less(hn)
						checked = true
				elif not catalog:
					var face: Vector2i = origin + Vector2i(8, 11)
					if data.terrain_at(face) != WorldGrid.Terrain.WATER:
						assert_that(data.terrain_at(face)).is_equal(WorldGrid.Terrain.CLIFF)
						assert_float(FieldCollision.height_at(data, face)).is_equal(FieldCollision.NO_FLOOR)
						checked = true
				else:
					## Face units stay walkable; the wall sits on the height jump (`mCoBG` edges).
					var face: Vector2i = origin + Vector2i(8, 11)
					if data.terrain_at(face) != WorldGrid.Terrain.WATER:
						assert_that(data.terrain_at(face)).is_not_equal(WorldGrid.Terrain.CLIFF)
						checked = true
			elif shape == 2:
				var west_h: float = FieldCollision.height_at(data, origin + Vector2i(2, 8))
				var east_h: float = FieldCollision.height_at(data, origin + Vector2i(14, 8))
				if FieldCollision.has_floor(west_h) and FieldCollision.has_floor(east_h) and west_h != east_h:
					assert_float(west_h).is_greater(east_h)
					checked = true
			elif shape == 5:
				var east_h: float = FieldCollision.height_at(data, origin + Vector2i(14, 8))
				var west_h: float = FieldCollision.height_at(data, origin + Vector2i(2, 8))
				if FieldCollision.has_floor(west_h) and FieldCollision.has_floor(east_h) and west_h != east_h:
					assert_float(east_h).is_greater(west_h)
					checked = true
	assert_bool(checked).is_true()


func test_water_has_no_floor() -> void:
	var data: WorldData = WorldGenerator.authored_test_town()
	assert_float(FieldCollision.height_at(data, Vector2i(12, 3))).is_equal(FieldCollision.NO_FLOOR)
	assert_float(FieldCollision.height_at(data, Vector2i(8, 11))).is_equal(0.0)
	assert_float(FieldCollision.ground_y(data, Vector2i(8, 11))).is_equal(0.0)
	assert_float(FieldCollision.ground_y(data, Vector2i(12, 3))).is_equal(0.0)
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var water_pos: Vector3 = grid.cell_to_world(Vector2i(12, 3))
	assert_float(FieldCollision.ground_y_at(data, grid, water_pos)).is_equal(FieldCollision.NO_FLOOR)
	assert_float(FieldCollision.ground_y_at(data, grid, grid.cell_to_world(Vector2i(8, 11)))).is_equal(0.0)


func test_ramp_height_follows_position() -> void:
	var data: WorldData = WorldGenerator.generate(12345)
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var found := false
	for bz: int in range(1, 7):
		for bx: int in range(1, 6):
			var type: int = int(data.acre_types[bz * 7 + bx])
			if not TownFieldGenerator.is_slope(type):
				continue
			var origin := Vector2i((bx - 1) * 16, (bz - 1) * 16)
			for uz: int in 16:
				for ux: int in 16:
					var cell := Vector2i(origin.x + ux, origin.y + uz)
					if data.terrain_at(cell) != WorldGrid.Terrain.PATH:
						continue
					var c0: Vector3 = grid.cell_corner(cell)
					var y_n: float = FieldCollision.ground_y_at(data, grid, c0 + Vector3(1.0, 0.0, 0.05))
					var y_s: float = FieldCollision.ground_y_at(data, grid, c0 + Vector3(1.0, 0.0, 1.95))
					var y_w: float = FieldCollision.ground_y_at(data, grid, c0 + Vector3(0.05, 0.0, 1.0))
					var y_e: float = FieldCollision.ground_y_at(data, grid, c0 + Vector3(1.95, 0.0, 1.0))
					if (
						not FieldCollision.has_floor(y_n)
						or not FieldCollision.has_floor(y_s)
						or not FieldCollision.has_floor(y_w)
						or not FieldCollision.has_floor(y_e)
					):
						continue
					if absf(y_n - y_s) > 0.15 or absf(y_w - y_e) > 0.15:
						found = true
						break
				if found:
					break
			if found:
				break
		if found:
			break
	assert_bool(found).is_true()


func test_catalog_cliff_keeps_face_walkable() -> void:
	if not FieldCatalog.has_acre_collision(&"grd_s_c1_1"):
		return
	var high: Dictionary = FieldCatalog.unit_at(&"grd_s_c1_1", 8, 2)
	var low: Dictionary = FieldCatalog.unit_at(&"grd_s_c1_1", 8, 14)
	assert_int(int(high["c"])).is_equal(16)
	assert_int(int(low["c"])).is_equal(4)
	assert_int(int(FieldCatalog.unit_at(&"grd_s_c1_1", 8, 11)["c"])).is_equal(16)


func test_slate_face_keeps_high_side_flat() -> void:
	## Bilinear across SE=4 / NW=16 drops Y into the cliff mesh. Slate uses flat side heights.
	if not FieldCatalog.has_acre_collision(&"grd_s_c1_1"):
		return
	var data := WorldData.new()
	data.columns = 16
	data.rows = 16
	data.cell_size = 2.0
	data.acre_visual = &"grd_s_c1_1"
	data.bake()
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var slate := Vector2i(8, 12)
	var unit: Dictionary = FieldCatalog.unit_at(&"grd_s_c1_1", slate.x, slate.y)
	assert_int(int(unit["s"])).is_equal(1)
	assert_int(int(unit["se"])).is_less(int(unit["nw"]))
	var c0: Vector3 = grid.cell_corner(slate)
	var cs: float = grid.cell_size
	## NW of the SW–NE diagonal (high side).
	var high_pos := Vector3(c0.x + cs * 0.25, 0.0, c0.z + cs * 0.25)
	var high_y: float = FieldCollision.ground_y_at(data, grid, high_pos)
	var expect_high: float = FieldCatalog.counts_to_y(int(unit["nw"]), 0)
	assert_float(high_y).is_equal_approx(expect_high, 0.001)
	## SE of the diagonal (low side).
	var low_pos := Vector3(c0.x + cs * 0.75, 0.0, c0.z + cs * 0.75)
	var low_y: float = FieldCollision.ground_y_at(data, grid, low_pos)
	var expect_low: float = FieldCatalog.counts_to_y(int(unit["se"]), 0)
	assert_float(low_y).is_equal_approx(expect_low, 0.001)


func test_actor_radius_matches_original_bgcheck() -> void:
	assert_float(FieldCollision.ACTOR_RADIUS).is_equal_approx(0.9, 0.001)


func test_revise_xz_rejects_authored_pond() -> void:
	## Circle vs bank: do not enter a hole. Authored pond is not catalog water.
	var data: WorldData = WorldGenerator.authored_test_town()
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var land_cell := Vector2i(11, 3)
	var water_cell := Vector2i(12, 3)
	var land: Vector3 = grid.cell_to_world(land_cell)
	land.y = FieldCollision.ground_y_at(data, grid, land)
	var water: Vector3 = grid.cell_to_world(water_cell)
	water.y = land.y
	var revised: Vector3 = FieldCollision.revise_xz(data, grid, land, water)
	assert_that(grid.world_to_cell(revised)).is_equal(land_cell)
	assert_that(data.terrain_at(grid.world_to_cell(revised))).is_not_equal(WorldGrid.Terrain.WATER)
	assert_float(revised.y).is_equal(land.y)


func test_catalog_water_is_heightfield_not_pit() -> void:
	## Original `GetBgY` interpolates water corners; gravity never runs over a river.
	var data: WorldData = WorldGenerator.generate(12345)
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var found := false
	var blocked := false
	for z: int in data.rows:
		for x: int in data.columns:
			var cell := Vector2i(x, z)
			if data.terrain_at(cell) != WorldGrid.Terrain.WATER:
				continue
			var pos: Vector3 = grid.cell_to_world(cell)
			var y: float = FieldCollision.ground_y_at(data, grid, pos)
			if not FieldCollision.has_floor(y):
				continue
			assert_that(FieldCollision.has_floor(y)).is_true()
			found = true
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var land_cell: Vector2i = cell + d
				if not data.is_in_bounds(land_cell):
					continue
				if data.terrain_at(land_cell) == WorldGrid.Terrain.WATER:
					continue
				var from: Vector3 = grid.cell_to_world(land_cell)
				from.y = FieldCollision.ground_y_at(data, grid, from)
				if not FieldCollision.has_floor(from.y):
					continue
				var revised: Vector3 = FieldCollision.revise_xz(data, grid, from, pos)
				assert_that(data.terrain_at(grid.world_to_cell(revised))).is_not_equal(
					WorldGrid.Terrain.WATER
				)
				assert_that(grid.world_to_cell(revised)).is_equal(land_cell)
				blocked = true
				break
			if blocked:
				break
		if blocked:
			break
	if not FieldCatalog.has_acre_collision(&"grd_s_r1_1") and not found:
		return
	assert_bool(found).is_true()
	assert_bool(blocked).is_true()


func test_revise_xz_rejects_cliff_edge() -> void:
	var data: WorldData = WorldGenerator.generate(12345)
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var found := false
	for z: int in data.rows:
		for x: int in data.columns:
			var a := Vector2i(x, z)
			var ha: float = FieldCollision.height_at(data, a)
			if not FieldCollision.has_floor(ha):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var b: Vector2i = a + d
				if not data.is_in_bounds(b):
					continue
				var hb: float = FieldCollision.height_at(data, b)
				if not FieldCollision.has_floor(hb):
					continue
				if absf(ha - hb) < 2.0:
					continue
				var from: Vector3 = grid.cell_to_world(a)
				from.y = ha
				var to: Vector3 = grid.cell_to_world(b)
				to.y = hb
				var revised: Vector3 = FieldCollision.revise_xz(data, grid, from, to)
				assert_that(grid.world_to_cell(revised)).is_equal(a)
				assert_float(Vector2(revised.x - to.x, revised.z - to.z).length()).is_greater(0.5)
				found = true
				break
			if found:
				break
		if found:
			break
	if not FieldCatalog.has_acre_collision(&"grd_s_c1_1") and not found:
		return
	assert_bool(found).is_true()


func test_revise_xz_slides_along_wall() -> void:
	## Diagonal move into a terrace: keep the tangent, do not restore both X and Z.
	var data: WorldData = WorldGenerator.generate(12345)
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var found := false
	for z: int in data.rows:
		for x: int in data.columns:
			var a := Vector2i(x, z)
			var unit: Dictionary = FieldCatalog.unit_at(
				_visual_at(data, a), posmod(a.x, WorldGenerator.UT), posmod(a.y, WorldGenerator.UT)
			)
			if not unit.is_empty() and int(unit["s"]) != 0:
				continue
			var ha: float = FieldCollision.height_at(data, a)
			if not FieldCollision.has_floor(ha):
				continue
			var b := Vector2i(a.x + 1, a.y)
			if not data.is_in_bounds(b):
				continue
			var hb: float = FieldCollision.height_at(data, b)
			if not FieldCollision.has_floor(hb) or absf(ha - hb) < 2.0:
				continue
			var south := Vector2i(a.x, a.y + 1)
			if data.is_in_bounds(south):
				var hs: float = FieldCollision.height_at(data, south)
				if FieldCollision.has_floor(hs) and absf(ha - hs) >= 2.0:
					continue
			var c0: Vector3 = grid.cell_corner(a)
			var cs: float = grid.cell_size
			## Stand 1.5 m west of the east wall so radius 0.9 m still allows travel + slide.
			var from := Vector3(c0.x + cs - 1.5, ha, c0.z + cs * 0.5)
			var to: Vector3 = from + Vector3(2.0, 0.0, 1.0)
			var revised: Vector3 = FieldCollision.revise_xz(data, grid, from, to)
			assert_float(absf(revised.z - from.z)).is_greater(0.5)
			assert_float(revised.x).is_less(c0.x + cs)
			found = true
			break
		if found:
			break
	if not FieldCatalog.has_acre_collision(&"grd_s_c1_1") and not found:
		return
	assert_bool(found).is_true()


func test_slate_corner_cardinal_is_half_edge() -> void:
	## SE-notch slate + low east neighbor: a full N–S wall would sit in front of the 45° face.
	## Keep only the north half so the south-east notch is reachable from the east.
	if not FieldCatalog.has_acre_collision(&"grd_s_c2_1"):
		return
	var data := WorldData.new()
	data.columns = 16
	data.rows = 16
	data.cell_size = 2.0
	data.acre_visual = &"grd_s_c2_1"
	data.bake()
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var slate := Vector2i(9, 8)
	var unit: Dictionary = FieldCatalog.unit_at(&"grd_s_c2_1", slate.x, slate.y)
	assert_bool(FieldCatalog.is_slate_unit(int(unit["s"]), int(unit["a"]))).is_true()
	assert_int(int(unit["se"])).is_less(int(unit["ne"]))
	var c0: Vector3 = grid.cell_corner(slate)
	var cs: float = grid.cell_size
	var east_x: float = c0.x + cs
	var from := Vector3(east_x + 1.0, 0.0, c0.z + cs * 0.85)
	from.y = FieldCollision.ground_y_at(data, grid, from)
	var to := Vector3(east_x - 0.8, from.y, from.z)
	var revised: Vector3 = FieldCollision.revise_xz(data, grid, from, to)
	assert_float(revised.x).is_less(east_x)


func test_walls_do_not_cover_walkable_cell_centers() -> void:
	## A circle at the unit center must stay put. Slate diagonals run through the center.
	if not FieldCatalog.has_acre_collision(&"grd_s_c1_1"):
		return
	var data: WorldData = WorldGenerator.generate(12345)
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var hit := 0
	for z: int in data.rows:
		for x: int in data.columns:
			var cell := Vector2i(x, z)
			if data.terrain_at(cell) == WorldGrid.Terrain.WATER:
				continue
			var unit: Dictionary = FieldCatalog.unit_at(
				_visual_at(data, cell),
				posmod(cell.x, WorldGenerator.UT),
				posmod(cell.y, WorldGenerator.UT)
			)
			if not unit.is_empty() and FieldCatalog.is_slate_unit(int(unit["s"]), int(unit["a"])):
				continue
			var y: float = FieldCollision.height_at(data, cell)
			if not FieldCollision.has_floor(y):
				continue
			var pos: Vector3 = grid.cell_to_world(cell)
			pos.y = y
			var revised: Vector3 = FieldCollision.revise_xz(data, grid, pos, pos)
			if Vector2(revised.x - pos.x, revised.z - pos.z).length() > 0.05:
				hit += 1
	assert_int(hit).is_equal(0)


func test_corner_does_not_trap_circle() -> void:
	## Two walls at a terrace corner: the circle slides out instead of freezing.
	var data: WorldData = WorldGenerator.generate(12345)
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var found := false
	for z: int in range(1, data.rows - 1):
		for x: int in range(1, data.columns - 1):
			var cell := Vector2i(x, z)
			var h: float = FieldCollision.height_at(data, cell)
			if not FieldCollision.has_floor(h):
				continue
			var east := Vector2i(x + 1, z)
			var south := Vector2i(x, z + 1)
			var he: float = FieldCollision.height_at(data, east)
			var hs: float = FieldCollision.height_at(data, south)
			if not FieldCollision.has_floor(he) or not FieldCollision.has_floor(hs):
				continue
			if absf(h - he) < 2.0 or absf(h - hs) < 2.0:
				continue
			var from: Vector3 = grid.cell_to_world(cell)
			from.y = h
			var to: Vector3 = from + Vector3(2.0, 0.0, 2.0)
			var revised: Vector3 = FieldCollision.revise_xz(data, grid, from, to)
			var moved: float = Vector2(revised.x - from.x, revised.z - from.z).length()
			## Radius 0.9 m leaves ~0.1 m of travel from a cell center before both walls.
			assert_float(moved).is_greater(0.05)
			assert_that(grid.world_to_cell(revised)).is_equal(cell)
			found = true
			break
		if found:
			break
	if not FieldCatalog.has_acre_collision(&"grd_s_c1_1") and not found:
		return
	assert_bool(found).is_true()


func test_player_house_plus_offset_leaves_porch() -> void:
	FieldCollision.clear_caches()
	var data: WorldData = _house_data()
	var b := BuildingPlacement.new()
	b.id = &"player_house"
	b.kind = &"house"
	b.cell = Vector2i(7, 1)
	b.footprint = Vector2i(2, 2)
	b.visual_id = &"obj_s_myhome1"
	b.mesh_facing = WorldGrid.Facing.SOUTH
	data.buildings.append(b)
	StructureOffset.apply(data)
	assert_that(StructureOffset.player_home_cell(b)).is_equal(Vector2i(8, 1))
	var porch: Vector2i = Vector2i(7, 3)
	var body: Vector2i = Vector2i(7, 2)
	var hp: float = FieldCollision.height_at(data, porch)
	var hb: float = FieldCollision.height_at(data, body)
	assert_float(hb).is_greater(hp + 2.0)
	assert_float(FieldCollision.ground_y(data, body)).is_equal_approx(FieldCollision.ground_y(data, porch), 0.01)


func test_west_player_house_porch_is_south_east() -> void:
	FieldCollision.clear_caches()
	var data: WorldData = _house_data()
	var b := BuildingPlacement.new()
	b.id = &"player_house"
	b.kind = &"house"
	b.cell = Vector2i(3, 3)
	b.footprint = Vector2i(2, 2)
	b.visual_id = &"obj_s_myhome1"
	b.mesh_facing = WorldGrid.Facing.WEST
	data.buildings.append(b)
	StructureOffset.apply(data)
	var home: Vector2i = StructureOffset.player_home_cell(b)
	assert_that(home).is_equal(Vector2i(3, 3))
	var porch: Vector2i = home + Vector2i(1, 2)
	var body: Vector2i = home + Vector2i(1, 1)
	assert_float(FieldCollision.height_at(data, body)).is_greater(FieldCollision.height_at(data, porch) + 2.0)


func test_npc_house_south_center_is_the_door() -> void:
	FieldCollision.clear_caches()
	var data: WorldData = _house_data()
	var b := BuildingPlacement.new()
	b.id = &"npc_house_0"
	b.kind = &"house"
	b.cell = Vector2i(4, 4)
	b.footprint = Vector2i(3, 3)
	b.visual_id = &"obj_s_house1"
	data.buildings.append(b)
	StructureOffset.apply(data)
	var home: Vector2i = StructureOffset.npc_home_cell(b)
	assert_that(home).is_equal(Vector2i(5, 5))
	var porch: Vector2i = home + Vector2i(0, 1)
	var body: Vector2i = home
	assert_float(FieldCollision.height_at(data, body)).is_greater(FieldCollision.height_at(data, porch) + 1.0)


func _house_data() -> WorldData:
	var data := WorldData.new()
	data.columns = 16
	data.rows = 16
	data.cell_size = 2.0
	data.acre_visual = &""
	data.bake()
	return data


func _visual_at(data: WorldData, cell: Vector2i) -> StringName:
	if data.acre_visuals.size() == TownFieldGenerator.BLOCK_TOTAL:
		var bx: int = int(cell.x / WorldGenerator.UT) + 1
		var bz: int = int(cell.y / WorldGenerator.UT) + 1
		if bx >= 1 and bx <= 5 and bz >= 1 and bz <= 6:
			return StringName(data.acre_visuals[bz * TownFieldGenerator.BLOCK_X + bx])
	return data.acre_visual
