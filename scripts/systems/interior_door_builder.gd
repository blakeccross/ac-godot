class_name InteriorDoorBuilder
extends RefCounted

## Places door nodes (exit / linked room / museum wing) into an interior's
## `Doors/` root. Shell/collision geometry lives in `InteriorShellBuilder`.

const DOOR_SCENE := preload("res://scenes/world/door.tscn")


static func add_exit_door(root: Node3D, grid: WorldGrid, room: Room) -> void:
	var door: Node3D = DOOR_SCENE.instantiate() as Node3D
	door.name = "Exit"
	door.set("label", "Leave")
	door.set("verb", Interaction.ENTER)
	door.set("occupy_grid", false)
	## Museum wings return to the entrance at decomp door spawns — not the outdoor exit.
	if room.kind == Room.Kind.MUSEUM and room.parent_room_id != &"" and MuseumDisplay.WING_EXIT_DOORS.has(room.id):
		var link: Dictionary = MuseumDisplay.WING_EXIT_DOORS[room.id] as Dictionary
		door.position = MuseumDisplay.gx_to_world(grid, link["sensor"] as Vector3)
		door.set("exits_interior", false)
		door.set("linked_room_id", room.parent_room_id)
		door.set("auto_enter", true)
		door.set("has_linked_spawn", true)
		door.set("linked_spawn_gx", link["spawn"] as Vector3)
		## `m_scene.c` angle_table matches furniture yaw (EAST=+90°), not `yaw_for_facing`.
		door.set("linked_spawn_yaw", WorldGrid.yaw_for_furniture(link["facing"] as WorldGrid.Facing))
		_size_museum_wing_door(door, link["sensor"] as Vector3)
	elif room.id == &"museum_entrance":
		## South opening sits on enter X (`aMsm_museum_enter_data`), not room-center door_cell.
		var sensor: Vector3 = MuseumDisplay.ENTRANCE_EXIT_SENSOR_GX
		door.position = MuseumDisplay.gx_to_world(grid, sensor)
		door.set("exits_interior", true)
		door.set("auto_enter", true)
		_size_museum_wing_door(door, sensor)
	elif room.door_cell.x < 0:
		## Upper floor / basement: stairs only (`add_stair_doors`).
		door.free()
		return
	else:
		## EXIT_DOOR pair midpoint (houses / shops).
		door.position = (
			grid.cell_to_world(room.door_cell)
			+ grid.cell_to_world(room.door_cell + Vector2i(1, 0))
		) * 0.5
		door.set("exits_interior", true)
	root.add_child(door)


static func place_authored_doors(root: Node3D, grid: WorldGrid, room: Room) -> void:
	## Keep editor-authored door nodes; refresh world position + leave/link flags.
	if root == null or grid == null or room == null:
		return
	if room.kind == Room.Kind.MUSEUM:
		return
	var exit_door: Node3D = root.get_node_or_null("Exit") as Node3D
	if exit_door != null:
		exit_door.position = (
			grid.cell_to_world(room.door_cell)
			+ grid.cell_to_world(room.door_cell + Vector2i(1, 0))
		) * 0.5
		exit_door.set("exits_interior", true)
		exit_door.set("label", "Leave")
		exit_door.set("occupy_grid", false)
	elif root.get_child_count() == 0:
		add_exit_door(root, grid, room)
	if room.linked_rooms.is_empty():
		return
	var inner_north := room.inner_origin.y
	var start_x: int = room.inner_origin.x + 1
	for i: int in room.linked_rooms.size():
		var room_id: StringName = room.linked_rooms[i]
		var door: Node3D = root.get_node_or_null("Link_%s" % String(room_id)) as Node3D
		var template: Room = InteriorCatalog.room_template(room_id)
		var cell := Vector2i(start_x + i * 2, inner_north)
		if not room.is_inner(cell):
			cell = Vector2i(room.inner_origin.x, inner_north)
		if door == null:
			door = DOOR_SCENE.instantiate() as Node3D
			door.name = "Link_%s" % String(room_id)
			root.add_child(door)
		door.position = grid.cell_to_world(cell)
		door.set("label", template.display_name if template else "Room")
		door.set("verb", Interaction.ENTER)
		door.set("linked_room_id", room_id)
		door.set("occupy_grid", false)


## Player-house stairs: walk onto the `DOOR` unit to change floor (`goto_next_scene` with the
## door index). Lands at the target scene's `Door_data_c` exit position.
static func add_stair_doors(root: Node3D, grid: WorldGrid, room: Room) -> void:
	if root == null or grid == null or room == null:
		return
	for stair: RoomStair in room.stairs:
		if stair == null or stair.target_room_id == &"":
			continue
		var door: Node3D = DOOR_SCENE.instantiate() as Node3D
		door.name = "Stairs_%s" % String(stair.target_room_id)
		door.position = grid.cell_to_world(stair.cell)
		door.set("label", stair.label)
		door.set("verb", Interaction.ENTER)
		door.set("linked_room_id", stair.target_room_id)
		door.set("occupy_grid", false)
		door.set("auto_enter", true)
		door.set("has_linked_spawn", true)
		door.set("linked_spawn_gx", stair.spawn_gx)
		door.set("linked_spawn_yaw", WorldGrid.yaw_for_furniture(stair.spawn_facing))
		HostCollision.resize_interact_box(door, Vector3(grid.cell_size, 2.0, grid.cell_size))
		root.add_child(door)


static func add_linked_doors(root: Node3D, grid: WorldGrid, room: Room) -> void:
	if room.kind == Room.Kind.MUSEUM and room.id == &"museum_entrance":
		_add_museum_entrance_doors(root, grid)
		return
	if room.linked_rooms.is_empty():
		return
	var inner_north := room.inner_origin.y
	var start_x: int = room.inner_origin.x + 1
	for i: int in room.linked_rooms.size():
		var room_id: StringName = room.linked_rooms[i]
		var template: Room = InteriorCatalog.room_template(room_id)
		var door: Node3D = DOOR_SCENE.instantiate() as Node3D
		door.name = "Link_%s" % String(room_id)
		var cell := Vector2i(start_x + i * 2, inner_north)
		if not room.is_inner(cell):
			cell = Vector2i(room.inner_origin.x, inner_north)
		door.position = grid.cell_to_world(cell)
		door.set("label", template.display_name if template else "Room")
		door.set("verb", Interaction.ENTER)
		door.set("linked_room_id", room_id)
		door.set("occupy_grid", false)
		root.add_child(door)


static func _add_museum_entrance_doors(root: Node3D, grid: WorldGrid) -> void:
	## Four wing doors from `MUSEUM_ENTRANCE_door_data` (north / west / east walls).
	for link: Dictionary in MuseumDisplay.ENTRANCE_WING_DOORS:
		var room_id: StringName = link["room"] as StringName
		var template: Room = InteriorCatalog.room_template(room_id)
		var door: Node3D = DOOR_SCENE.instantiate() as Node3D
		door.name = "Link_%s" % String(room_id)
		door.position = MuseumDisplay.gx_to_world(grid, link["sensor"] as Vector3)
		door.set("label", template.display_name if template else "Room")
		door.set("verb", Interaction.ENTER)
		door.set("linked_room_id", room_id)
		door.set("occupy_grid", false)
		door.set("auto_enter", true)
		door.set("has_linked_spawn", true)
		door.set("linked_spawn_gx", link["spawn"] as Vector3)
		door.set("linked_spawn_yaw", WorldGrid.yaw_for_furniture(link["facing"] as WorldGrid.Facing))
		_size_museum_wing_door(door, link["sensor"] as Vector3)
		root.add_child(door)


static func _size_museum_wing_door(door: Node3D, sensor_gx: Vector3) -> void:
	## Match wall gap half-width so the player cannot slip past the sensor.
	HostCollision.resize_interact_box(door, InteriorShellBuilder.museum_door_box(sensor_gx))
