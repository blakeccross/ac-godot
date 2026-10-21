class_name HoleUse
extends RefCounted

## Dig / fill hole FG. Original: `DIG_SCOOP` writes `HOLE00`–`HOLE24`; `FILL_SCOOP` restores empty.
## Not an autoload. The hole scene only presents fill. The mesh follows the unit's slope
## (`HoleShape`); a shape with no hole mesh digs (clods and all) but leaves no hole.

const SCENE := "res://scenes/world/hole.tscn"
## Same −1 GX lift as other `bg_item` props (`FieldCollision.FG_GROUND_DIST`).
const GROUND_DIST := FieldCollision.FG_GROUND_DIST


## `Put_Hole_Dig_scoop` (frame 20) after `SetSound_Dig_scoop` (frame 15).
const HOLE_SHOWS_AFTER := 5.0 / DecompTime.FRAME_HZ
## `bIT_actor_dig_hole_effect_entry(…, 12, …)`: the hole grows in over 12 frames.
const HOLE_GROW_SECONDS := 12.0 / DecompTime.FRAME_HZ

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


static func dig(ctx: InteractionContext, cell: Vector2i, play_scoop_se: bool = true) -> bool:
	var grid: WorldGrid = _grid(ctx)
	if not can_open(grid, cell):
		return false
	## No `mCoBG_hole_data` row for this slope: the dig plays, no hole entry is made.
	if _number(ctx.world if ctx != null else null, cell) < 0:
		_notify_bugs(ctx, cell)
		if play_scoop_se and ctx != null and ctx.actor != null:
			PlayerSe.scoop_dig(ctx.actor)
		return true
	var pid: StringName = persist_id(cell)
	Game.mark_hole(pid)
	if not grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT):
		Game.clear_hole(pid)
		return false
	var hole: Node3D = _instance(ctx.world if ctx != null else null, grid, cell, pid)
	## `Put_Hole_Dig_scoop`: the unit is a hole from the dig's frame 15, but the hole itself
	## shows at frame 20, once the clods are up, and grows to full size.
	if hole != null and hole.is_inside_tree():
		hole.scale = Vector3.ZERO
		var grow: Tween = hole.create_tween()
		grow.tween_interval(HOLE_SHOWS_AFTER)
		grow.tween_property(hole, "scale", Vector3.ONE, HOLE_GROW_SECONDS)
	_notify_bugs(ctx, cell)
	if play_scoop_se and ctx != null and ctx.actor != null:
		PlayerSe.scoop_dig(ctx.actor)
	return true


static func fill(host: Node, ctx: InteractionContext) -> bool:
	if host == null:
		return false
	## `scoop_umeru` is scheduled from the fill clip; host is the SE anchor if needed.
	## `Player_actor_set_viblation_Fill_scoop`.
	GameConfig.rumble(GameConfig.FILL)
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
	for key: String in Game.town.hole_interactables:
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
	hole.set("visual_id", HoleShape.visual_for(_number(world, cell)))
	objects.add_child(hole)
	var pos: Vector3 = grid.cell_to_world(cell)
	if "layout" in world and world.layout != null:
		pos.y = FieldCollision.ground_y(world.layout as WorldData, cell, GROUND_DIST)
	if hole.is_inside_tree():
		hole.global_position = pos
	else:
		hole.position = pos
	return hole


## `HoleShape` row for the unit; 0 where the world has no field layout (tests, rooms).
static func _number(world: Node, cell: Vector2i) -> int:
	if world == null or not ("layout" in world) or not (world.layout is WorldData):
		return 0
	return HoleShape.number_for(world.layout as WorldData, cell)


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
		## `aINS_PL_ACT_DIG_SCOOP` — wakes a mole cricket buried in this unit.
		field.notify_field_action(BugActor.PlAct.DIG_SCOOP, cell)
