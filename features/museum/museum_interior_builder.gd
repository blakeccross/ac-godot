class_name MuseumInteriorBuilder
extends RefCounted

## Museum-specific fixtures: shell/collision for a wing, exhibit sets,
## Blathers, the entrance clock, and the painting-wing mid walls.
## Shell/door-gap geometry itself lives in `InteriorShellBuilder`.

const BLATHERS_SCENE := preload("res://features/museum/blathers.tscn")


static func add_museum_set(root: Node3D, interior: IndoorSession) -> void:
	## Fossils / art / tank fish / case insects from town `MuseumBook` bits.
	MuseumPresenter.new().present(root, interior)
	if interior == null or interior.room == null:
		return
	match interior.room.id:
		&"museum_entrance":
			add_blathers(root, interior)
			add_museum_clock(root, interior)
		_:
			pass


## Crazy Redd in the tent (talk / browse art).
static func add_redd(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	if root.get_node_or_null("Redd") != null:
		return
	var redd: Node3D = (load("res://features/shops/redd/redd.tscn") as PackedScene).instantiate()
	redd.name = "Redd"
	## `aEBR2_search_player2` stands him at (60, 100) GX in the tent.
	redd.position = WorldGrid.room_point(interior.grid, Vector3(60.0, 0.0, 100.0) * FieldCatalog.GX_TO_METERS)
	root.add_child(redd)


## Katrina in her tent (`SCENE_BUGGY`, the player comes in at (160, 260) GX facing her).
static func add_katrina(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	if root.get_node_or_null("Katrina") != null:
		return
	var katrina: Node3D = (load("res://features/events/katrina.tscn") as PackedScene).instantiate()
	katrina.name = "Katrina"
	katrina.position = WorldGrid.room_point(interior.grid, Vector3(160.0, 0.0, 140.0) * FieldCatalog.GX_TO_METERS)
	root.add_child(katrina)


## Blathers in the entrance hall (talk / donate).
static func add_blathers(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	if root.get_node_or_null("Blathers") != null:
		return
	var blathers: Node3D = BLATHERS_SCENE.instantiate() as Node3D
	blathers.position = WorldGrid.room_point(interior.grid, MuseumDisplay.BLATHERS_STAND)
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
	host.position = WorldGrid.room_point(interior.grid, MuseumDisplay.CLOCK)
	host.set_script(load("res://features/museum/museum_clock.gd"))
	root.add_child(host)
	var pivot: Node3D = GeneratedVisual.attach(host, MuseumDisplay.CLOCK_VISUAL)
	if pivot != null:
		## Skeleton joint Y is mid-body; rest the mesh on the floor.
		VisualFit.align_actor_to_height(pivot, 0.0)
