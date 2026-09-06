class_name BuriedUse
extends RefCounted

## Daily buried dig spots (`mMsm_DepositFossil` / `mAGrw_SetDigItem` shine).
## Fossils show the deposit X (`obj_crack0`); shine spots show golden `ef_anahikari` rays.
## Not an autoload.

const SCENE := "res://scenes/world/buried_mark.tscn"
const FOSSIL_MAX := 5
const KEY_KIND := "kind"
const KEY_ITEM := "item_id"
const KEY_CELL_X := "cell_x"
const KEY_CELL_Z := "cell_z"
const KIND_FOSSIL := &"fossil"
const KIND_SHINE := &"shine"
const VISUAL_CRACK := &"BURIED_CRACK"
const VISUAL_SHINE := &"SHINE_SPOT"


static func persist_id(cell: Vector2i) -> StringName:
	return StringName("buried_%d_%d" % [cell.x, cell.y])


static func cell_from_persist(id: StringName) -> Vector2i:
	var s := String(id)
	if not s.begins_with("buried_"):
		return Vector2i(-1, -1)
	var parts: PackedStringArray = s.substr(7).split("_")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


static func record(persist_id: StringName) -> Dictionary:
	if persist_id == &"" or Game.buried_deposits == null:
		return {}
	var raw: Variant = Game.buried_deposits.get(String(persist_id), {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return (raw as Dictionary).duplicate()


static func is_buried(persist_id: StringName) -> bool:
	return not record(persist_id).is_empty()


static func kind_of(persist_id: StringName) -> StringName:
	return StringName(str(record(persist_id).get(KEY_KIND, "")))


static func visual_for(persist_id: StringName) -> StringName:
	return VISUAL_SHINE if kind_of(persist_id) == KIND_SHINE else VISUAL_CRACK


static func renew(world: Node, grid: WorldGrid, rng: RandomNumberGenerator = null) -> void:
	## Top up to `mMsm_DEPOSIT_FOSSIL_MAX` fossils and one shine spot (`mAGrw_SetShineGround`).
	if world == null or grid == null:
		return
	var roll: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		roll.randomize()
	var layout: WorldData = _layout(world)
	_clear_shine(world, grid)
	_top_up_fossils(world, grid, layout, roll)
	_place_shine(world, grid, layout, roll)


static func restore(world: Node, grid: WorldGrid) -> void:
	if world == null or grid == null:
		return
	var layout: WorldData = _layout(world)
	for key: Variant in Game.buried_deposits.keys():
		var pid := StringName(str(key))
		var rec: Dictionary = record(pid)
		if rec.is_empty():
			continue
		var cell := Vector2i(int(rec.get(KEY_CELL_X, -1)), int(rec.get(KEY_CELL_Z, -1)))
		if cell.x < 0:
			cell = cell_from_persist(pid)
		var kind: StringName = StringName(str(rec.get(KEY_KIND, KIND_FOSSIL)))
		if not _can_deposit(grid, cell, layout, kind == KIND_SHINE):
			continue
		if not grid.is_occupied(cell):
			if not grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT):
				continue
		_instance(world, grid, cell, pid, kind)


static func dig(ctx: InteractionContext, cell: Vector2i) -> bool:
	## `mFI_CheckDigGetItem` when deposit / shine is present.
	var grid: WorldGrid = _grid(ctx)
	if grid == null or not grid.is_in_bounds(cell):
		return false
	var occupant: StringName = grid.occupant_at(cell)
	if not is_buried(occupant):
		return false
	var rec: Dictionary = record(occupant)
	var item_id := StringName(str(rec.get(KEY_ITEM, "")))
	var kind: StringName = StringName(str(rec.get(KEY_KIND, "")))
	if kind == KIND_SHINE:
		item_id = _shine_loot(RandomNumberGenerator.new())
	elif item_id == &"":
		item_id = &"fossil"
	var item: ItemData = ItemCatalog.get_item(item_id)
	if item != null and ctx != null and ctx.inventory != null:
		if ctx.inventory.add(item, 1) != 0:
			Game.post_notice("Pockets are full.")
			return false
	_remove(ctx.world if ctx != null else null, grid, occupant, cell)
	if kind == KIND_SHINE:
		Game.post_notice("You dug up bells!")
	else:
		Game.post_notice("You dug up a fossil!")
	## Digging a buried spot leaves an open hole (`DIG_SCOOP` after get).
	HoleUse.dig(ctx, cell)
	return true


static func _top_up_fossils(
	world: Node, grid: WorldGrid, layout: WorldData, rng: RandomNumberGenerator
) -> void:
	var have := 0
	for key: Variant in Game.buried_deposits.keys():
		if kind_of(StringName(str(key))) == KIND_FOSSIL:
			have += 1
	var need: int = FOSSIL_MAX - have
	while need > 0:
		var cell: Vector2i = _pick_open_cell(grid, layout, rng, false)
		if cell.x < 0:
			return
		if not _deposit(world, grid, layout, cell, KIND_FOSSIL, &"fossil"):
			return
		need -= 1


static func _place_shine(
	world: Node, grid: WorldGrid, layout: WorldData, rng: RandomNumberGenerator
) -> void:
	var cell: Vector2i = _pick_open_cell(grid, layout, rng, true)
	if cell.x < 0:
		return
	_deposit(world, grid, layout, cell, KIND_SHINE, &"money_1000")


static func _clear_shine(world: Node, grid: WorldGrid) -> void:
	## Prior shine clears on renew (`mAGrw_ClearShineGround`).
	var doomed: Array[StringName] = []
	for key: Variant in Game.buried_deposits.keys():
		var pid := StringName(str(key))
		if kind_of(pid) == KIND_SHINE:
			doomed.append(pid)
	for pid: StringName in doomed:
		var cell: Vector2i = cell_from_persist(pid)
		var rec: Dictionary = record(pid)
		if not rec.is_empty():
			cell = Vector2i(int(rec.get(KEY_CELL_X, cell.x)), int(rec.get(KEY_CELL_Z, cell.y)))
		_remove(world, grid, pid, cell)


static func _deposit(
	world: Node,
	grid: WorldGrid,
	layout: WorldData,
	cell: Vector2i,
	kind: StringName,
	item_id: StringName
) -> bool:
	if not _can_deposit(grid, cell, layout, kind == KIND_SHINE):
		return false
	var pid: StringName = persist_id(cell)
	if not grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT):
		return false
	Game.buried_deposits[String(pid)] = {
		KEY_KIND: String(kind),
		KEY_ITEM: String(item_id),
		KEY_CELL_X: cell.x,
		KEY_CELL_Z: cell.y,
	}
	_instance(world, grid, cell, pid, kind)
	return true


static func _remove(world: Node, grid: WorldGrid, pid: StringName, cell: Vector2i) -> void:
	Game.buried_deposits.erase(String(pid))
	if grid != null:
		grid.remove(pid)
	if world == null or world.get_tree() == null:
		return
	for node: Node in world.get_tree().get_nodes_in_group("buried"):
		if node.get("persist_id") == pid:
			node.queue_free()
			return


static func _instance(
	world: Node, grid: WorldGrid, cell: Vector2i, pid: StringName, kind: StringName
) -> void:
	if world == null:
		return
	var packed: PackedScene = load(SCENE) as PackedScene
	if packed == null:
		return
	var host: Node3D = packed.instantiate() as Node3D
	host.set("persist_id", pid)
	host.set("occupant_id", pid)
	host.set("visual_id", VISUAL_SHINE if kind == KIND_SHINE else VISUAL_CRACK)
	host.set("is_shine", kind == KIND_SHINE)
	var parent: Node = world.get_node_or_null("Objects")
	if parent == null:
		parent = world
	parent.add_child(host)
	var pos: Vector3 = grid.cell_to_world(cell)
	if "layout" in world and world.layout != null:
		pos.y = FieldCollision.ground_y(world.layout as WorldData, cell, FieldCollision.FG_GROUND_DIST)
	if host.is_inside_tree():
		host.global_position = pos
	else:
		host.position = pos


static func _can_deposit(
	grid: WorldGrid, cell: Vector2i, layout: WorldData = null, for_shine: bool = false
) -> bool:
	## Empty diggable unit (`EMPTY_NO` + `mCoBG_CheckHole_OrgAttr`), not on blocked acres
	## (player / shrine / station / pool / dump), not on structure plus-offset pads.
	## Shine also needs flat corners and not sand-hole attrs.
	if grid == null or not grid.is_in_bounds(cell):
		return false
	if grid.is_occupied(cell):
		return false
	if FieldCollision.is_raised_plus(cell):
		return false
	if layout != null:
		var acre_type: int = FieldCollision.acre_type_at(layout, cell)
		if acre_type >= 0 and TownFieldGenerator.is_deposit_blocked_acre(acre_type):
			return false
		var attr: int = FieldCollision.unit_attr_at_cell(layout, cell)
		if attr >= 0:
			if not FieldCatalog.is_diggable_attr(attr):
				return false
			if for_shine:
				if FieldCatalog.is_sand_hole_attr(attr):
					return false
				if not FieldCollision.unit_is_flat(layout, cell):
					return false
			return true
	var terrain: WorldGrid.Terrain = grid.terrain_at(cell)
	if for_shine:
		return terrain == WorldGrid.Terrain.GRASS
	return (
		terrain == WorldGrid.Terrain.GRASS
		or terrain == WorldGrid.Terrain.SOIL
		or terrain == WorldGrid.Terrain.SAND
	)


static func _pick_open_cell(
	grid: WorldGrid, layout: WorldData, rng: RandomNumberGenerator, for_shine: bool
) -> Vector2i:
	## Prefer playable FG acres away from map edges.
	var candidates: Array[Vector2i] = []
	for z: int in range(2, maxi(grid.rows - 2, 2)):
		for x: int in range(2, maxi(grid.columns - 2, 2)):
			var cell := Vector2i(x, z)
			if _can_deposit(grid, cell, layout, for_shine):
				candidates.append(cell)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _shine_loot(rng: RandomNumberGenerator) -> StringName:
	## `bg_item_fg_sub_dig2take_conv` without destiny luck: mostly 1k, rare 10k/30k.
	rng.randomize()
	var roll: float = rng.randf() * 100.0
	if roll <= 2.0:
		return &"money_30000"
	if roll <= 12.0:
		return &"money_10000"
	return &"money_1000"


static func _layout(world: Node) -> WorldData:
	if world == null or not ("layout" in world):
		return null
	return world.layout as WorldData


static func _grid(ctx: InteractionContext) -> WorldGrid:
	if ctx == null or ctx.world == null:
		return null
	return ctx.world.get("grid") as WorldGrid
