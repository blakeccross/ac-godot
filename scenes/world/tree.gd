extends StaticBody3D

## Outdoor tree. Shake / chop / stump rules live in TreeUse; this scene presents them.

const PICKUP_SCENE := preload("res://scenes/world/item_pickup.tscn")
const STUMP_VISUAL := &"TREE_STUMP004"
const SHAKE_AMP := 0.08
const CHOP_AMP := 0.14
const FALL_SEC := 0.55

@export var plant: PlantData
@export var occupant_id: StringName = &""
@export var persist_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.PLANT
@export var visual_id: StringName = &"TREE_APPLE_FRUIT"

var _use: TreeUse
var _motion: Tween
var _felling: bool = false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("plant")
	if Game.is_interactable_removed(_persist()):
		queue_free()
		return
	if Game.is_stump(_persist()):
		_ensure_use()
		_present_stump()
		return
	if _persist() != &"" and plant != null:
		PlantGrowth.ensure(_persist(), plant, visual_id, _cell())
	apply_growth()
	HostCollision.apply_cylinder(self, footprint, HostCollision.CELL)


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	var use: TreeUse = _ensure_use()
	if _felling:
		return []
	var label: String = plant.display_name if plant else "Tree"
	if use.stage == TreeUse.Stage.STUMP:
		if ToolUse.has(ctx, ToolData.Kind.SHOVEL):
			return [Interaction.of(Interaction.DIG, "Dig stump", 8, &"ply_1_dig1")]
		return []
	var actions: Array[Interaction] = [
		Interaction.of(Interaction.SHAKE, "Shake %s" % label, 10, &"ply_1_shake1")
	]
	if ToolUse.has(ctx, ToolData.Kind.AXE):
		actions.append(Interaction.of(Interaction.CHOP, "Chop %s" % label, 18, &"ply_1_axe_swing1"))
	return actions


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null:
		return false
	var use: TreeUse = _ensure_use()
	if action.id == Interaction.SHAKE:
		return _on_shake(use, ctx)
	if action.id == Interaction.CHOP:
		return _on_chop(use, ctx)
	if action.id == Interaction.DIG:
		return _on_dig_stump(use, ctx)
	return false


func _on_shake(use: TreeUse, ctx: InteractionContext) -> bool:
	var out: TreeUse.Outcome = use.shake()
	if not out.shook:
		return false
	_stress_bugs_at(ctx)
	_drop_fruit(out.dropped_fruit, ctx)
	if out.dropped_fruit > 0:
		PlantGrowth.take_fruit(_persist())
		apply_growth()
	else:
		Game.post_notice("The tree rustles.")
	_play_shake(false)
	return true


func _on_chop(use: TreeUse, ctx: InteractionContext) -> bool:
	if not ToolUse.has(ctx, ToolData.Kind.AXE):
		return false
	var out: TreeUse.Outcome = use.chop()
	if not out.shook and not out.felled:
		return false
	_drop_fruit(out.dropped_fruit, ctx)
	if out.dropped_fruit > 0:
		PlantGrowth.take_fruit(_persist())
		if not out.felled:
			apply_growth()
	if out.felled:
		PlantGrowth.clear(_persist())
		Game.mark_stump(_persist())
		_play_fall(ctx)
	else:
		_play_shake(true)
	return true


func _on_dig_stump(use: TreeUse, ctx: InteractionContext) -> bool:
	if use.stage != TreeUse.Stage.STUMP:
		return false
	if not ToolUse.has(ctx, ToolData.Kind.SHOVEL):
		return false
	Game.post_notice("You dig up the stump.")
	var pid: StringName = _persist()
	PlantGrowth.clear(pid)
	Game.clear_stump(pid)
	if pid != &"":
		Game.mark_interactable_removed(pid)
	var cell := Vector2i(-1, -1)
	var grid: WorldGrid = _grid(ctx)
	if grid != null:
		cell = grid.world_to_cell(global_position)
	if ctx != null:
		ctx.release_occupant(pid)
	HoleUse.dig(ctx, cell)
	queue_free()
	return true


func apply_growth() -> void:
	if plant == null or Game.is_stump(_persist()) or _felling:
		return
	var rec: Dictionary = PlantGrowth.record(_persist())
	if not rec.is_empty():
		var pipe: PlantGrowth.Pipeline = PlantGrowth.pipeline(rec, plant)
		visual_id = PlantGrowth.visual_id(rec, plant)
		var pivot := get_node_or_null("VisualPivot") as Node3D
		if pivot != null:
			pivot.scale = Vector3.ONE
		if _use == null:
			_ensure_use()
		else:
			_use.sync_growth(
				plant, visual_id, PlantGrowth.tree_size(pipe), PlantGrowth.fruit_ready(rec, plant)
			)
	_present_live_visual()
	if _use == null:
		_ensure_use()


func refresh_seasonal_visual() -> void:
	## Season mesh infix (`obj_s/f/w_*`) without replaying growth math.
	if _felling:
		return
	if Game.is_stump(_persist()):
		_present_stump()
		return
	apply_growth()


func _present_live_visual() -> void:
	GeneratedVisual.detach(self)
	var vis: Node3D = GeneratedVisual.attach(self, visual_id)
	var pivot := get_node_or_null("VisualPivot") as Node3D
	if vis != null and pivot != null and is_inside_tree():
		vis.reparent(pivot)


func _ensure_use() -> TreeUse:
	if _use != null:
		return _use
	_use = TreeUse.new()
	var rec: Dictionary = PlantGrowth.record(_persist())
	var as_stump: bool = Game.is_stump(_persist())
	if rec.is_empty():
		_use.configure(plant, visual_id, as_stump)
		return _use
	var pipe: PlantGrowth.Pipeline = PlantGrowth.pipeline(rec, plant)
	_use.configure(
		plant,
		visual_id,
		as_stump,
		PlantGrowth.tree_size(pipe),
		PlantGrowth.fruit_ready(rec, plant)
	)
	return _use


func _persist() -> StringName:
	return persist_id if persist_id != &"" else occupant_id


func _cell() -> Vector2i:
	var world: Node = get_tree().get_first_node_in_group("world") if get_tree() != null else null
	if world != null and "grid" in world and world.grid != null:
		return world.grid.world_to_cell(global_position)
	return Vector2i.ZERO


func _drop_fruit(count: int, ctx: InteractionContext) -> void:
	if count <= 0 or plant == null or plant.fruit == null or ctx == null or ctx.world == null:
		return
	var grid: WorldGrid = _grid(ctx)
	if grid == null:
		return
	var objects: Node = ctx.world.get_node_or_null("Objects")
	if objects == null:
		return
	var origin: Vector2i = grid.world_to_cell(global_position)
	var cells: Array[Vector2i] = TreeUse.pick_drop_cells(origin, grid, count)
	var i: int = 0
	for cell: Vector2i in cells:
		var pickup: Node3D = PICKUP_SCENE.instantiate() as Node3D
		pickup.set("item", plant.fruit)
		var drop_id := StringName("%s_drop_%d" % [String(_persist()), i])
		pickup.set("persist_id", drop_id)
		pickup.set("occupant_id", drop_id)
		objects.add_child(pickup)
		var pos: Vector3 = grid.cell_to_world(cell)
		if "layout" in ctx.world and ctx.world.layout != null:
			pos.y = FieldCollision.ground_y(ctx.world.layout, cell)
		pickup.global_position = pos
		grid.place(
			drop_id, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM
		)
		i += 1


func _grid(ctx: InteractionContext) -> WorldGrid:
	if ctx == null or ctx.world == null:
		return null
	if "grid" in ctx.world:
		return ctx.world.grid as WorldGrid
	return null


func _play_shake(strong: bool) -> void:
	var pivot := get_node_or_null("VisualPivot") as Node3D
	if pivot == null or not is_inside_tree():
		return
	_kill_motion()
	var amp: float = CHOP_AMP if strong else SHAKE_AMP
	pivot.rotation = Vector3.ZERO
	_motion = create_tween()
	_motion.tween_property(pivot, "rotation:z", amp, 0.05)
	_motion.tween_property(pivot, "rotation:z", -amp, 0.08)
	_motion.tween_property(pivot, "rotation:z", amp * 0.55, 0.07)
	_motion.tween_property(pivot, "rotation:z", -amp * 0.3, 0.07)
	_motion.tween_property(pivot, "rotation:z", 0.0, 0.08)


func _play_fall(ctx: InteractionContext) -> void:
	var pivot := get_node_or_null("VisualPivot") as Node3D
	if pivot == null or not is_inside_tree():
		_present_stump()
		return
	_felling = true
	_kill_motion()
	var axis := Vector3.RIGHT
	if ctx != null and ctx.actor != null:
		var away: Vector3 = global_position - ctx.actor.global_position
		away.y = 0.0
		if away.length_squared() > 0.0001:
			axis = Vector3.UP.cross(away.normalized())
	pivot.rotation = Vector3.ZERO
	_motion = create_tween()
	_motion.tween_property(pivot, "rotation", axis * (PI * 0.5), FALL_SEC).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_IN)
	_motion.finished.connect(_present_stump, CONNECT_ONE_SHOT)


func _present_stump() -> void:
	_felling = false
	_kill_motion()
	Game.mark_stump(_persist())
	if _use != null:
		_use.stage = TreeUse.Stage.STUMP
		_use.hits_left = 0
	var pivot := get_node_or_null("VisualPivot") as Node3D
	if pivot != null:
		pivot.rotation = Vector3.ZERO
		pivot.scale = Vector3.ONE
		pivot.visible = false
	GeneratedVisual.detach(self)
	var stump_vis: Node3D = GeneratedVisual.attach(self, STUMP_VISUAL)
	var stump := get_node_or_null("Stump") as Node3D
	if stump != null:
		stump.visible = stump_vis == null
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		col.position.y = 0.2
		if col.shape is CylinderShape3D:
			var shape := (col.shape as CylinderShape3D).duplicate() as CylinderShape3D
			shape.height = 0.4
			shape.radius = 0.22
			col.shape = shape


func _kill_motion() -> void:
	if _motion != null and is_instance_valid(_motion):
		_motion.kill()
	_motion = null


func _stress_bugs_at(ctx: InteractionContext) -> void:
	if ctx == null or ctx.world == null:
		return
	var field: BugField = ctx.world.get("bugs") as BugField
	if field == null:
		return
	var grid: WorldGrid = ctx.world.get("grid") as WorldGrid
	if grid == null:
		return
	field.notify_player_action(_cell())
