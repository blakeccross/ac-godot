extends StaticBody3D

## Outdoor tree. Shake / chop / stump rules live in TreeUse; this scene presents them.
## Shake timing matches `mPlayer_ANIM_SHAKE1` frame 10; sway matches EffectBG shakeL/S.

const STUMP_VISUAL := &"TREE_STUMP004"
## `mCoBG_MakeOneColumnCollisionData`: a grown stump (`TREE_STUMP004`) is an 18 GX column
## (the `*_STUMP001` saplings' stumps would be 10). Trees are 19 (`HostCollision`).
const STUMP_RADIUS := 18.0 * FieldCatalog.GX_TO_METERS
## Player shake effect lands on frame 10 (`Player_actor_SetEffect_Shake_tree`).
const SHAKE_EFFECT_FRAME := 10.0
## `STATUS_FOR_BEE_ATTACK` at frame 29.5 — delay from the effect mark (frame 10).
const BEE_ATTACKABLE_AFTER_EFFECT := (29.5 - SHAKE_EFFECT_FRAME) / DecompTime.FRAME_HZ
## Bee birth retry window starts 5 frames after the effect (`bee_spawn_timer = 5`).
const BEE_SPAWN_DELAY := 5.0 / DecompTime.FRAME_HZ
## EffectBG sets `frame_control.speed = 0.5` on a 60 Hz actor tick (= 30 anim fps).
## Pipeline / player clips already sample at 30 fps, so Godot dt is frames / 30 — not / 15.
## `eYoung_Tree_dw`: cedar / palm saplings roll about a point above the trunk base.
const YOUNG_PIVOT_PALM_GX := 5.0
const YOUNG_PIVOT_CEDAR_GX := 15.0

const XMAS_TREE_LIGHTS := &"obj_x_tree5_light"
const XMAS_CEDAR_LIGHTS := &"obj_x_ceder5_light"
@export var plant: PlantData
@export var occupant_id: StringName = &""
@export var persist_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.PLANT
@export var visual_id: StringName = &"TREE_APPLE_FRUIT"

## `mPlib_Check_tree_shaken_big` / `_little`: a full shake, or the player bumping it.
signal shaken(big: bool)

var _use: TreeUse
var _motion: Tween
var _felling: bool = false
var _pending_bees: BeeSwarm = null


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
			return [Interaction.of(Interaction.DIG, "Dig stump", 8, &"ply_1_dig1", 15.0)]
		return []
	var actions: Array[Interaction] = [
		Interaction.of(
			Interaction.SHAKE, "Shake %s" % label, 10, &"ply_1_shake1", SHAKE_EFFECT_FRAME
		)
	]
	if ToolUse.has(ctx, ToolData.Kind.AXE):
		## Furi @10 (PlayerSe clip marks); cut @15 when interact fires.
		actions.append(
			Interaction.of(Interaction.CHOP, "Chop %s" % label, 18, &"ply_1_axe_swing1", 15.0)
		)
	return actions


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null:
		return false
	var use: TreeUse = _ensure_use()
	if action.id == Interaction.SHAKE:
		return await _on_shake(use, ctx)
	if action.id == Interaction.CHOP:
		return _on_chop(use, ctx)
	if action.id == Interaction.DIG:
		return _on_dig_stump(use, ctx)
	return false


## `IS_ITEM_COLLIDEABLE_TREE`: every growth stage, not the stump.
func can_bump() -> bool:
	return not _felling and _ensure_use().stage != TreeUse.Stage.STUMP


## `Player_actor_check_little_shake_tree` hit: EffectBG SHAKE_SMALL, plus the touch SE for
## med / large / full trees only (`IS_ITEM_SHAKEABLE_TREE`).
func bump() -> void:
	_play_shake(false)
	shaken.emit(false)
	if _ensure_use().size != TreeUse.Size.S0:
		PlayerSe.tree_touch(self)


func _on_shake(use: TreeUse, ctx: InteractionContext) -> bool:
	var out: TreeUse.Outcome = use.shake()
	if not out.shook:
		return false
	if ctx != null and ctx.actor != null and ctx.actor.has_method("note_big_tree_shake"):
		ctx.actor.call("note_big_tree_shake", _cell())
	PlayerSe.tree_yurasu(self)
	shaken.emit(true)
	_stress_bugs_at(ctx)
	var had_drops: bool = not out.drops.is_empty() or out.dropped_fruit > 0
	_emit_drops(out, ctx)
	if had_drops:
		if out.dropped_fruit > 0:
			PlantGrowth.take_fruit(_persist())
		PlantGrowth.clear_shake_content(_persist())
		apply_growth()
	else:
		Game.post_notice("The tree rustles.")
	_play_shake(true)
	if out.spawn_bees:
		_arm_bees(ctx)
	elif _world_has_bees(ctx):
		## Existing swarm may sting once the shake clip reaches frame 29.5.
		_schedule_bee_attackable(BEE_ATTACKABLE_AFTER_EFFECT)
	return true


func _on_chop(use: TreeUse, ctx: InteractionContext) -> bool:
	if not ToolUse.has(ctx, ToolData.Kind.AXE):
		return false
	var out: TreeUse.Outcome = use.chop()
	if not out.shook and not out.felled:
		return false
	PlayerSe.axe_cut(self)
	ToolUse.wear_axe(ctx, false)
	_emit_drops(out, ctx)
	if out.dropped_fruit > 0:
		PlantGrowth.take_fruit(_persist())
	if not out.drops.is_empty():
		PlantGrowth.clear_shake_content(_persist())
	if out.dropped_fruit > 0 and not out.felled:
		apply_growth()
	elif not out.drops.is_empty() and not out.felled:
		apply_growth()
	if out.spawn_bees:
		_arm_bees(ctx)
	if out.felled:
		PlantGrowth.clear(_persist())
		Game.mark_stump(_persist())
		_play_fall(ctx)
	else:
		_play_shake(true, false)
	return true


func _on_dig_stump(use: TreeUse, ctx: InteractionContext) -> bool:
	if use.stage != TreeUse.Stage.STUMP:
		return false
	if not ToolUse.has(ctx, ToolData.Kind.SHOVEL):
		return false
	PlayerSe.stump_dig(self)
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
	HoleUse.dig(ctx, cell, false)
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
		var content: TreeUse.Content = PlantGrowth.shake_content_of(rec)
		if _use == null:
			_ensure_use()
		else:
			_use.sync_growth(
				plant,
				visual_id,
				PlantGrowth.tree_size(pipe),
				PlantGrowth.fruit_ready(rec, plant),
				content
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
	if vis != null and PlantGrowth.is_gold(_persist()):
		_tint_gold(vis)
	if vis != null and PlantGrowth.has_lights(PlantGrowth.record(_persist())):
		_add_lights(vis)
	var pivot := get_node_or_null("VisualPivot") as Node3D
	if vis != null and pivot != null and is_inside_tree():
		vis.reparent(pivot)


## `tree4_light_list` / `cedar5_light_list`: the December lights, drawn in the tree's own
## frame (same scale and origin).
func _add_lights(vis: Node3D) -> void:
	var id: StringName = XMAS_CEDAR_LIGHTS if plant != null and plant.id == &"cedar_tree" else XMAS_TREE_LIGHTS
	var lights: Node3D = GeneratedVisual.instantiate_raw(id)
	if lights == null:
		return
	lights.name = "XmasLights"
	vis.add_child(lights)
	var cell: Vector2i = _cell()
	XmasLights.attach(lights, cell.x * 7 + cell.y * 13)


## `golden_tree_pal`: the golden tree draws the hardwood with its own palette.
func _tint_gold(vis: Node) -> void:
	for node: Node in vis.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for i: int in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(i) as StandardMaterial3D
			if mat == null:
				continue
			var own := mat.duplicate() as StandardMaterial3D
			own.albedo_color = own.albedo_color * PlantGrowth.GOLD_TINT
			mesh.set_surface_override_material(i, own)


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
		PlantGrowth.fruit_ready(rec, plant),
		PlantGrowth.shake_content_of(rec)
	)
	return _use


## `mMsr_CheckAroundTree`: a grown tree with nothing hidden in it, and fruit trees only while
## the fruit is on (`TREE`, `TREE_*_FRUIT`, money trees, `CEDAR_TREE`, `GOLD_TREE`).
func can_host_mushroom() -> bool:
	if plant == null or plant.kind == PlantData.Kind.FLOWER or _felling:
		return false
	var use: TreeUse = _ensure_use()
	if use.size != TreeUse.Size.FULL or use.stage == TreeUse.Stage.STUMP:
		return false
	match use.content:
		TreeUse.Content.BELLS, TreeUse.Content.BEES, TreeUse.Content.FURNITURE:
			return false
	if plant.fruit != null or use.palm_fruit:
		return use.stage == TreeUse.Stage.FRUITING
	return true


## `aFSN_moving`'s FG check: a grown tree with nothing on it (`TREE`, `*_NOFRUIT_*`,
## `CEDAR_TREE`, `GOLD_TREE`) is where a balloon snags.
func can_catch_balloon() -> bool:
	if _felling or Game.is_stump(_persist()):
		return false
	var use: TreeUse = _ensure_use()
	return use.size == TreeUse.Size.FULL and use.stage == TreeUse.Stage.BARE


## Where a snagged balloon's present sits (GX from the unit centre): cedars higher and further forward.
func balloon_perch() -> Vector3:
	var gx: Vector3 = Vector3(0.0, 100.0, 20.0) if _family() == PlantData.Family.CEDAR else Vector3(-2.5, 97.5, 7.5)
	var world := World.find(get_tree())
	var base: Vector3 = global_position
	if world != null and world.grid != null:
		base = world.grid.cell_to_world(_cell())
		base.y = global_position.y
	return base + gx * FieldCatalog.GX_TO_METERS


## `fruit_set(ITM_PRESENT)`: the balloon's present falls out like fruit (top of the crown).
func drop_present(item: ItemData) -> void:
	var world := World.find(get_tree())
	if world == null or world.grid == null or item == null:
		return
	var objects: Node = world.get_node_or_null("Objects")
	if objects == null:
		return
	var grid: WorldGrid = world.grid
	var origin: Vector2i = grid.world_to_cell(global_position)
	var cells: Array[Vector2i] = TreeUse.pick_drop_cells(origin, grid, 1, false)
	if cells.is_empty():
		return
	var pickup: Node3D = FieldItems.put(world, cells[0], item.id, true)
	if pickup == null:
		return
	var land: Vector3 = pickup.global_position
	var crown: Vector3 = global_position + TreeUse.crown_offset(2, false, false)
	if pickup.has_method("begin_fall"):
		pickup.call("begin_fall", crown, land, TreeUse.drop_duration(2, false, false), false)
	else:
		pickup.global_position = land


func _persist() -> StringName:
	return persist_id if persist_id != &"" else occupant_id


func _cell() -> Vector2i:
	var world := World.find(get_tree())
	if world != null and "grid" in world and world.grid != null:
		return world.grid.world_to_cell(global_position)
	return Vector2i.ZERO


func _emit_drops(out: TreeUse.Outcome, ctx: InteractionContext) -> void:
	var items: Array[ItemData] = out.drops.duplicate()
	if items.is_empty() and out.dropped_fruit > 0 and plant != null and plant.fruit != null:
		for _i: int in out.dropped_fruit:
			items.append(plant.fruit)
	if items.is_empty() or ctx == null or ctx.world == null:
		return
	var grid: WorldGrid = _grid(ctx)
	if grid == null:
		return
	var objects: Node = ctx.world.get_node_or_null("Objects")
	if objects == null:
		return
	var origin: Vector2i = grid.world_to_cell(global_position)
	var prefer_east := false
	if items.size() == 1 and ctx.actor != null:
		prefer_east = global_position.x > ctx.actor.global_position.x
	var cells: Array[Vector2i] = TreeUse.pick_drop_cells(origin, grid, items.size(), prefer_east)
	var is_palm: bool = _use != null and _use.palm_fruit
	for i: int in items.size():
		var data: ItemData = items[i]
		if data == null:
			continue
		var cell: Vector2i = cells[i] if i < cells.size() else origin
		var is_honey: bool = data.id == &"honeycomb"
		var is_ftr: bool = data is FurnitureData
		## What lands stays on the field (`FieldItems`); no free unit, nothing lands.
		var pickup: Node3D = FieldItems.put(ctx.world, cell, data.id)
		if pickup == null:
			continue
		var land: Vector3 = pickup.global_position
		var crown: Vector3 = global_position + TreeUse.crown_offset(i, is_honey, is_palm)
		var duration: float = TreeUse.drop_duration(i, is_honey, is_ftr)
		if pickup.has_method("begin_fall"):
			pickup.call("begin_fall", crown, land, duration, is_ftr)
			if is_honey and _pending_bees != null:
				pickup.landed.connect(
					func() -> void:
						if is_instance_valid(_pending_bees):
							_pending_bees.global_position = land + Vector3(0.0, 0.4, 0.0),
					CONNECT_ONE_SHOT
				)
		else:
			pickup.global_position = land


func _arm_bees(ctx: InteractionContext) -> void:
	if ctx == null or ctx.world == null:
		return
	var objects: Node = ctx.world.get_node_or_null("Objects")
	if objects == null:
		return
	## Delayed birth (~5 frames after shake effect) then attach to honeycomb land.
	get_tree().create_timer(BEE_SPAWN_DELAY).timeout.connect(
		func() -> void:
			if not is_instance_valid(self) or ctx.world == null:
				return
			var parent: Node = ctx.world.get_node_or_null("Objects")
			if parent == null:
				return
			_pending_bees = BeeSwarm.spawn(parent, global_position + Vector3(0.0, 2.5, 0.0), ctx.actor)
			_schedule_bee_attackable(BEE_ATTACKABLE_AFTER_EFFECT - BEE_SPAWN_DELAY),
		CONNECT_ONE_SHOT
	)


func _schedule_bee_attackable(delay: float) -> void:
	get_tree().create_timer(maxf(0.0, delay)).timeout.connect(
		func() -> void:
			if _pending_bees != null and is_instance_valid(_pending_bees):
				_pending_bees.mark_attackable()
			elif get_tree() != null:
				for node: Node in get_tree().get_nodes_in_group("bee_swarm"):
					if node.has_method("mark_attackable"):
						node.call("mark_attackable"),
		CONNECT_ONE_SHOT
	)


func _world_has_bees(ctx: InteractionContext) -> bool:
	if ctx == null or ctx.world == null or ctx.world.get_tree() == null:
		return false
	return not ctx.world.get_tree().get_nodes_in_group("bee_swarm").is_empty()


func _grid(ctx: InteractionContext) -> WorldGrid:
	if ctx == null or ctx.world == null:
		return null
	if "grid" in ctx.world:
		return ctx.world.grid as WorldGrid
	return null


## `Player_actor_SetEffect_Shake_tree` / the little bump: the EffectBG sway for this tree's
## family and size, plus its falling leaves and (in winter) snow. `with_fx` is off for the
## chop hit, which is not a shake effect.
func _play_shake(strong: bool, with_fx: bool = true) -> void:
	var pivot := get_node_or_null("VisualPivot") as Node3D
	if pivot == null or not is_inside_tree():
		return
	_kill_motion()
	pivot.transform = Transform3D.IDENTITY
	var size: int = _ensure_use().size
	if size == TreeUse.Size.S0 and not strong:
		_play_young_wobble(pivot)
		return
	var family: PlantData.Family = _family()
	var curve: Array[Vector3] = TreeSway.keys(family, size, strong)
	var first: float = TreeSway.first_frame(curve)
	var last: float = TreeSway.last_frame(curve)
	_motion = create_tween()
	_motion.tween_method(_apply_sway.bind(pivot, curve), first, last, (last - first) / DecompTime.FRAME_HZ)
	if with_fx:
		_schedule_shake_fx(strong, family, size)


func _apply_sway(frame: float, pivot: Node3D, curve: Array[Vector3]) -> void:
	if is_instance_valid(pivot):
		pivot.rotation.z = deg_to_rad(TreeSway.sample(curve, frame))


func _family() -> PlantData.Family:
	return plant.family if plant != null else PlantData.Family.HARDWOOD


## `eYoung_Tree_mv`: a sapling rolls about the camera's line of sight, decaying over the
## effect's 14 ticks; cedar and palm saplings pivot above the trunk base.
func _play_young_wobble(pivot: Node3D) -> void:
	var ticks: int = TreeSway.YOUNG_SMALL_TICKS
	_motion = create_tween()
	_motion.tween_method(_apply_young.bind(pivot), 0.0, float(ticks), float(ticks) * DecompTime.TICK_SEC)


func _apply_young(tick: float, pivot: Node3D) -> void:
	if not is_instance_valid(pivot):
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var whole: int = int(tick)
	var roll: float = deg_to_rad(
		TreeSway.young_roll(TreeSway.YOUNG_SMALL_TICKS - whole, float(whole) * TreeSway.YOUNG_PHASE_STEP)
	)
	var axis: Vector3 = (cam.global_position - global_position).normalized()
	axis = global_transform.basis.inverse() * axis
	if axis.length_squared() < 0.0001:
		return
	var basis := Basis(axis.normalized(), roll)
	var about := Vector3.ZERO
	if _family() == PlantData.Family.PALM:
		about.y = YOUNG_PIVOT_PALM_GX * FieldCatalog.GX_TO_METERS
	elif _family() == PlantData.Family.CEDAR:
		about.y = YOUNG_PIVOT_CEDAR_GX * FieldCatalog.GX_TO_METERS
	pivot.transform = Transform3D(basis, about - basis * about)


## `ac_effectbg` timer callbacks: the big shake drops a leaf every 16 ticks from tick 16;
## both shakes add a winter snow puff every 16 ticks (from tick 0 for the little one).
func _schedule_shake_fx(strong: bool, family: PlantData.Family, size: int) -> void:
	var last_tick: int = TreeSway.LARGE_TICKS if strong else TreeSway.SMALL_TICKS
	var medium_cedar: bool = family == PlantData.Family.CEDAR and size == TreeUse.Size.S1
	var winter: bool = Clock.season() == Clock.Season.WINTER
	for tick: int in range(0, last_tick + 1, 16):
		if strong and tick == 0:
			continue
		var delay: float = float(tick) * DecompTime.TICK_SEC
		if delay <= 0.0:
			_emit_shake_fx(strong, family, medium_cedar, winter)
		else:
			get_tree().create_timer(delay).timeout.connect(
				_emit_shake_fx.bind(strong, family, medium_cedar, winter), CONNECT_ONE_SHOT
			)


func _emit_shake_fx(strong: bool, family: PlantData.Family, medium_cedar: bool, winter: bool) -> void:
	if not is_inside_tree() or _felling:
		return
	var host: Node = get_parent()
	if host == null:
		return
	var crown: Vector3 = global_position + Vector3(0.0, TreeFx.CROWN_GX * FieldCatalog.GX_TO_METERS, 0.0)
	if strong:
		TreeFx.leaf(host, crown, family, medium_cedar)
	if winter:
		TreeFx.snow(host, crown, medium_cedar)


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
	_motion.tween_property(pivot, "rotation", axis * (PI * 0.5), 0.55).set_trans(
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
		_use.content = TreeUse.Content.NONE
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
			shape.radius = STUMP_RADIUS
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
	## `aINS_PL_ACT_SHAKE_TREE` — wakes bagworms and scares tree cicadas / beetles.
	field.notify_field_action(BugActor.PlAct.SHAKE_TREE, _cell())
