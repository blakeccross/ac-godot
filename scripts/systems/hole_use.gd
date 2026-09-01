class_name HoleUse
extends RefCounted

## Dig / fill hole FG. Original: `DIG_SCOOP` writes `HOLE00`–`HOLE24`; `FILL_SCOOP` restores empty.
## Not an autoload. The hole scene only presents fill.

const VISUAL := &"HOLE00"
const SCENE := "res://scenes/world/hole.tscn"
## `mCoBG_GetBgY_OnlyCenter_FromWpos2(*pos, -1.0f)` — 1 GX above the unit so the fan is not coplanar with the acre.
const GROUND_DIST := -FieldCatalog.GX_TO_METERS


static func persist_id(cell: Vector2i) -> StringName:
	return StringName("hole_%d_%d" % [cell.x, cell.y])


static func cell_from_persist(id: StringName) -> Vector2i:
	var s := String(id)
	if not s.begins_with("hole_"):
		return Vector2i(-1, -1)
	var parts: PackedStringArray = s.substr(5).split("_")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


static func can_open(grid: WorldGrid, cell: Vector2i) -> bool:
	if grid == null or not grid.is_in_bounds(cell):
		return false
	var terrain: WorldGrid.Terrain = grid.terrain_at(cell)
	if (
		terrain != WorldGrid.Terrain.GRASS
		and terrain != WorldGrid.Terrain.SOIL
		and terrain != WorldGrid.Terrain.SAND
	):
		return false
	return not grid.is_occupied(cell)


static func dig(ctx: InteractionContext, cell: Vector2i) -> bool:
	var grid: WorldGrid = _grid(ctx)
	if not can_open(grid, cell):
		return false
	var pid: StringName = persist_id(cell)
	Game.mark_hole(pid)
	if not grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT):
		Game.clear_hole(pid)
		return false
	_instance(ctx.world if ctx != null else null, grid, cell, pid)
	_notify_bugs(ctx, cell)
	return true


static func fill(host: Node, ctx: InteractionContext) -> bool:
	if host == null:
		return false
	var pid: StringName = _host_persist(host)
	Game.clear_hole(pid)
	var grid: WorldGrid = _grid(ctx)
	if grid != null:
		grid.remove(pid)
	if ctx != null:
		ctx.release_occupant(pid)
	host.queue_free()
	return true


static func restore(world: Node, grid: WorldGrid) -> void:
	if world == null or grid == null:
		return
	for key: String in Game.hole_interactables:
		var pid := StringName(key)
		var cell: Vector2i = cell_from_persist(pid)
		if not can_open(grid, cell):
			continue
		if not grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT):
			continue
		_instance(world, grid, cell, pid)


static func _instance(world: Node, grid: WorldGrid, cell: Vector2i, pid: StringName) -> Node3D:
	if world == null or grid == null:
		return null
	var objects: Node = world.get_node_or_null("Objects")
	if objects == null:
		return null
	if not ResourceLoader.exists(SCENE):
		return null
	var packed: PackedScene = load(SCENE) as PackedScene
	if packed == null:
		return null
	var hole: Node3D = packed.instantiate() as Node3D
	if hole == null:
		return null
	hole.set("persist_id", pid)
	hole.set("occupant_id", pid)
	hole.set("visual_id", VISUAL)
	objects.add_child(hole)
	var pos: Vector3 = grid.cell_to_world(cell)
	if "layout" in world and world.layout != null:
		pos.y = FieldCollision.ground_y(world.layout as WorldData, cell, GROUND_DIST)
	if hole.is_inside_tree():
		hole.global_position = pos
	else:
		hole.position = pos
	return hole


static func _host_persist(host: Node) -> StringName:
	var persist: Variant = host.get("persist_id")
	if persist is StringName and persist != &"":
		return persist as StringName
	var occupant: Variant = host.get("occupant_id")
	if occupant is StringName:
		return occupant as StringName
	return &""


static func _grid(ctx: InteractionContext) -> WorldGrid:
	if ctx == null or ctx.world == null:
		return null
	var value: Variant = ctx.world.get("grid")
	return value as WorldGrid


static func _notify_bugs(ctx: InteractionContext, cell: Vector2i) -> void:
	if ctx == null or ctx.world == null:
		return
	var field: BugField = ctx.world.get("bugs") as BugField
	if field != null:
		field.notify_player_action(cell)
