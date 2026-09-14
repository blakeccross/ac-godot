class_name MuseumInteriorBuilder
extends RefCounted

## Museum-specific fixtures: shell/collision for a wing, exhibit sets,
## Blathers, the entrance clock, and the painting-wing mid walls.
## Shell/door-gap geometry itself lives in `InteriorShellBuilder`.

const BLATHERS_SCRIPT := preload("res://scenes/world/museum/museum_blathers.gd")


static func build_museum_stage(root: Node3D, interior: IndoorSession) -> void:
	## Legacy single-root harness path — prefer `build_museum_room` per authored wing.
	build_museum_room(root, interior)


static func build_museum_room(room_root: Node3D, interior: IndoorSession) -> void:
	## Authored wing helper: shell collision only. Exhibits belong to each room script.
	if room_root == null or interior == null or interior.room == null:
		return
	var terrain: Node3D = room_root.get_node_or_null("Terrain") as Node3D
	if terrain == null:
		return
	InteriorShellBuilder.clear_shell_colliders(terrain)
	InteriorShellBuilder.add_museum_shell_collision(
		terrain, interior.room, interior.grid, InteriorShellBuilder.museum_door_gaps(interior.room, interior.grid)
	)


static func add_museum_set(root: Node3D, interior: IndoorSession) -> void:
	## Fossils / art / tank fish / case insects from town `MuseumBook` bits.
	MuseumPresenter.new().present(root, interior)
	if interior == null or interior.room == null:
		return
	match interior.room.id:
		&"museum_entrance":
			add_blathers(root, interior)
			add_museum_clock(root, interior)
		&"museum_painting":
			var terrain: Node3D = null
			if root != null and root.get_parent() != null:
				terrain = root.get_parent().get_node_or_null("Terrain") as Node3D
			add_museum_art_partitions(terrain, interior.room, interior.grid)
		_:
			pass


## Crazy Redd in the tent (talk / browse art).
static func add_redd(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	if root.get_node_or_null("Redd") != null:
		return
	var redd := StaticBody3D.new()
	redd.set_script(load("res://scenes/world/interiors/redd.gd"))
	redd.name = "Redd"
	redd.position = interior.grid.cell_to_world(interior.room.counter_cell())
	root.add_child(redd)


## Blathers in the entrance hall (talk / donate).
static func add_blathers(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	if root.get_node_or_null("Blathers") != null:
		return
	var blathers := StaticBody3D.new()
	blathers.set_script(BLATHERS_SCRIPT)
	blathers.name = "Blathers"
	blathers.position = MuseumDisplay.gx_to_world(interior.grid, MuseumDisplay.BLATHERS_STAND_GX)
	blathers.rotation.y = WorldGrid.yaw_for_facing(MuseumDisplay.BLATHERS_FACING)
	root.add_child(blathers)


## Floor clock in the entrance hall (`HOUSE_CLOCK` / `obj_clock_museum1`).
static func add_museum_clock(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	if root.get_node_or_null("MuseumClock") != null:
		return
	if FieldCatalog.mesh_paths(MuseumDisplay.CLOCK_VISUAL).is_empty():
		return
	var host := Node3D.new()
	host.name = "MuseumClock"
	host.position = MuseumDisplay.gx_to_world(interior.grid, MuseumDisplay.CLOCK_GX)
	host.set_script(load("res://scenes/world/museum/museum_clock.gd"))
	root.add_child(host)
	var pivot: Node3D = GeneratedVisual.attach(host, MuseumDisplay.CLOCK_VISUAL)
	if pivot != null:
		## Skeleton joint Y is mid-body; rest the mesh on the floor.
		GeneratedVisual.align_actor_to_height_gx(pivot, 0.0)


## Painting-wing E–W mid walls with walk gaps where `ART_CELLS` has no hang.
static func add_museum_art_partitions(root: Node3D, room: Room, grid: WorldGrid) -> void:
	if root == null or room == null or grid == null:
		return
	var occupied: Dictionary = {}
	for cell: Vector2i in MuseumDisplay.ART_CELLS:
		occupied[cell] = true
	var x0: int = room.inner_origin.x
	var x1: int = room.inner_origin.x + room.inner_size.x
	var thickness: float = grid.cell_size * 0.4
	for row_z: int in MuseumDisplay.ART_PARTITION_ROWS:
		var gaps: Array[Dictionary] = []
		for x: int in range(x0, x1):
			if bool(occupied.get(Vector2i(x, row_z), false)):
				continue
			var world: Vector3 = grid.cell_to_world(Vector2i(x, row_z))
			gaps.append({"center": world.x, "half": grid.cell_size * 0.5})
		var span_lo: float = grid.cell_corner(Vector2i(x0, row_z)).x
		var span_hi: float = grid.cell_corner(Vector2i(x1, row_z)).x
		var z_center: float = grid.cell_to_world(Vector2i(x0, row_z)).z
		var full_size := Vector3(span_hi - span_lo, InteriorShellBuilder.WALL_HEIGHT, thickness)
		var full_pos := Vector3((span_lo + span_hi) * 0.5, InteriorShellBuilder.WALL_HEIGHT * 0.5, z_center)
		InteriorShellBuilder.add_multi_gapped_wall(root, full_size, full_pos, &"x", span_lo, span_hi, gaps)
