class_name InteriorDoorBuilder
extends RefCounted

## Places door nodes (exit / linked room / museum wing) into an interior's
## `Doors/` root. Shell/collision geometry lives in `InteriorShellBuilder`.

const DOOR_SCENE := preload("res://scenes/world/door.tscn")


static func add_exit_door(root: Node3D, grid: WorldGrid, room: Room) -> void:
	var door := DOOR_SCENE.instantiate() as Door
	door.name = "Exit"
	door.label = "Leave"
	door.verb = Interaction.ENTER
	door.occupy_grid = false
	## Museum wings return to the entrance at decomp door spawns — not the outdoor exit.
	if room.kind == Room.Kind.MUSEUM and room.parent_room_id != &"" and MuseumDisplay.WING_EXIT_DOORS.has(room.id):
		var link: Dictionary = MuseumDisplay.WING_EXIT_DOORS[room.id] as Dictionary
		door.position = WorldGrid.room_point(grid, link["sensor"] as Vector3)
		door.exits_interior = false
		door.linked_room_id = room.parent_room_id
		door.auto_enter = true
		door.has_linked_spawn = true
		door.linked_spawn = link["spawn"] as Vector3
		## `m_scene.c` angle_table matches furniture yaw (EAST=+90°), not `yaw_for_facing`.
		door.linked_spawn_yaw = WorldGrid.yaw_for_furniture(link["facing"] as WorldGrid.Facing)
		_size_museum_wing_door(door, link["sensor"] as Vector3)
	elif room.id == &"museum_entrance":
		## South opening sits on enter X (`aMsm_museum_enter_data`), not room-center door_cell.
		var sensor: Vector3 = MuseumDisplay.ENTRANCE_EXIT_SENSOR
		door.position = WorldGrid.room_point(grid, sensor)
		door.exits_interior = true
		door.auto_enter = true
		_size_museum_wing_door(door, sensor)
	elif room.door_cell.x < 0:
		## Upper floor / basement: stairs only (`Interior._physics_process` checks the stair unit).
		door.free()
		return
	else:
		## EXIT_DOOR pair midpoint (houses / shops).
		door.position = (
			grid.cell_to_world(room.door_cell)
			+ grid.cell_to_world(room.door_cell + Vector2i(1, 0))
		) * 0.5
		door.exits_interior = true
	root.add_child(door)


## Nookington's stairs: a walk-on door pair in the north wall to the other floor, arriving just
## inside the opposite stairs (`SHOP04_1F_door_data` / `SHOP04_2F_door_data`).
static func _add_nook_stairs(root: Node3D, grid: WorldGrid, room: Room) -> void:
	var link: Dictionary = ShopDisplay.NOOK_STAIRS[room.id] as Dictionary
	var to: StringName = link["to"] as StringName
	var template: Room = InteriorCatalog.room_template(to)
	var door := root.get_node_or_null("Link_%s" % String(to)) as Door
	if door == null:
		door = DOOR_SCENE.instantiate() as Door
		door.name = "Link_%s" % String(to)
		root.add_child(door)
	door.position = WorldGrid.room_point(grid, ShopDisplay.STAIRS_SENSOR)
	door.label = "stairs" if template == null else "the stairs to %s" % template.display_name
	door.verb = Interaction.ENTER
	door.linked_room_id = to
	door.occupy_grid = false
	door.auto_enter = true
	door.has_linked_spawn = true
	door.linked_spawn = link["spawn"] as Vector3
	door.linked_spawn_yaw = WorldGrid.yaw_for_furniture(WorldGrid.Facing.SOUTH)
	HostCollision.resize_interact_box(door, ShopDisplay.STAIRS_BOX)


static func place_authored_doors(root: Node3D, grid: WorldGrid, room: Room) -> void:
	## Keep editor-authored door nodes; refresh world position + leave/link flags.
	if root == null or grid == null or room == null:
		return
	if room.kind == Room.Kind.MUSEUM:
		return
	if ShopDisplay.NOOK_STAIRS.has(room.id):
		var shop_exit: Node3D = root.get_node_or_null("Exit") as Node3D
		if room.door_cell.x < 0 and shop_exit != null:
			shop_exit.queue_free()
		elif room.door_cell.x >= 0 and shop_exit == null:
			add_exit_door(root, grid, room)
		_add_nook_stairs(root, grid, room)
		return
	var exit_door := root.get_node_or_null("Exit") as Door
	if exit_door != null:
		exit_door.position = (
			grid.cell_to_world(room.door_cell)
			+ grid.cell_to_world(room.door_cell + Vector2i(1, 0))
		) * 0.5
		exit_door.exits_interior = true
		exit_door.label = "Leave"
		exit_door.occupy_grid = false
	elif root.get_child_count() == 0:
		add_exit_door(root, grid, room)
	if room.linked_rooms.is_empty():
		return
	var inner_north := room.inner_origin.y
	var start_x: int = room.inner_origin.x + 1
	for i: int in room.linked_rooms.size():
		var room_id: StringName = room.linked_rooms[i]
		var door := root.get_node_or_null("Link_%s" % String(room_id)) as Door
		var template: Room = InteriorCatalog.room_template(room_id)
		var cell := Vector2i(start_x + i * 2, inner_north)
		if not room.is_inner(cell):
			cell = Vector2i(room.inner_origin.x, inner_north)
		if door == null:
			door = DOOR_SCENE.instantiate() as Door
			door.name = "Link_%s" % String(room_id)
			root.add_child(door)
		door.position = grid.cell_to_world(cell)
		door.label = template.display_name if template else "Room"
		door.verb = Interaction.ENTER
		door.linked_room_id = room_id
		door.occupy_grid = false


static func add_linked_doors(root: Node3D, grid: WorldGrid, room: Room) -> void:
	if room.kind == Room.Kind.MUSEUM and room.id == &"museum_entrance":
		_add_museum_entrance_doors(root, grid)
		return
	if ShopDisplay.NOOK_STAIRS.has(room.id):
		_add_nook_stairs(root, grid, room)
		return
	if room.linked_rooms.is_empty():
		return
	var inner_north := room.inner_origin.y
	var start_x: int = room.inner_origin.x + 1
	for i: int in room.linked_rooms.size():
		var room_id: StringName = room.linked_rooms[i]
		var template: Room = InteriorCatalog.room_template(room_id)
		var door := DOOR_SCENE.instantiate() as Door
		door.name = "Link_%s" % String(room_id)
		var cell := Vector2i(start_x + i * 2, inner_north)
		if not room.is_inner(cell):
			cell = Vector2i(room.inner_origin.x, inner_north)
		door.position = grid.cell_to_world(cell)
		door.label = template.display_name if template else "Room"
		door.verb = Interaction.ENTER
		door.linked_room_id = room_id
		door.occupy_grid = false
		root.add_child(door)


static func _add_museum_entrance_doors(root: Node3D, grid: WorldGrid) -> void:
	## Four wing doors from `MUSEUM_ENTRANCE_door_data` (north / west / east walls).
	for link: Dictionary in MuseumDisplay.ENTRANCE_WING_DOORS:
		var room_id: StringName = link["room"] as StringName
		var template: Room = InteriorCatalog.room_template(room_id)
		var door := DOOR_SCENE.instantiate() as Door
		door.name = "Link_%s" % String(room_id)
		door.position = WorldGrid.room_point(grid, link["sensor"] as Vector3)
		door.label = template.display_name if template else "Room"
		door.verb = Interaction.ENTER
		door.linked_room_id = room_id
		door.occupy_grid = false
		door.auto_enter = true
		door.has_linked_spawn = true
		door.linked_spawn = link["spawn"] as Vector3
		door.linked_spawn_yaw = WorldGrid.yaw_for_furniture(link["facing"] as WorldGrid.Facing)
		_size_museum_wing_door(door, link["sensor"] as Vector3)
		root.add_child(door)


static func _size_museum_wing_door(door: Node3D, sensor: Vector3) -> void:
	## Match wall gap half-width so the player cannot slip past the sensor.
	HostCollision.resize_interact_box(door, InteriorShellBuilder.museum_door_box(sensor))
