class_name WorldBuilder
extends RefCounted

## Turns WorldData into Godot nodes. Kind → scene comes from WorldObjectRegistry.

## Placeholder terrain tiles are thin boxes; water is lifted so it reads above the ground.
const PLACEHOLDER_TILE_THICKNESS := 0.06
const WATER_TILE_LIFT := 0.03


## Where the water plane sits on a placeholder acre. One height per field: catalog water is
## a heightfield and generated acres vary, so this is only right while acres stay flat.
static func water_surface_y() -> float:
	return WATER_TILE_LIFT + PLACEHOLDER_TILE_THICKNESS * 0.5


func build(world: Node3D, data: WorldData, grid: WorldGrid) -> void:
	if world == null or data == null or grid == null:
		return
	WorldObjectRegistry.ensure()
	data.bake()
	grid.configure_from_world(data)
	FieldCollision.clear_caches()
	StructureOffset.apply(data)
	var terrain_root: Node3D = world.get_node_or_null("Terrain") as Node3D
	var objects_root: Node3D = world.get_node_or_null("Objects") as Node3D
	var buildings_root: Node3D = world.get_node_or_null("Buildings") as Node3D
	var characters_root: Node3D = world.get_node_or_null("Characters") as Node3D
	_paint_terrain(terrain_root, data, grid)
	for b: BuildingPlacement in data.buildings:
		_add_building(buildings_root, b, data, grid)
	for o: ObjectPlacement in data.objects:
		var parent: Node3D = _parent_for(o.kind, objects_root, buildings_root, characters_root)
		_add_object(parent, o, data, grid)
	_add_player_spawn(characters_root, data, grid)


func _parent_for(
	kind: StringName, objects_root: Node3D, buildings_root: Node3D, characters_root: Node3D
) -> Node3D:
	match WorldObjectRegistry.group(kind):
		WorldObjectRegistry.GROUP_BUILDINGS:
			return buildings_root
		WorldObjectRegistry.GROUP_CHARACTERS:
			return characters_root
		_:
			return objects_root


func _paint_terrain(root: Node3D, data: WorldData, grid: WorldGrid) -> void:
	if root == null:
		return
	var meshed: Array = []
	var has_grd: bool = _attach_acres(root, data, grid, meshed)
	## Terrain walls are kinematic circles vs segments (`revise_xz`), not physics shapes.
	FieldCollision.add_to(root, data, grid)
	_add_map_bounds(root, data, grid)
	_disable_placeholder_ground(root)
	if has_grd and meshed.is_empty():
		return
	_paint_placeholder_tiles(root, data, grid, meshed)


func _paint_placeholder_tiles(root: Node3D, data: WorldData, grid: WorldGrid, meshed: Array) -> void:
	var water_mat := _mat(Color(0.28, 0.52, 0.78, 1))
	var sand_mat := _mat(Color(0.82, 0.74, 0.52, 1))
	var path_mat := _mat(Color(0.55, 0.42, 0.28, 1))
	var stone_mat := _mat(Color(0.62, 0.61, 0.56, 1))
	var cliff_mat := _mat(Color(0.45, 0.4, 0.35, 1))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(grid.cell_size * 0.96, PLACEHOLDER_TILE_THICKNESS, grid.cell_size * 0.96)
	var cliff_mesh := BoxMesh.new()
	cliff_mesh.size = Vector3(grid.cell_size * 0.96, 0.9, grid.cell_size * 0.96)
	var skip_meshed: bool = meshed.size() == TownFieldGenerator.BLOCK_TOTAL
	for x: int in data.columns:
		for z: int in data.rows:
			if skip_meshed:
				var bx: int = x / WorldGenerator.UT + 1
				var bz: int = z / WorldGenerator.UT + 1
				var bnum: int = bz * TownFieldGenerator.BLOCK_X + bx
				if bnum >= 0 and bnum < meshed.size() and int(meshed[bnum]) != 0:
					continue
			var cell := Vector2i(x, z)
			var t: WorldGrid.Terrain = data.terrain_at(cell)
			var pos: Vector3 = grid.cell_to_world(cell)
			var elev_y: float = FieldCollision.height_at(data, cell, false)
			if not FieldCollision.has_floor(elev_y):
				elev_y = float(data.elevation_at(cell)) * FieldCatalog.ACRE_STEP_METERS
			pos.y += elev_y
			match t:
				WorldGrid.Terrain.WATER:
					root.add_child(_tile(mesh, water_mat, pos + Vector3(0, WATER_TILE_LIFT, 0)))
				WorldGrid.Terrain.SAND:
					root.add_child(_tile(mesh, sand_mat, pos + Vector3(0, 0.02, 0)))
				WorldGrid.Terrain.PATH:
					root.add_child(_tile(mesh, path_mat, pos + Vector3(0, 0.02, 0)))
				WorldGrid.Terrain.STONE:
					root.add_child(_tile(mesh, stone_mat, pos + Vector3(0, 0.02, 0)))
				WorldGrid.Terrain.CLIFF:
					root.add_child(_tile(cliff_mesh, cliff_mat, pos + Vector3(0, 0.45, 0)))


func _attach_acres(root: Node3D, data: WorldData, grid: WorldGrid, meshed: Array) -> bool:
	if (
		data.acre_visuals.size() == TownFieldGenerator.BLOCK_TOTAL
		and data.acre_types.size() == TownFieldGenerator.BLOCK_TOTAL
	):
		var acres_root := Node3D.new()
		acres_root.name = "Acres"
		root.add_child(acres_root)
		meshed.resize(TownFieldGenerator.BLOCK_TOTAL)
		meshed.fill(0)
		var placed_mesh := false
		## Full 7×10: FG (bx 1–5, bz 1–6), side cliffs (`grd_s_e2/e3_*`), north border
		## (`e1/e4/e5`), and south ocean / island rows (`grd_s_o_*`, `il`/`ir`).
		## Placement still uses FG-relative min-corners (`mFI_BkNum2WposXZ`).
		for bz: int in TownFieldGenerator.BLOCK_Z:
			for bx: int in TownFieldGenerator.BLOCK_X:
				var bnum: int = bz * TownFieldGenerator.BLOCK_X + bx
				var origin_cell := Vector2i((bx - 1) * WorldGenerator.UT, (bz - 1) * WorldGenerator.UT)
				var pos: Vector3 = grid.cell_corner(origin_cell)
				if data.acre_heights.size() == TownFieldGenerator.BLOCK_TOTAL:
					pos.y += float(data.acre_heights[bnum]) * FieldCatalog.ACRE_STEP_METERS
				var visual := StringName(data.acre_visuals[bnum])
				if visual == &"":
					continue
				var host := Node3D.new()
				host.name = "acre_%d_%d" % [bx, bz]
				host.set_meta("visual_id", visual)
				host.position = pos
				if GeneratedVisual.attach(host, visual) == null:
					host.free()
					continue
				acres_root.add_child(host)
				meshed[bnum] = 1
				placed_mesh = true
		return placed_mesh
	if data.acre_visual != &"":
		var host := Node3D.new()
		host.name = "Acre"
		host.set_meta("visual_id", data.acre_visual)
		host.position = grid.cell_corner(Vector2i(0, 0))
		root.add_child(host)
		if GeneratedVisual.attach(host, data.acre_visual) == null:
			root.remove_child(host)
			host.free()
			return false
		return true
	return false


func _add_map_bounds(root: Node3D, data: WorldData, grid: WorldGrid) -> void:
	var min_c: Vector3 = grid.cell_corner(Vector2i(0, 0))
	var size_x: float = float(data.columns) * grid.cell_size
	var size_z: float = float(data.rows) * grid.cell_size
	var wall_h: float = FieldCatalog.ACRE_STEP_METERS * 4.0
	var thick: float = 2.0
	var cx: float = min_c.x + size_x * 0.5
	var cz: float = min_c.z + size_z * 0.5
	var mid_y: float = wall_h * 0.5
	root.add_child(_bound_wall(Vector3(min_c.x - thick * 0.5, mid_y, cz), Vector3(thick, wall_h, size_z)))
	root.add_child(_bound_wall(Vector3(min_c.x + size_x + thick * 0.5, mid_y, cz), Vector3(thick, wall_h, size_z)))
	root.add_child(_bound_wall(Vector3(cx, mid_y, min_c.z - thick * 0.5), Vector3(size_x, wall_h, thick)))
	root.add_child(_bound_wall(Vector3(cx, mid_y, min_c.z + size_z + thick * 0.5), Vector3(size_x, wall_h, thick)))


func _bound_wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "MapBound"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body


func _disable_placeholder_ground(root: Node3D) -> void:
	var mesh: Node = root.get_node_or_null("Ground/MeshInstance3D")
	if mesh is MeshInstance3D:
		(mesh as MeshInstance3D).visible = false
	var ground: Node = root.get_node_or_null("Ground")
	if ground is CollisionObject3D:
		(ground as CollisionObject3D).collision_layer = 0
	var ground_shape: Node = root.get_node_or_null("Ground/CollisionShape3D")
	if ground_shape is CollisionShape3D:
		(ground_shape as CollisionShape3D).disabled = true


func _add_building(root: Node3D, placement: BuildingPlacement, data: WorldData, grid: WorldGrid) -> void:
	if root == null or placement == null:
		return
	var node: Node3D = _instance_building(placement)
	if node == null:
		return
	var visual_id: StringName = placement.visual_id
	## Live Nook visual follows upgrade level even if WorldData still has shop1.
	if placement.id == &"acre_shop" and Game != null and Game.shops != null:
		visual_id = Game.shops.nook_visual_id()
	_apply_common(node, placement.id, placement.footprint, placement.facing, placement.occupy_grid, visual_id)
	if "occupant_id" in node and placement.resident_id != &"":
		node.set("occupant_id", placement.resident_id)
	if "label" in node and placement.label != "":
		node.set("label", placement.label)
	if "door_verb" in node and placement.door_verb != &"":
		node.set("door_verb", placement.door_verb)
	_place_node(
		root, node, placement.cell, placement.footprint, placement.facing, data, grid, placement.actor_shift, placement.mesh_facing
	)
	if placement.occupy_grid:
		grid.place(
			placement.id,
			placement.cell,
			placement.footprint,
			placement.facing,
			WorldObjectRegistry.place_kind(placement.kind)
		)


func _add_object(root: Node3D, placement: ObjectPlacement, data: WorldData, grid: WorldGrid) -> void:
	if root == null or placement == null:
		return
	var persist: StringName = placement.persist_id if placement.persist_id != &"" else placement.id
	if persist != &"" and Game.is_interactable_removed(persist):
		return
	var node: Node3D = _instance(placement.kind)
	if node == null:
		return
	_apply_common(node, placement.id, placement.footprint, placement.facing, placement.occupy_grid, placement.visual_id)
	if "persist_id" in node:
		node.set("persist_id", persist)
	if "message" in node and placement.message != "":
		node.set("message", placement.message)
	if "label" in node and placement.message != "":
		node.set("label", placement.message)
	_apply_payload(node, placement)
	_place_node(root, node, placement.cell, placement.footprint, placement.facing, data, grid)
	if not placement.occupy_grid:
		return
	grid.place(
		placement.id,
		placement.cell,
		placement.footprint,
		placement.facing,
		WorldObjectRegistry.place_kind(placement.kind)
	)


func _add_player_spawn(root: Node3D, data: WorldData, grid: WorldGrid) -> void:
	if root == null:
		return
	var existing: Node = root.get_node_or_null("PlayerSpawn")
	var marker: Marker3D
	if existing is Marker3D:
		marker = existing as Marker3D
	else:
		marker = Marker3D.new()
		marker.name = "PlayerSpawn"
		root.add_child(marker)
	var spawn: SpawnPoint = data.player_spawn()
	var pos: Vector3 = grid.cell_to_world(spawn.cell)
	pos.y = FieldCollision.ground_y(data, spawn.cell)
	marker.position = pos
	marker.rotation.y = spawn.yaw


func _place_node(
	root: Node3D,
	node: Node3D,
	cell: Vector2i,
	footprint: Vector2i,
	facing: WorldGrid.Facing,
	data: WorldData,
	grid: WorldGrid,
	actor_shift: Vector2 = Vector2.ZERO,
	mesh_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
) -> void:
	var pos: Vector3 = grid.footprint_center(cell, footprint, facing)
	pos += Vector3(actor_shift.x, 0.0, actor_shift.y) * grid.cell_size
	if data != null:
		## Height at the actor stand unit (`mCoBG_GetBgY_OnlyCenter_FromWpos2`), not the NW cell.
		var stand: Vector2i = grid.world_to_cell(pos)
		if not data.is_in_bounds(stand):
			stand = cell
		pos.y = FieldCollision.ground_y(data, stand)
	node.position = pos
	root.add_child(node)
	if node.has_method("apply_grid_yaw"):
		node.call("apply_grid_yaw", mesh_facing)


func _apply_common(
	node: Node,
	id: StringName,
	footprint: Vector2i,
	facing: WorldGrid.Facing,
	occupy_grid: bool,
	visual_id: StringName
) -> void:
	if id != &"":
		node.name = String(id)
	if "occupant_id" in node:
		node.set("occupant_id", id)
	if "footprint" in node:
		node.set("footprint", footprint)
	if "grid_facing" in node:
		node.set("grid_facing", facing)
	if "occupy_grid" in node:
		node.set("occupy_grid", occupy_grid)
	if "visual_id" in node and visual_id != &"":
		node.set("visual_id", visual_id)


func _apply_payload(node: Node, placement: ObjectPlacement) -> void:
	if placement.payload == null:
		return
	if placement.payload is PlantData:
		node.set("plant", placement.payload)
	elif placement.payload is FurnitureData:
		node.set("data", placement.payload)
	elif placement.payload is VillagerData:
		node.set("data", placement.payload)
	elif placement.payload is ItemData:
		node.set("item", placement.payload)


func _instance(kind: StringName) -> Node3D:
	var path: String = WorldObjectRegistry.scene_path(kind)
	if path.is_empty():
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var node: Node = packed.instantiate()
	if node is Node3D:
		return node as Node3D
	node.queue_free()
	return null


func _instance_building(placement: BuildingPlacement) -> Node3D:
	var path: String = WorldObjectRegistry.scene_for_building(placement.id, placement.kind)
	if path.is_empty():
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var node: Node = packed.instantiate()
	if node is Node3D:
		return node as Node3D
	node.queue_free()
	return null


func _tile(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var vis := MeshInstance3D.new()
	vis.mesh = mesh
	vis.material_override = mat
	vis.position = pos
	return vis


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
