class_name TestFieldCollision
extends GdUnitTestSuite

## Unit heightfield analog of `mCoBG` (terraces + slate ramps), not `grd_*` triangles.


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


func test_revise_xz_rejects_authored_pond() -> void:
	## `CarryOutReverse`: do not step onto a hole. Authored pond is not catalog water.
	var data: WorldData = WorldGenerator.authored_test_town()
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var land: Vector3 = grid.cell_to_world(Vector2i(8, 11))
	land.y = FieldCollision.ground_y_at(data, grid, land)
	var water: Vector3 = grid.cell_to_world(Vector2i(12, 3))
	water.y = land.y
	var revised: Vector3 = FieldCollision.revise_xz(data, grid, land, water)
	assert_float(revised.x).is_equal(land.x)
	assert_float(revised.z).is_equal(land.z)
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
				assert_float(revised.x).is_equal(from.x)
				assert_float(revised.z).is_equal(from.z)
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
				assert_float(revised.x).is_equal(from.x)
				assert_float(revised.z).is_equal(from.z)
				found = true
				break
			if found:
				break
		if found:
			break
	if not FieldCatalog.has_acre_collision(&"grd_s_c1_1") and not found:
		return
	assert_bool(found).is_true()


func test_catalog_walls_are_segments_not_boxes() -> void:
	## Cardinal + 45° walls. Oriented boxes / prism meshes, not convex hulls that fill the gap.
	if not FieldCatalog.has_acre_collision(&"grd_s_c1_1"):
		return
	var data: WorldData = WorldGenerator.generate(12345)
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var root: Node3D = auto_free(Node3D.new()) as Node3D
	FieldCollision.add_to(root, data, grid)
	var body: Node = root.get_node_or_null("Heightfield")
	assert_that(body).is_not_null()
	var wall_boxes := 0
	var diagonals := 0
	var prisms := 0
	var hulls := 0
	for child: Node in body.get_children():
		var col: CollisionShape3D = child as CollisionShape3D
		if col == null or col.shape == null:
			continue
		if col.shape is ConvexPolygonShape3D:
			hulls += 1
		elif col.shape is ConcavePolygonShape3D:
			prisms += 1
		elif col.shape is BoxShape3D:
			var size: Vector3 = (col.shape as BoxShape3D).size
			var thin: float = minf(size.x, size.z)
			var long_xz: float = maxf(size.x, size.z)
			if thin < 0.75 and long_xz > 1.0:
				wall_boxes += 1
				var xx: float = absf(col.transform.basis.x.x)
				var xz: float = absf(col.transform.basis.x.z)
				if xx > 0.3 and xz > 0.3:
					diagonals += 1
	assert_int(hulls).is_equal(0)
	assert_int(wall_boxes + prisms).is_greater(0)
	assert_int(diagonals).is_greater(0)


func test_slate_corner_cardinal_is_half_edge() -> void:
	## SE-notch slate + low east neighbor: full N–S wall jets out in front of the 45° face.
	## Keep only the north half (the pre-flatten height jump).
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
	var root: Node3D = auto_free(Node3D.new()) as Node3D
	FieldCollision.add_to(root, data, grid)
	var body: Node = root.get_node_or_null("Heightfield")
	assert_that(body).is_not_null()
	var slate := Vector2i(9, 8)
	var unit: Dictionary = FieldCatalog.unit_at(&"grd_s_c2_1", slate.x, slate.y)
	assert_bool(FieldCatalog.is_slate_unit(int(unit["s"]), int(unit["a"]))).is_true()
	assert_int(int(unit["se"])).is_less(int(unit["ne"]))
	var c0: Vector3 = grid.cell_corner(slate)
	var cs: float = grid.cell_size
	var east_x: float = c0.x + cs
	var full_len := 0
	var half_len := 0
	for child: Node in body.get_children():
		var col: CollisionShape3D = child as CollisionShape3D
		if col == null or not (col.shape is BoxShape3D):
			continue
		var size: Vector3 = (col.shape as BoxShape3D).size
		if minf(size.x, size.z) >= 0.75:
			continue
		var mid: Vector3 = col.global_position if col.is_inside_tree() else col.position
		## Oriented box mid sits on the low side of the edge (east + thickness/2).
		if absf(mid.x - (east_x + FieldCollision.WALL_THICK * 0.5)) > 0.05:
			continue
		if mid.z < c0.z - 0.05 or mid.z > c0.z + cs + 0.05:
			continue
		var along: float = maxf(size.x, size.z)
		if along > cs * 0.75:
			full_len += 1
		elif along > cs * 0.35:
			half_len += 1
	assert_int(full_len).is_equal(0)
	assert_int(half_len).is_greater(0)


func test_walls_do_not_cover_walkable_cell_centers() -> void:
	## Thickness sits on the low side; a cylinder at the unit center must not be inside a wall.
	if not FieldCatalog.has_acre_collision(&"grd_s_c1_1"):
		return
	var data: WorldData = WorldGenerator.generate(12345)
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var root: Node3D = auto_free(Node3D.new()) as Node3D
	FieldCollision.add_to(root, data, grid)
	var body: Node = root.get_node_or_null("Heightfield")
	assert_that(body).is_not_null()
	var hulls: Array[AABB] = []
	for child: Node in body.get_children():
		var col: CollisionShape3D = child as CollisionShape3D
		if col == null or col.shape == null:
			continue
		if col.shape is ConcavePolygonShape3D:
			var faces: PackedVector3Array = (col.shape as ConcavePolygonShape3D).get_faces()
			if faces.is_empty():
				continue
			var aabb := AABB(faces[0], Vector3.ZERO)
			for p: Vector3 in faces:
				aabb = aabb.expand(p)
			hulls.append(aabb)
		elif col.shape is BoxShape3D:
			var size: Vector3 = (col.shape as BoxShape3D).size
			if minf(size.x, size.z) >= 0.75:
				continue
			var xf: Transform3D = col.transform
			var half: Vector3 = size * 0.5
			var box_aabb := AABB(xf * Vector3(-half.x, -half.y, -half.z), Vector3.ZERO)
			for sx: int in [-1, 1]:
				for sy: int in [-1, 1]:
					for sz: int in [-1, 1]:
						box_aabb = box_aabb.expand(xf * Vector3(half.x * float(sx), half.y * float(sy), half.z * float(sz)))
			hulls.append(box_aabb)
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
			pos.y = y + 0.3
			for aabb: AABB in hulls:
				if aabb.has_point(pos):
					hit += 1
					break
	assert_int(hit).is_equal(0)


func _visual_at(data: WorldData, cell: Vector2i) -> StringName:
	if data.acre_visuals.size() == TownFieldGenerator.BLOCK_TOTAL:
		var bx: int = int(cell.x / WorldGenerator.UT) + 1
		var bz: int = int(cell.y / WorldGenerator.UT) + 1
		if bx >= 1 and bx <= 5 and bz >= 1 and bz <= 6:
			return StringName(data.acre_visuals[bz * TownFieldGenerator.BLOCK_X + bx])
	return data.acre_visual
