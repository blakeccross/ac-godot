class_name InteriorBuilder
extends RefCounted

## Generic interior assembly: shell fit + collision (`InteriorShellBuilder`),
## doors (`InteriorDoorBuilder`), and data-driven `FurniturePlacement`.
## Building-specific fixtures (shopkeepers, stock, the Able Sisters set,
## museum exhibits — `MuseumInteriorBuilder`) live in the room's own `.tscn`
## script → `present_exhibits()` → a `*Presenter` (`ShopPresenter`,
## `NeedleworkPresenter`, `PostPresenter`, `PolicePresenter`, `MuseumPresenter`).
## Scene-less rooms use `furnish_fallback`.

const FURNITURE_SCENE := preload("res://scenes/world/furniture.tscn")
## Authored `Furniture/*` fixtures that survive a re-populate (only data-driven
## exhibits / stock rebuild). Each presenter names its persistent nodes here or
## adds them to the `"authored_fixture"` group.
const AUTHORED_FIXTURE_NAMES: Array[StringName] = [
	&"TomNook", &"NookClock", &"PostGirl", &"PostDesk", &"PostTerminal", &"Booker",
	&"Blathers", &"MuseumClock", &"LightShaft", &"Redd", &"Mabel", &"Sable",
	&"NeedleworkFurnitureCol", &"SewingMachine", &"SewingCloth", &"NeedleworkClock",
]


static func build(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.room == null:
		return
	var room: Room = interior.room
	var grid: WorldGrid = interior.grid
	var terrain: Node3D = root.get_node_or_null("Terrain") as Node3D
	var furniture_root: Node3D = root.get_node_or_null("Furniture") as Node3D
	var doors_root: Node3D = root.get_node_or_null("Doors") as Node3D
	if terrain == null:
		terrain = Node3D.new()
		terrain.name = "Terrain"
		root.add_child(terrain)
	if furniture_root == null:
		furniture_root = Node3D.new()
		furniture_root.name = "Furniture"
		root.add_child(furniture_root)
	if doors_root == null:
		doors_root = Node3D.new()
		doors_root.name = "Doors"
		root.add_child(doors_root)
	InteriorShellBuilder.paint_shell(terrain, room, grid)
	for entry: FurniturePlacement in room.placements:
		add_furniture(furniture_root, interior, entry)
	furnish_fallback(furniture_root, interior)
	InteriorDoorBuilder.add_exit_door(doors_root, grid, room)
	InteriorDoorBuilder.add_linked_doors(doors_root, grid, room)


## Authored public/museum room: shell fit + collision + furniture + shop set.
## Doors stay as authored children under `Doors/` (positions refreshed).
static func populate_authored(room_root: Node3D, interior: IndoorSession) -> void:
	if room_root == null or interior == null or interior.room == null:
		return
	var room: Room = interior.room
	var grid: WorldGrid = interior.grid
	var terrain: Node3D = room_root.get_node_or_null("Terrain") as Node3D
	var furniture_root: Node3D = room_root.get_node_or_null("Furniture") as Node3D
	var doors_root: Node3D = room_root.get_node_or_null("Doors") as Node3D
	if terrain == null or furniture_root == null:
		return
	InteriorShellBuilder.clear_shell_colliders(terrain)
	for child: Node in furniture_root.get_children():
		## Keep authored fixtures (shopkeepers, clerks, curator, clocks, light shafts);
		## only the data-driven exhibits are rebuilt on re-populate.
		if child.name in AUTHORED_FIXTURE_NAMES or child.is_in_group("authored_fixture"):
			continue
		furniture_root.remove_child(child)
		child.free()
	var shell_vis: Node3D = room_root.get_node_or_null("Shell/GeneratedVisual") as Node3D
	if shell_vis != null and shell_vis.get_child_count() > 0:
		GeneratedVisual.layout_authored_interior(shell_vis, room, grid, InteriorShellBuilder.WALL_HEIGHT)
		var gaps: Array = InteriorShellBuilder.shell_door_gaps(room, grid)
		InteriorShellBuilder.add_shell_collision(terrain, room, grid, gaps)
	else:
		InteriorShellBuilder.paint_shell(terrain, room, grid)
	for entry: FurniturePlacement in room.placements:
		add_furniture(furniture_root, interior, entry)
	## Every authored room's script owns its fixtures (`present_exhibits`, same as
	## the museum wings). Scene-less kinds fall back to `furnish_fallback`.
	if room_root.has_method("present_exhibits"):
		room_root.call("present_exhibits", furniture_root, interior)
	else:
		furnish_fallback(furniture_root, interior)
	InteriorDoorBuilder.place_authored_doors(doors_root, grid, room)


## Furnishing for rooms with no authored `.tscn` script (Redd's tent; the
## `build()` placeholder path). Authored rooms use their own `present_exhibits`.
static func furnish_fallback(furniture_root: Node3D, interior: IndoorSession) -> void:
	if interior == null or interior.room == null:
		return
	match interior.room.kind:
		Room.Kind.MUSEUM:
			MuseumInteriorBuilder.add_museum_set(furniture_root, interior)
		Room.Kind.SHOP:
			ShopPresenter.new().present(furniture_root, interior)
		Room.Kind.NEEDLEWORK:
			NeedleworkPresenter.new().present(furniture_root, interior)
		Room.Kind.POST_OFFICE:
			PostPresenter.new().present(furniture_root, interior)
		Room.Kind.POLICE:
			PolicePresenter.new().present(furniture_root, interior)
		Room.Kind.BROKER:
			MuseumInteriorBuilder.add_redd(furniture_root, interior)
		_:
			pass


static func add_furniture(root: Node3D, interior: IndoorSession, entry: FurniturePlacement) -> void:
	if entry == null or entry.id == &"":
		return
	var data: FurnitureData = interior.furniture_of(entry.furniture_id)
	if data == null:
		return
	var footprint: Vector2i = entry.resolved_footprint(data)
	var node: Node3D = FURNITURE_SCENE.instantiate() as Node3D
	node.name = String(entry.id)
	node.set("data", data)
	node.set("occupant_id", entry.id)
	node.set("footprint", footprint)
	node.set("grid_facing", entry.facing)
	node.set("cloth_index", entry.cloth_index)
	if data.visual_id != &"":
		node.set("visual_id", data.visual_id)
	var pos: Vector3 = interior.grid.furniture_world(entry.cell, footprint, entry.facing)
	pos.y = 0.8 if entry.layer > 0 else 0.0
	node.position = pos
	root.add_child(node)
	if entry.cloth_index >= 0:
		GeneratedVisual.apply_cloth(node, entry.cloth_index)
	if node.has_method("apply_grid_yaw"):
		node.call("apply_grid_yaw", entry.facing)
	if node.has_method("apply_footprint"):
		node.call("apply_footprint", interior.grid.cell_size)
