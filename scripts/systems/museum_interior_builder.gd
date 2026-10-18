class_name MuseumInteriorBuilder
extends RefCounted

## Museum-specific fixtures: shell/collision for a wing, exhibit sets,
## Blathers, the entrance clock, and the painting-wing mid walls.
## Shell/door-gap geometry itself lives in `InteriorShellBuilder`.

const BLATHERS_SCENE := preload("res://scenes/world/museum/blathers.tscn")


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
	var redd: Node3D = (load("res://scenes/world/interiors/redd.tscn") as PackedScene).instantiate()
	redd.name = "Redd"
	## `aEBR2_search_player2` stands him at (60, 100) GX in the tent.
	redd.position = MuseumDisplay.gx_to_world(interior.grid, Vector3(60.0, 0.0, 100.0))
	root.add_child(redd)


## Katrina in her tent (`SCENE_BUGGY`, the player comes in at (160, 260) GX facing her).
static func add_katrina(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	if root.get_node_or_null("Katrina") != null:
		return
	var katrina: Node3D = (load("res://scenes/world/interiors/katrina.tscn") as PackedScene).instantiate()
	katrina.name = "Katrina"
	katrina.position = MuseumDisplay.gx_to_world(interior.grid, Vector3(160.0, 0.0, 140.0))
	root.add_child(katrina)


## Blathers in the entrance hall (talk / donate).
static func add_blathers(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	if root.get_node_or_null("Blathers") != null:
		return
	var blathers: Node3D = BLATHERS_SCENE.instantiate() as Node3D
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
		VisualFit.align_actor_to_height_gx(pivot, 0.0)


## Painting-wing inner walls from `rom_museum3`'s BG: the two partition rows (gaps at
## x 5–8 and 7–10), the pillars at the north corners and the raised strip between them.
## Partition units are 6 counts up (60 GX).
static func add_museum_art_partitions(root: Node3D, room: Room, grid: WorldGrid) -> void:
	if root == null or room == null or grid == null:
		return
	InteriorUnitCollision.add_hulls(root, grid, "MuseumArtCol", art_blocked_units(room))


## Units of the painting wing the BG blocks: `Vector2i` unit → height in GX.
static func art_blocked_units(room: Room) -> Dictionary:
	return InteriorUnitCollision.blocked_from_bg(
		&"rom_museum3",
		FieldCatalog.LAND_COUNTS,
		FieldCatalog.HEIGHT_MAX,
		Rect2i(room.inner_origin, room.inner_size)
	)
