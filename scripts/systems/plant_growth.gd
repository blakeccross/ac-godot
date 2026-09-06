class_name PlantGrowth
extends RefCounted

## Daily FG growth (`mAGrw_RenewalFgItem` at 06:00). Stores planted_renew and
## derives Seed → Growing → Mature → Harvestable. Not an autoload.

enum Pipeline { SEED, GROWING, MATURE, HARVESTABLE }

const PLANTS_DIR := "res://data/plants"
const KEY_PLANT := "plant"
const KEY_PLANTED := "planted_renew"
const KEY_WATERED := "last_watered_renew"
const KEY_FRUIT := "fruit_taken_renew"
const KEY_CONTENT := "shake_content"
const KEY_CELL_X := "cell_x"
const KEY_CELL_Z := "cell_z"
## Bloom color visual for grown flowers (`FLOWER_PANSIES0` white / `1` purple / `2` yellow).
## Not a growth stage — GC uses separate `FLOWER_LEAVES_*` ids for leaves.
const KEY_BLOOM := "bloom_visual"

## Daily special-tree caps (`mAGrw_*`). Town is smaller than GC; still top up to these.
const MONEY_TREE_NUM := 30
const FTR_TREE_NUM := 2
## One bee tree per FG X-column when possible (`FG_BLOCK_X_NUM` = 5).
const BEE_COLUMN_NUM := 5
## Unwatered flowers die after this many renews past `last_watered_renew`.
## GC clears flowers on KILL_PLANT tiles; wilt extends our watering slice.
const FLOWER_DIE_DAYS := 4

static var _plants: Dictionary = {}
static var _plants_loaded := false


static func plant_data(plant_id: StringName) -> PlantData:
	_ensure_plants()
	return _plants.get(plant_id) as PlantData


static func persist_id(cell: Vector2i) -> StringName:
	return StringName("plant_%d_%d" % [cell.x, cell.y])


static func cell_from_persist(id: StringName) -> Vector2i:
	var s := String(id)
	if not s.begins_with("plant_"):
		return Vector2i(-1, -1)
	var parts: PackedStringArray = s.substr(6).split("_")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


static func record(persist_id: StringName) -> Dictionary:
	if persist_id == &"" or Game.plant_states == null:
		return {}
	var raw: Variant = Game.plant_states.get(String(persist_id), {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return (raw as Dictionary).duplicate()


static func has_record(persist_id: StringName) -> bool:
	return not record(persist_id).is_empty()


static func clear(persist_id: StringName) -> void:
	if persist_id == &"":
		return
	Game.plant_states.erase(String(persist_id))


static func growth_days(rec: Dictionary, plant: PlantData, now_renew: int = -1) -> int:
	if rec.is_empty() or plant == null:
		return 0
	var now: int = now_renew if now_renew >= 0 else Clock.renew_index()
	var planted: int = int(rec.get(KEY_PLANTED, now))
	var calendar: int = _calendar_days(planted, now, plant.winter_pauses)
	if not plant.needs_water:
		return calendar
	var watered: int = int(rec.get(KEY_WATERED, planted))
	var watered_span: int = _calendar_days(planted, watered, plant.winter_pauses)
	return mini(calendar, watered_span)


static func pipeline(rec: Dictionary, plant: PlantData, now_renew: int = -1) -> Pipeline:
	if rec.is_empty() or plant == null:
		return Pipeline.HARVESTABLE
	return pipeline_for_days(growth_days(rec, plant, now_renew), plant)


static func pipeline_for_days(days: int, plant: PlantData) -> Pipeline:
	var t0: int = _threshold(plant, 0)
	var t1: int = _threshold(plant, 1)
	var t2: int = _threshold(plant, 2)
	if days < t0:
		return Pipeline.SEED
	if days < t1:
		return Pipeline.GROWING
	if days < t2:
		return Pipeline.MATURE
	return Pipeline.HARVESTABLE


static func fruit_ready(rec: Dictionary, plant: PlantData, now_renew: int = -1) -> bool:
	if plant == null or plant.fruit == null:
		return false
	if pipeline(rec, plant, now_renew) != Pipeline.HARVESTABLE:
		return false
	var now: int = now_renew if now_renew >= 0 else Clock.renew_index()
	return int(rec.get(KEY_FRUIT, -1)) < now


static func visual_id(rec: Dictionary, plant: PlantData, now_renew: int = -1) -> StringName:
	if plant == null:
		return &""
	var pipe: Pipeline = pipeline(rec, plant, now_renew)
	match pipe:
		Pipeline.SEED:
			return _visual(plant.visual_seed, plant)
		Pipeline.GROWING:
			return _visual(plant.visual_growing, plant)
		Pipeline.MATURE:
			return _visual(plant.visual_mature, plant)
		_:
			if plant.kind == PlantData.Kind.FLOWER:
				var bloom := StringName(str(rec.get(KEY_BLOOM, "")))
				if bloom != &"":
					return bloom
			if fruit_ready(rec, plant, now_renew) and plant.visual_harvestable != &"":
				return plant.visual_harvestable
			return _visual(plant.visual_mature, plant)


static func visual_scale(_pipe: Pipeline) -> float:
	## Stage meshes (`obj_s_tree1`–`tree5`) already carry size. Do not scale a full tree down.
	return 1.0


static func tree_size(pipe: Pipeline) -> TreeUse.Size:
	match pipe:
		Pipeline.SEED:
			return TreeUse.Size.S0
		Pipeline.GROWING:
			return TreeUse.Size.S1
		Pipeline.MATURE:
			return TreeUse.Size.S2
		_:
			return TreeUse.Size.FULL


static func ensure(
	persist_id: StringName, plant: PlantData, visual: StringName, cell: Vector2i
) -> Dictionary:
	if persist_id == &"" or plant == null:
		return {}
	var existing: Dictionary = record(persist_id)
	if not existing.is_empty():
		return existing
	var now: int = Clock.renew_index()
	var days: int = _days_for_visual(plant, visual)
	var planted: int = now - days
	var rec := {
		KEY_PLANT: String(plant.id),
		KEY_PLANTED: planted,
		KEY_WATERED: now if plant.needs_water else planted,
		KEY_FRUIT: -1,
		KEY_CELL_X: cell.x,
		KEY_CELL_Z: cell.y,
	}
	if plant.kind == PlantData.Kind.FLOWER and is_grown_flower_visual(visual):
		rec[KEY_BLOOM] = String(visual)
	_store(persist_id, rec)
	return rec


static func ensure_grown_bloom(persist_id: StringName, visual: StringName) -> void:
	## Repair FG blooms saved under the old stage mapping (colors treated as seed/bud).
	if persist_id == &"" or not is_grown_flower_visual(visual):
		return
	var rec: Dictionary = record(persist_id)
	if rec.is_empty():
		return
	var plant: PlantData = plant_data(StringName(str(rec.get(KEY_PLANT, ""))))
	if plant == null or plant.kind != PlantData.Kind.FLOWER:
		return
	rec[KEY_BLOOM] = String(visual)
	var need: int = _threshold(plant, 2)
	if growth_days(rec, plant) < need:
		var now: int = Clock.renew_index()
		rec[KEY_PLANTED] = now - need
		rec[KEY_WATERED] = now
	_store(persist_id, rec)


static func plant(ctx: InteractionContext, plant: PlantData, cell: Vector2i) -> StringName:
	if plant == null or not can_plant(ctx, plant, cell):
		return &""
	var grid: WorldGrid = _grid(ctx)
	var pid: StringName = persist_id(cell)
	var occupant: StringName = grid.occupant_at(cell)
	if occupant != &"" and Game.is_hole(occupant):
		var hole: Node = _hole_at(ctx.world, occupant)
		if hole != null:
			HoleUse.fill(hole, ctx)
		else:
			Game.clear_hole(occupant)
			grid.remove(occupant)
	var now: int = Clock.renew_index()
	var rec := {
		KEY_PLANT: String(plant.id),
		KEY_PLANTED: now,
		KEY_WATERED: now,
		KEY_FRUIT: -1,
		KEY_CELL_X: cell.x,
		KEY_CELL_Z: cell.y,
	}
	_store(pid, rec)
	if not grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT):
		clear(pid)
		return &""
	_instance(ctx.world if ctx != null else null, grid, cell, pid, plant)
	return pid


static func can_plant(ctx: InteractionContext, plant: PlantData, cell: Vector2i) -> bool:
	var grid: WorldGrid = _grid(ctx)
	if grid == null or plant == null or not grid.is_in_bounds(cell):
		return false
	if not _terrain_ok(grid.terrain_at(cell), plant):
		return false
	if not grid.is_occupied(cell):
		return true
	return Game.is_hole(grid.occupant_at(cell))


static func water(persist_id: StringName) -> bool:
	var rec: Dictionary = record(persist_id)
	if rec.is_empty():
		return false
	var plant: PlantData = plant_data(StringName(str(rec.get(KEY_PLANT, ""))))
	if plant == null or not plant.needs_water:
		return false
	var now: int = Clock.renew_index()
	if int(rec.get(KEY_WATERED, 0)) >= now:
		return false
	rec[KEY_WATERED] = now
	_store(persist_id, rec)
	return true


static func take_fruit(persist_id: StringName) -> bool:
	var rec: Dictionary = record(persist_id)
	if rec.is_empty():
		return false
	var plant: PlantData = plant_data(StringName(str(rec.get(KEY_PLANT, ""))))
	if not fruit_ready(rec, plant):
		return false
	rec[KEY_FRUIT] = Clock.renew_index()
	_store(persist_id, rec)
	return true


static func shake_content(persist_id: StringName) -> TreeUse.Content:
	var rec: Dictionary = record(persist_id)
	if rec.is_empty():
		return TreeUse.Content.NONE
	return TreeUse.content_from_id(StringName(str(rec.get(KEY_CONTENT, ""))))


static func set_shake_content(persist_id: StringName, content: TreeUse.Content) -> void:
	var rec: Dictionary = record(persist_id)
	if rec.is_empty():
		return
	var id: StringName = TreeUse.content_id(content)
	if id == &"":
		rec.erase(KEY_CONTENT)
	else:
		rec[KEY_CONTENT] = String(id)
	_store(persist_id, rec)


static func clear_shake_content(persist_id: StringName) -> void:
	set_shake_content(persist_id, TreeUse.Content.NONE)


static func can_hold_special(rec: Dictionary, plant: PlantData) -> bool:
	## Bare mature hardwood/cedar/gold only — not fruiting, not already special, not a flower.
	if rec.is_empty() or plant == null or plant.kind != PlantData.Kind.TREE:
		return false
	if pipeline(rec, plant) != Pipeline.HARVESTABLE:
		return false
	if fruit_ready(rec, plant):
		return false
	return shake_content_of(rec) == TreeUse.Content.NONE


static func shake_content_of(rec: Dictionary) -> TreeUse.Content:
	if rec.is_empty():
		return TreeUse.Content.NONE
	return TreeUse.content_from_id(StringName(str(rec.get(KEY_CONTENT, ""))))


static func assign_special_trees(world: Node = null) -> void:
	## Top up bees / furniture / money trees after grow (`mAGrw_SetHoneycombTree` order).
	var candidates: Array[StringName] = []
	var bee_count := 0
	var ftr_count := 0
	var money_count := 0
	for key: Variant in Game.plant_states.keys():
		var pid := StringName(str(key))
		if Game.is_interactable_removed(pid) or Game.is_stump(pid):
			continue
		var rec: Dictionary = record(pid)
		var plant: PlantData = plant_data(StringName(str(rec.get(KEY_PLANT, ""))))
		if plant == null or plant.kind != PlantData.Kind.TREE:
			continue
		var existing: TreeUse.Content = shake_content_of(rec)
		match existing:
			TreeUse.Content.BEES:
				bee_count += 1
			TreeUse.Content.FURNITURE:
				ftr_count += 1
			TreeUse.Content.BELLS:
				money_count += 1
			_:
				pass
		if can_hold_special(rec, plant):
			candidates.append(pid)
	_assign_content(candidates, TreeUse.Content.BEES, maxi(0, BEE_COLUMN_NUM - bee_count))
	_assign_content(candidates, TreeUse.Content.FURNITURE, maxi(0, FTR_TREE_NUM - ftr_count))
	_assign_content(candidates, TreeUse.Content.BELLS, maxi(0, MONEY_TREE_NUM - money_count))
	if world != null:
		refresh_hosts(world)


static func _assign_content(
	candidates: Array[StringName], content: TreeUse.Content, need: int
) -> void:
	if need <= 0 or candidates.is_empty():
		return
	candidates.shuffle()
	var placed := 0
	var i := 0
	while i < candidates.size() and placed < need:
		var pid: StringName = candidates[i]
		i += 1
		var rec: Dictionary = record(pid)
		var plant: PlantData = plant_data(StringName(str(rec.get(KEY_PLANT, ""))))
		if not can_hold_special(rec, plant):
			continue
		set_shake_content(pid, content)
		placed += 1
	## Drop used ids so later content kinds do not overwrite.
	var remaining: Array[StringName] = []
	for pid: StringName in candidates:
		if shake_content(pid) == TreeUse.Content.NONE:
			remaining.append(pid)
	candidates.clear()
	candidates.append_array(remaining)


static func refresh_hosts(world: Node) -> void:
	if world == null or world.get_tree() == null:
		return
	for node: Node in world.get_tree().get_nodes_in_group("plant"):
		if node.has_method("apply_growth"):
			node.call("apply_growth")


static func plant_from_slot(ctx: InteractionContext, slot_index: int) -> String:
	if ctx == null or ctx.inventory == null:
		return ""
	var slot: InventorySlot = ctx.inventory.slot_at(slot_index)
	if slot == null or slot.is_empty():
		return ""
	var item: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if item == null or item.plant_id == &"":
		return ""
	var plant: PlantData = plant_data(item.plant_id)
	if plant == null:
		return ""
	var cell: Vector2i = ToolUse.facing_cell(ctx)
	if not can_plant(ctx, plant, cell):
		return "Can't plant here."
	var removed: InventoryItem = ctx.inventory.remove_from_slot(slot_index, 1)
	if removed.is_empty():
		return ""
	var pid: StringName = PlantGrowth.plant(ctx, plant, cell)
	if pid == &"":
		ctx.inventory.add(item, 1, removed.condition)
		return "Can't plant here."
	return "Planted %s." % plant.display_name


static func refresh_world(world: Node) -> void:
	assign_special_trees(world)
	refresh_hosts(world)


static func should_die(rec: Dictionary, plant: PlantData, now_renew: int = -1) -> bool:
	## Flowers that need water die when left dry for `FLOWER_DIE_DAYS` renews.
	if rec.is_empty() or plant == null or plant.kind != PlantData.Kind.FLOWER:
		return false
	if not plant.needs_water:
		return false
	var now: int = now_renew if now_renew >= 0 else Clock.renew_index()
	var watered: int = int(rec.get(KEY_WATERED, int(rec.get(KEY_PLANTED, now))))
	var dry: int = _calendar_days(watered, now, plant.winter_pauses)
	return dry >= FLOWER_DIE_DAYS


static func cull_dead_flowers(world: Node, grid: WorldGrid) -> void:
	## Remove wilted flowers from the field (`EMPTY_NO` on kill / our water wilt).
	if world == null or grid == null:
		return
	var doomed: Array[StringName] = []
	for key: Variant in Game.plant_states.keys():
		var pid := StringName(str(key))
		var rec: Dictionary = record(pid)
		var plant: PlantData = plant_data(StringName(str(rec.get(KEY_PLANT, ""))))
		if should_die(rec, plant):
			doomed.append(pid)
	for pid: StringName in doomed:
		_kill_flower(world, grid, pid)


static func dig_up_flower(ctx: InteractionContext, cell: Vector2i) -> bool:
	## `mFI_CheckDigRemoveItem` for flowers: scoop clears the plant and writes a hole.
	var grid: WorldGrid = null
	if ctx != null and ctx.world != null:
		grid = ctx.world.get("grid") as WorldGrid
	if grid == null or not grid.is_in_bounds(cell):
		return false
	var occupant: StringName = grid.occupant_at(cell)
	if occupant == &"":
		return false
	var rec: Dictionary = record(occupant)
	var plant: PlantData = plant_data(StringName(str(rec.get(KEY_PLANT, ""))))
	if plant == null or plant.kind != PlantData.Kind.FLOWER:
		## Also allow FG flower hosts without a growth record (test town / templates).
		if not _is_flower_host(ctx.world if ctx != null else null, occupant):
			return false
	_kill_flower(ctx.world if ctx != null else null, grid, occupant)
	Game.post_notice("You dug up the flower.")
	return HoleUse.dig(ctx, cell)


static func _kill_flower(world: Node, grid: WorldGrid, pid: StringName) -> void:
	clear(pid)
	Game.mark_interactable_removed(pid)
	if grid != null:
		grid.remove(pid)
	if world == null or world.get_tree() == null:
		return
	for node: Node in world.get_tree().get_nodes_in_group("plant"):
		if node.get("persist_id") == pid or node.get("occupant_id") == pid:
			node.queue_free()
			return


static func _is_flower_host(world: Node, pid: StringName) -> bool:
	if world == null or world.get_tree() == null or pid == &"":
		return false
	for node: Node in world.get_tree().get_nodes_in_group("plant"):
		if node.get("persist_id") != pid and node.get("occupant_id") != pid:
			continue
		var plant: Variant = node.get("plant")
		if plant is PlantData and (plant as PlantData).kind == PlantData.Kind.FLOWER:
			return true
		var vis := String(node.get("visual_id"))
		if vis.begins_with("FLOWER_"):
			return true
	return false


static func restore(world: Node, grid: WorldGrid) -> void:
	if world == null or grid == null:
		return
	for key: Variant in Game.plant_states.keys():
		var pid := StringName(str(key))
		if Game.is_interactable_removed(pid) or Game.is_stump(pid):
			continue
		if _host_exists(world, pid):
			continue
		var rec: Dictionary = record(pid)
		var plant: PlantData = plant_data(StringName(str(rec.get(KEY_PLANT, ""))))
		if plant == null:
			continue
		var cell := Vector2i(int(rec.get(KEY_CELL_X, -1)), int(rec.get(KEY_CELL_Z, -1)))
		if cell.x < 0:
			cell = cell_from_persist(pid)
		if not grid.is_in_bounds(cell):
			continue
		if not grid.is_occupied(cell):
			if not grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT):
				continue
		_instance(world, grid, cell, pid, plant)


static func _calendar_days(from_renew: int, to_renew: int, skip_winter: bool) -> int:
	if to_renew <= from_renew:
		return 0
	if not skip_winter:
		return to_renew - from_renew
	var n := 0
	for r: int in range(from_renew, to_renew):
		if Clock.season_on_renew(r) != Clock.Season.WINTER:
			n += 1
	return n


static func _threshold(plant: PlantData, index: int) -> int:
	if plant == null or index < 0 or index >= plant.stage_days.size():
		return (index + 1) * 2
	return maxi(plant.stage_days[index], 0)


static func is_grown_flower_visual(visual: StringName) -> bool:
	## `IS_ITEM_GROWN_FLOWER`: bloom colors, not leaf beds (`FLOWER_LEAVES_*`).
	var id := String(visual)
	return (
		id.begins_with("FLOWER_PANSIES")
		or id.begins_with("FLOWER_COSMOS")
		or id.begins_with("FLOWER_TULIP")
	)


static func _days_for_visual(plant: PlantData, visual: StringName) -> int:
	if visual == &"" or plant == null:
		return _threshold(plant, 2)
	## Bloom color ids are already grown (`FLOWER_PANSIES0` white / `1` purple / `2` yellow).
	if is_grown_flower_visual(visual):
		return _threshold(plant, 2)
	if plant.visual_harvestable != &"" and visual == plant.visual_harvestable:
		return _threshold(plant, 2)
	if (
		plant.visual_mature != &""
		and visual == plant.visual_mature
		and visual != plant.visual_seed
		and visual != plant.visual_growing
	):
		return _threshold(plant, 1)
	if (
		plant.visual_growing != &""
		and visual == plant.visual_growing
		and visual != plant.visual_seed
	):
		return _threshold(plant, 0)
	if plant.visual_seed != &"" and visual == plant.visual_seed:
		return 0
	if visual == &"TREE_S0" or visual == &"CEDAR_S0" or visual == &"PALM_S0":
		return 0
	if visual == &"TREE_S1" or visual == &"CEDAR_S1" or visual == &"PALM_S1":
		return _threshold(plant, 0)
	if visual == &"TREE_S2" or visual == &"CEDAR_S2" or visual == &"PALM_S2":
		return _threshold(plant, 1)
	if visual == &"TREE_APPLE_FRUIT" or visual == &"TREE_PALM_FRUIT":
		return _threshold(plant, 2)
	return _threshold(plant, 2)


static func _visual(id: StringName, plant: PlantData) -> StringName:
	if id != &"":
		return id
	if plant.kind == PlantData.Kind.FLOWER:
		return &"FLOWER_PANSIES0"
	return &"TREE"


static func _terrain_ok(terrain: WorldGrid.Terrain, plant: PlantData) -> bool:
	if plant.terrains.is_empty():
		return terrain == WorldGrid.Terrain.GRASS or terrain == WorldGrid.Terrain.SOIL
	return int(terrain) in plant.terrains


static func _store(persist_id: StringName, rec: Dictionary) -> void:
	Game.plant_states[String(persist_id)] = rec.duplicate()


static func _instance(
	world: Node, grid: WorldGrid, cell: Vector2i, pid: StringName, plant: PlantData
) -> Node3D:
	if world == null or grid == null or plant == null:
		return null
	var objects: Node = world.get_node_or_null("Objects")
	if objects == null:
		return null
	var kind: StringName = &"flower" if plant.kind == PlantData.Kind.FLOWER else &"tree"
	var path: String = WorldObjectRegistry.scene_path(kind)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var node: Node3D = packed.instantiate() as Node3D
	if node == null:
		return null
	node.set("persist_id", pid)
	node.set("occupant_id", pid)
	node.set("plant", plant)
	var rec: Dictionary = record(pid)
	if not rec.is_empty():
		node.set("visual_id", visual_id(rec, plant))
	objects.add_child(node)
	var pos: Vector3 = grid.cell_to_world(cell)
	if "layout" in world and world.layout != null:
		pos.y = FieldCollision.ground_y(
			world.layout as WorldData, cell, FieldCollision.fg_ground_dist(kind)
		)
	if node.is_inside_tree():
		node.global_position = pos
	else:
		node.position = pos
	return node


static func _host_exists(world: Node, pid: StringName) -> bool:
	if world == null or world.get_tree() == null:
		return false
	for node: Node in world.get_tree().get_nodes_in_group("plant"):
		var persist: Variant = node.get("persist_id")
		if persist is StringName and persist == pid:
			return true
		var occupant: Variant = node.get("occupant_id")
		if occupant is StringName and occupant == pid:
			return true
	return world.find_child(String(pid), true, false) != null


static func _hole_at(world: Node, pid: StringName) -> Node:
	if world == null:
		return null
	var objects: Node = world.get_node_or_null("Objects")
	if objects == null:
		return null
	for child in objects.get_children():
		var persist: Variant = child.get("persist_id")
		if persist is StringName and persist == pid:
			return child
	return null


static func _grid(ctx: InteractionContext) -> WorldGrid:
	if ctx == null or ctx.world == null:
		return null
	var value: Variant = ctx.world.get("grid")
	return value as WorldGrid


static func _ensure_plants() -> void:
	if _plants_loaded:
		return
	_plants_loaded = true
	_plants.clear()
	var dir := DirAccess.open(PLANTS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".tres"):
			var res: Resource = load("%s/%s" % [PLANTS_DIR, name])
			if res is PlantData:
				var data := res as PlantData
				if data.id != &"":
					_plants[data.id] = data
		name = dir.get_next()
	dir.list_dir_end()
