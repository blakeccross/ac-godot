class_name InteriorShellBuilder
extends RefCounted

## Interior shell geometry: floor/wall visuals, collision, and the door-gap
## math shared by houses, public buildings, and museum wings. No fixtures,
## no doors nodes — `InteriorDoorBuilder` places the actual door nodes and
## `MuseumInteriorBuilder` / `InteriorBuilder` place furniture.

const WALL_HEIGHT := 3.0
## Door opening half-width (~1.5 UT). Matches walk-in sensors better than 1 UT.
const MUSEUM_DOOR_HALF_GX := 60.0


static func paint_shell(root: Node3D, room: Room, grid: WorldGrid) -> void:
	## Museum / Nook / post / police keep the acre NW at `grid.origin` (FG RSV / door GX).
	var shell_id := StringName(room.shell_ids[0]) if not room.shell_ids.is_empty() else &""
	var keep_acre := (
		room.kind == Room.Kind.MUSEUM or GeneratedVisual._shell_keeps_acre_origin(shell_id)
	)
	var target := (
		AABB(grid.origin, Vector3(float(grid.columns) * grid.cell_size, WALL_HEIGHT, float(grid.rows) * grid.cell_size))
		if keep_acre
		else shell_bounds(room, grid)
	)
	var shell: Node3D = GeneratedVisual.attach_interior(root, room.shell_ids, room.wall_id, room.floor_id, target)
	var gaps: Array = shell_door_gaps(room, grid)
	add_shell_collision(root, room, grid, gaps)
	if shell != null:
		return
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = InteriorStyleCatalog.floor_color(room.floor_id)
	if floor_mat.albedo_color.a <= 0.0:
		floor_mat.albedo_color = InteriorStyleCatalog.floor_color(InteriorStyleCatalog.FLOOR_DEFAULT)
	_apply_tile_texture(floor_mat, InteriorStyleCatalog.floor_texture_path(room.floor_id))
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = InteriorStyleCatalog.wall_color(room.wall_id)
	if wall_mat.albedo_color.a <= 0.0:
		wall_mat.albedo_color = InteriorStyleCatalog.wall_color(InteriorStyleCatalog.WALL_DEFAULT)
	_apply_tile_texture(wall_mat, InteriorStyleCatalog.wall_texture_path(room.wall_id))
	var inner := _inner_size(room, grid)
	var center := _inner_center(room, grid)
	root.add_child(_box_visual(Vector3(inner.x, 0.08, inner.z), center + Vector3(0.0, 0.04, 0.0), floor_mat))
	_add_wall_visuals(root, room, grid, wall_mat)


static func clear_shell_colliders(terrain: Node3D) -> void:
	## Drop box colliders from a previous populate.
	if terrain == null:
		return
	for child: Node in terrain.get_children():
		if child is StaticBody3D:
			terrain.remove_child(child)
			child.free()


## Floor slab + outer walls. `gaps` = [{ "side", "center", "half" }, ...] door openings.
static func add_museum_shell_collision(root: Node3D, room: Room, grid: WorldGrid, gaps: Variant = []) -> void:
	if root == null or room == null or grid == null:
		return
	var list: Array = _normalize_museum_gaps(gaps)
	add_shell_collision(root, room, grid, list)


static func add_shell_collision(root: Node3D, room: Room, grid: WorldGrid, gaps: Array = []) -> void:
	var inner := _inner_size(room, grid)
	var center := _inner_center(room, grid)
	root.add_child(_collider(Vector3(inner.x, 0.12, inner.z), center + Vector3(0.0, 0.04, 0.0)))
	## Door porches beyond the floor so wing / house EXIT_DOOR cells stay walkable.
	if not gaps.is_empty():
		_add_door_porches(root, room, grid, gaps)
	if not room.stairs.is_empty():
		_add_stair_caps(root, room, grid)
	var origin: Vector3 = grid.cell_corner(Vector2i.ZERO)
	var full := Vector3(float(grid.columns) * grid.cell_size, WALL_HEIGHT, float(grid.rows) * grid.cell_size)
	var inner_nw: Vector3 = grid.cell_corner(room.inner_origin)
	var inner_se: Vector3 = grid.cell_corner(room.inner_origin + room.inner_size)
	## Wing shells with thick rim walls (painting/fossil) inset one cell so
	## collision matches the inner face. Entrance walls are thin on the floor
	## AABB. Fish/insect exits sit on the south rim (z=560 GX): inset put the
	## south wall face on the door threshold and blocked the opening.
	var inset: float = 0.0
	if room.kind == Room.Kind.MUSEUM and room.id in [&"museum_painting", &"museum_fossil"]:
		inset = grid.cell_size
	var wall_nw := Vector3(inner_nw.x + inset, 0.0, inner_nw.z + inset)
	var wall_se := Vector3(inner_se.x - inset, 0.0, inner_se.z - inset)
	if wall_se.x <= wall_nw.x + 0.05 or wall_se.z <= wall_nw.z + 0.05:
		wall_nw = inner_nw
		wall_se = inner_se
	var north_d: float = wall_nw.z - origin.z
	if north_d > 0.05:
		add_multi_gapped_wall(
			root,
			Vector3(full.x, WALL_HEIGHT, north_d),
			Vector3(origin.x + full.x * 0.5, WALL_HEIGHT * 0.5, origin.z + north_d * 0.5),
			&"x",
			origin.x,
			origin.x + full.x,
			_gaps_on_side(gaps, &"north")
		)
	var south_d: float = origin.z + full.z - wall_se.z
	if south_d > 0.05:
		add_multi_gapped_wall(
			root,
			Vector3(full.x, WALL_HEIGHT, south_d),
			Vector3(origin.x + full.x * 0.5, WALL_HEIGHT * 0.5, wall_se.z + south_d * 0.5),
			&"x",
			origin.x,
			origin.x + full.x,
			_gaps_on_side(gaps, &"south")
		)
	var west_d: float = wall_nw.x - origin.x
	var mid_z: float = (wall_nw.z + wall_se.z) * 0.5
	var mid_h: float = wall_se.z - wall_nw.z
	if west_d > 0.05 and mid_h > 0.05:
		add_multi_gapped_wall(
			root,
			Vector3(west_d, WALL_HEIGHT, mid_h),
			Vector3(origin.x + west_d * 0.5, WALL_HEIGHT * 0.5, mid_z),
			&"z",
			wall_nw.z,
			wall_se.z,
			_gaps_on_side(gaps, &"west")
		)
	var east_d: float = origin.x + full.x - wall_se.x
	if east_d > 0.05 and mid_h > 0.05:
		add_multi_gapped_wall(
			root,
			Vector3(east_d, WALL_HEIGHT, mid_h),
			Vector3(wall_se.x + east_d * 0.5, WALL_HEIGHT * 0.5, mid_z),
			&"z",
			wall_nw.z,
			wall_se.z,
			_gaps_on_side(gaps, &"east")
		)


static func _add_door_porches(root: Node3D, room: Room, grid: WorldGrid, gaps: Array) -> void:
	var origin: Vector3 = grid.cell_corner(Vector2i.ZERO)
	var full_x: float = float(grid.columns) * grid.cell_size
	var full_z: float = float(grid.rows) * grid.cell_size
	var inner_nw: Vector3 = grid.cell_corner(room.inner_origin)
	var inner_se: Vector3 = grid.cell_corner(room.inner_origin + room.inner_size)
	for gap: Dictionary in _gaps_on_side(gaps, &"south"):
		var depth: float = origin.z + full_z - inner_se.z
		_add_porch_slab(root, gap, &"z", inner_se.z, depth)
	for gap: Dictionary in _gaps_on_side(gaps, &"north"):
		var depth: float = inner_nw.z - origin.z
		_add_porch_slab(root, gap, &"z", origin.z, depth)
	for gap: Dictionary in _gaps_on_side(gaps, &"west"):
		var depth: float = inner_nw.x - origin.x
		_add_porch_slab(root, gap, &"x", origin.x, depth)
	for gap: Dictionary in _gaps_on_side(gaps, &"east"):
		var depth: float = origin.x + full_x - inner_se.x
		_add_porch_slab(root, gap, &"x", inner_se.x, depth)


static func _add_porch_slab(
	root: Node3D, gap: Dictionary, depth_axis: StringName, depth_lo: float, depth: float
) -> void:
	var center: float = float(gap.get("center", NAN))
	var half: float = float(gap.get("half", 2.0))
	## Homes are origin-centered; door X can be negative.
	if is_nan(center) or half <= 0.05 or depth <= 0.05:
		return
	if depth_axis == &"z":
		root.add_child(
			_collider(
				Vector3(half * 2.0, 0.12, depth),
				Vector3(center, 0.04, depth_lo + depth * 0.5)
			)
		)
	else:
		root.add_child(
			_collider(
				Vector3(depth, 0.12, half * 2.0),
				Vector3(depth_lo + depth * 0.5, 0.04, center)
			)
		)


## Merges overlapping gaps, then emits solid wall segments between them.
## Public: `MuseumInteriorBuilder.add_museum_art_partitions` reuses this for
## the painting-wing mid walls, which aren't part of the outer shell.
static func add_multi_gapped_wall(
	root: Node3D,
	full_size: Vector3,
	full_pos: Vector3,
	axis: StringName,
	span_lo: float,
	span_hi: float,
	gaps: Array[Dictionary]
) -> void:
	if gaps.is_empty():
		root.add_child(_collider(full_size, full_pos))
		return
	var cuts: Array[Vector2] = []
	for gap: Dictionary in gaps:
		var center: float = float(gap.get("center", NAN))
		var half: float = float(gap.get("half", 2.0))
		## Homes are centered at (−16,−16); door X is negative. Do not require center ≥ 0.
		if is_nan(center) or half <= 0.05:
			continue
		cuts.append(Vector2(center - half, center + half))
	if cuts.is_empty():
		root.add_child(_collider(full_size, full_pos))
		return
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = [cuts[0]]
	for i: int in range(1, cuts.size()):
		var prev: Vector2 = merged[merged.size() - 1]
		var cur: Vector2 = cuts[i]
		if cur.x <= prev.y + 0.05:
			merged[merged.size() - 1] = Vector2(prev.x, maxf(prev.y, cur.y))
		else:
			merged.append(cur)
	var cursor: float = span_lo
	for cut: Vector2 in merged:
		var gap_lo: float = maxf(cut.x, span_lo)
		var gap_hi: float = minf(cut.y, span_hi)
		if gap_lo > cursor + 0.05:
			_add_wall_segment(root, full_size, full_pos, axis, cursor, gap_lo)
		cursor = maxf(cursor, gap_hi)
	if span_hi > cursor + 0.05:
		_add_wall_segment(root, full_size, full_pos, axis, cursor, span_hi)


static func _add_wall_segment(
	root: Node3D,
	full_size: Vector3,
	full_pos: Vector3,
	axis: StringName,
	seg_lo: float,
	seg_hi: float
) -> void:
	var width: float = seg_hi - seg_lo
	if width <= 0.05:
		return
	if axis == &"x":
		root.add_child(
			_collider(
				Vector3(width, full_size.y, full_size.z),
				Vector3(seg_lo + width * 0.5, full_pos.y, full_pos.z)
			)
		)
	else:
		root.add_child(
			_collider(
				Vector3(full_size.x, full_size.y, width),
				Vector3(full_pos.x, full_pos.y, seg_lo + width * 0.5)
			)
		)


static func _add_wall_visuals(root: Node3D, room: Room, grid: WorldGrid, mat: Material) -> void:
	var origin: Vector3 = grid.cell_corner(Vector2i.ZERO)
	var full := Vector3(float(grid.columns) * grid.cell_size, WALL_HEIGHT, float(grid.rows) * grid.cell_size)
	var inner_nw: Vector3 = grid.cell_corner(room.inner_origin)
	var inner_se: Vector3 = grid.cell_corner(room.inner_origin + room.inner_size)
	var north_d: float = inner_nw.z - origin.z
	if north_d > 0.05:
		root.add_child(
			_box_visual(
				Vector3(full.x, WALL_HEIGHT, north_d),
				Vector3(origin.x + full.x * 0.5, WALL_HEIGHT * 0.5, origin.z + north_d * 0.5),
				mat
			)
		)
	var south_d: float = origin.z + full.z - inner_se.z
	if south_d > 0.05:
		root.add_child(
			_box_visual(
				Vector3(full.x, WALL_HEIGHT, south_d),
				Vector3(origin.x + full.x * 0.5, WALL_HEIGHT * 0.5, inner_se.z + south_d * 0.5),
				mat
			)
		)
	var west_d: float = inner_nw.x - origin.x
	var mid_z: float = (inner_nw.z + inner_se.z) * 0.5
	var mid_h: float = inner_se.z - inner_nw.z
	if west_d > 0.05:
		root.add_child(
			_box_visual(
				Vector3(west_d, WALL_HEIGHT, mid_h),
				Vector3(origin.x + west_d * 0.5, WALL_HEIGHT * 0.5, mid_z),
				mat
			)
		)
	var east_d: float = origin.x + full.x - inner_se.x
	if east_d > 0.05:
		root.add_child(
			_box_visual(
				Vector3(east_d, WALL_HEIGHT, mid_h),
				Vector3(inner_se.x + east_d * 0.5, WALL_HEIGHT * 0.5, mid_z),
				mat
			)
		)


static func _inner_size(room: Room, grid: WorldGrid) -> Vector3:
	return Vector3(
		float(maxi(room.inner_size.x, 1)) * grid.cell_size,
		WALL_HEIGHT,
		float(maxi(room.inner_size.y, 1)) * grid.cell_size
	)


static func _inner_center(room: Room, grid: WorldGrid) -> Vector3:
	var nw: Vector3 = grid.cell_corner(room.inner_origin)
	var size := _inner_size(room, grid)
	return Vector3(nw.x + size.x * 0.5, 0.0, nw.z + size.z * 0.5)


static func _collider(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body


static func _box_visual(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.position = pos
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = mat
	return visual


## Fit shell to the walkable rect (same as player myhome). NPC Arrange_Room
## uses rom_myhome2, not the 8×8 room01 acre.
static func shell_bounds(room: Room, grid: WorldGrid) -> AABB:
	var nw: Vector3 = grid.cell_corner(room.inner_origin)
	var se: Vector3 = grid.cell_corner(room.inner_origin + room.inner_size)
	return AABB(Vector3(nw.x, 0.0, nw.z), Vector3(se.x - nw.x, WALL_HEIGHT, se.z - nw.z))


static func _apply_tile_texture(mat: StandardMaterial3D, path: String) -> void:
	if path.is_empty():
		return
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.texture_repeat = true


## Wall openings for the current room (museum sensors or house EXIT_DOOR).
static func shell_door_gaps(room: Room, grid: WorldGrid) -> Array[Dictionary]:
	if room == null or grid == null:
		return []
	if room.kind == Room.Kind.MUSEUM:
		return museum_door_gaps(room, grid)
	## Houses + public rooms with south EXIT_DOOR (shop / post / police / Able).
	if (
		room.kind == Room.Kind.PLAYER
		or room.kind == Room.Kind.NPC
		or room.kind == Room.Kind.SHOP
		or room.kind == Room.Kind.POST_OFFICE
		or room.kind == Room.Kind.POLICE
		or room.kind == Room.Kind.NEEDLEWORK
	):
		return house_door_gaps(room, grid)
	return []


## Player / NPC EXIT_DOOR pair (`door_cell` + `(+1,0)`) — south porch past the carpet.
## Upper floor / basement have no outdoor exit (`door_cell.x < 0`), only stair bays.
static func house_door_gaps(room: Room, grid: WorldGrid) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if room == null or grid == null:
		return out
	if room.door_cell.x >= 0:
		var left: Vector3 = grid.cell_to_world(room.door_cell)
		var right: Vector3 = grid.cell_to_world(room.door_cell + Vector2i(1, 0))
		## Full two-unit strip so spawn (north of EXIT) and leave stay walkable.
		out.append({"side": &"south", "center": (left.x + right.x) * 0.5, "half": grid.cell_size})
	out.append_array(stair_bay_gaps(room, grid))
	return out


## Stair bays (`DOOR0` / `DOOR1`): the unit you land on plus the `DOOR` unit, in the first
## wall row south of the carpet. `[{ side, center, half, cap }]`.
static func stair_bay_gaps(room: Room, grid: WorldGrid) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if room == null or grid == null:
		return out
	for stair: RoomStair in room.stairs:
		if stair == null:
			continue
		var landing: Vector2i = grid.world_to_cell(MuseumDisplay.gx_to_world(grid, stair.spawn_gx))
		var x0: int = mini(stair.cell.x, landing.x)
		var x1: int = maxi(stair.cell.x, landing.x) + 1
		var lo: float = grid.cell_corner(Vector2i(x0, 0)).x
		var hi: float = grid.cell_corner(Vector2i(x1, 0)).x
		out.append({"side": &"south", "center": (lo + hi) * 0.5, "half": (hi - lo) * 0.5, "cap": true})
	return out


## One-row dead end behind each stair bay so the gap does not open the whole south rim.
static func _add_stair_caps(root: Node3D, room: Room, grid: WorldGrid) -> void:
	var origin: Vector3 = grid.cell_corner(Vector2i.ZERO)
	var full_z: float = float(grid.rows) * grid.cell_size
	var inner_se: Vector3 = grid.cell_corner(room.inner_origin + room.inner_size)
	var cap_z: float = inner_se.z + grid.cell_size
	var depth: float = origin.z + full_z - cap_z
	if depth <= 0.05:
		return
	for gap: Dictionary in stair_bay_gaps(room, grid):
		var half: float = float(gap["half"])
		root.add_child(
			_collider(
				Vector3(half * 2.0, WALL_HEIGHT, depth),
				Vector3(float(gap["center"]), WALL_HEIGHT * 0.5, cap_z + depth * 0.5)
			)
		)


## All wall openings for a museum room (wing links + leave sensors).
static func museum_door_gaps(room: Room, grid: WorldGrid) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if room == null or grid == null:
		return out
	var sensors: Array[Vector3] = []
	if room.id == &"museum_entrance":
		sensors.append(MuseumDisplay.ENTRANCE_EXIT_SENSOR_GX)
		for link: Dictionary in MuseumDisplay.ENTRANCE_WING_DOORS:
			sensors.append(link["sensor"] as Vector3)
	elif MuseumDisplay.WING_EXIT_DOORS.has(room.id):
		sensors.append(MuseumDisplay.WING_EXIT_DOORS[room.id]["sensor"] as Vector3)
	var half: float = MUSEUM_DOOR_HALF_GX * FieldCatalog.GX_TO_METERS
	for sensor: Vector3 in sensors:
		var gap: Dictionary = _museum_gap_for_sensor(grid, sensor, half)
		if not gap.is_empty():
			out.append(gap)
	return out


## Backward-compatible single leave-door gap (prefer `museum_door_gaps`).
static func museum_exit_gap(room: Room, grid: WorldGrid) -> Dictionary:
	var gaps: Array[Dictionary] = museum_door_gaps(room, grid)
	if room != null and room.id == &"museum_entrance":
		for gap: Dictionary in gaps:
			if gap.get("side", &"") == &"south":
				return gap
	return gaps[0] if not gaps.is_empty() else {}


static func _museum_gap_for_sensor(grid: WorldGrid, sensor: Vector3, half: float) -> Dictionary:
	var world: Vector3 = MuseumDisplay.gx_to_world(grid, sensor)
	var side: StringName = museum_door_side(sensor)
	match side:
		&"north", &"south":
			return {"side": side, "center": world.x, "half": half}
		&"west", &"east":
			return {"side": side, "center": world.z, "half": half}
		_:
			return {"side": &"south", "center": world.x, "half": half}


static func _normalize_museum_gaps(gaps: Variant) -> Array:
	if gaps is Dictionary:
		return [gaps] if not (gaps as Dictionary).is_empty() else []
	if gaps is Array:
		return gaps as Array
	return []


static func _gaps_on_side(gaps: Array, side: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in gaps:
		if entry is Dictionary and (entry as Dictionary).get("side", &"") == side:
			out.append(entry as Dictionary)
	return out


## North/south walls: wide in X. East/west walls: wide in Z.
## Corner sensors (insect/fish z=560 + x=80/560) must use X thresholds — z-only
## heuristics mistook them for south doors and swallowed the enter spawn.
static func museum_door_box(sensor_gx: Vector3) -> Vector3:
	var wide: float = MUSEUM_DOOR_HALF_GX * 2.0 * FieldCatalog.GX_TO_METERS
	var deep: float = 40.0 * FieldCatalog.GX_TO_METERS
	var tall: float = 2.6
	var side: StringName = museum_door_side(sensor_gx)
	var along_x: bool = side == &"north" or side == &"south"
	return Vector3(wide, tall, deep) if along_x else Vector3(deep, tall, wide)


static func museum_door_side(sensor_gx: Vector3) -> StringName:
	## Same rules as `_museum_gap_for_sensor`.
	if sensor_gx.z <= 120.0:
		return &"north"
	if sensor_gx.z >= 400.0 and sensor_gx.x > 120.0 and sensor_gx.x < 400.0:
		return &"south"
	if sensor_gx.x <= 120.0:
		return &"west"
	if sensor_gx.x >= 400.0:
		return &"east"
	return &"south"
