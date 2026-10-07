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
## Something the player buried in a hole (`mFI_Wpos2DepositON`): crack mark, digs back up.
const KIND_ITEM := &"item"
## `BURIED_PITFALL_HOLE00`+: a pitfall seed in a hole. Nothing shows above ground.
const KIND_PITFALL := &"pitfall"
const PITFALL_ITEM := &"pitfall"
## `Player_actor_check_pitfall`: within 19 GX of the unit centre.
const PITFALL_REACH_GX := 19.0
const PIT_OPEN_TICKS := 26.0
const PIT_SE_TICK := 6.0
const PIT_CLOSE_TICKS := 14.0
const VISUAL_CRACK := &"BURIED_CRACK"
## `mAGrw_HANIWA_NUM`, and the furniture list they come from (`HANIWA_START`…`HANIWA_END`).
const HANIWA_NUM := 3
const HANIWA_BIRTH := "haniwa"
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
	if Game.haniwa_scheduled:
		bury_gyroids(world, grid, roll)
		Game.haniwa_scheduled = false


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


## `mTG_TYPE_FIELD_DEFAULT_BURY` → `bIT_common_hole_throw`: an item put into the facing hole
## fills it; a pitfall seed becomes a hidden pitfall, anything else a marked deposit.
static func bury(ctx: InteractionContext, cell: Vector2i, item_id: StringName) -> bool:
	var grid: WorldGrid = _grid(ctx)
	if grid == null or not grid.is_in_bounds(cell) or item_id == &"":
		return false
	var hole: StringName = grid.occupant_at(cell)
	if not Game.is_hole(hole):
		return false
	if hole == Game.shine_hole:
		var planted: bool = _plant_in_shine_hole(ctx, cell, item_id)
		if planted:
			Game.shine_hole = &""
			return true
	var host: Node = _host_for(ctx.world if ctx != null else null, hole)
	if host != null:
		HoleUse.fill(host, ctx)
	else:
		Game.clear_hole(hole)
		grid.remove(hole)
	if hole == Game.shine_hole:
		Game.shine_hole = &""
	var kind: StringName = KIND_PITFALL if item_id == PITFALL_ITEM else KIND_ITEM
	return _deposit(ctx.world if ctx != null else null, grid, _layout(ctx.world if ctx != null else null), cell, kind, item_id, true)


## Money bag or the shovel into the shine spot's hole (`bIT_common_bury_after`). True when
## something was planted (the hole is gone then).
static func _plant_in_shine_hole(ctx: InteractionContext, cell: Vector2i, item_id: StringName) -> bool:
	var money: Dictionary = {
		&"money_100": TreeUse.Content.MONEY_100, &"money_1000": TreeUse.Content.MONEY_1000,
		&"money_10000": TreeUse.Content.MONEY_10000, &"money_30000": TreeUse.Content.MONEY_30000,
	}
	if money.has(item_id):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var luck: bool = Game.destiny_type == Game.Destiny.MONEY_LUCK
		var content: TreeUse.Content = TreeUse.Content.NONE
		if PlantGrowth.money_tree_takes(rng.randf(), Game.money_power, luck):
			content = money[item_id]
		return PlantGrowth.plant_special(ctx, cell, content, false) != &""
	if item_id == &"shovel":
		return PlantGrowth.plant_special(ctx, cell, TreeUse.Content.GOLDEN_SHOVEL, true) != &""
	return false


static func is_pitfall(persist_id: StringName) -> bool:
	return kind_of(persist_id) == KIND_PITFALL


## `bIT_actor_pit_fall` → `pit` mode 3: the seed is used up and a hole opens under the
## victim, growing in over 26 ticks with the `OTOSIANA` thud (0x13C) at tick 6.
static func spring_pitfall(world: Node, grid: WorldGrid, cell: Vector2i) -> Node3D:
	if grid == null or not grid.is_in_bounds(cell):
		return null
	var pid: StringName = grid.occupant_at(cell)
	if not is_pitfall(pid):
		return null
	_remove(world, grid, pid, cell)
	var ctx := InteractionContext.new()
	ctx.world = world
	if not HoleUse.dig(ctx, cell, false):
		return null
	var hole := _host_for(world, HoleUse.persist_id(cell)) as Node3D
	if hole == null:
		return null
	hole.scale = Vector3.ZERO
	var tw: Tween = hole.create_tween()
	tw.tween_property(hole, "scale", Vector3.ONE, PIT_OPEN_TICKS * DecompTime.TICK_SEC)
	hole.set_meta(&"pit_tween", tw)
	hole.get_tree().create_timer(PIT_SE_TICK * DecompTime.TICK_SEC).timeout.connect(
		func() -> void:
			if is_instance_valid(hole):
				Audio.play_se(&"13c", hole)
	)
	return hole


## `bIT_actor_pit_exit` → `pit` mode 4: the hole shrinks away over 14 ticks (0x15B) and the
## unit is plain ground again.
static func close_pit(world: Node, cell: Vector2i) -> void:
	var pid: StringName = HoleUse.persist_id(cell)
	var hole := _host_for(world, pid) as Node3D
	var ctx := InteractionContext.new()
	ctx.world = world
	if hole == null:
		Game.clear_hole(pid)
		var grid: WorldGrid = _grid(ctx)
		if grid != null:
			grid.remove(pid)
		return
	Audio.play_se(&"15b", hole)
	var opening: Variant = hole.get_meta(&"pit_tween", null)
	if opening is Tween and (opening as Tween).is_valid():
		(opening as Tween).kill()
	var tw: Tween = hole.create_tween()
	tw.tween_property(hole, "scale", Vector3.ZERO, PIT_CLOSE_TICKS * DecompTime.TICK_SEC)
	tw.tween_callback(func() -> void: HoleUse.fill(hole, ctx))


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
	if ctx != null and ctx.actor != null:
		PlayerSe.buried_dig(ctx.actor)
	if kind == KIND_SHINE:
		Game.post_notice("You dug up bells!")
		## `HOLE_SHINE`: what goes back into this hole can grow (`bIT_common_bury_after`).
		Game.shine_hole = HoleUse.persist_id(cell)
	elif kind == KIND_ITEM or kind == KIND_PITFALL:
		Game.post_notice("You dug up %s!" % (item.display_name if item != null else "something"))
	else:
		Game.post_notice("You dug up a fossil!")
		## First fossil triggers the Farway Museum's introductory letter (`mMsm` mail-in).
		if Game.farway != null:
			Game.farway.request_intro_letter()
	## Digging a buried spot leaves an open hole (`DIG_SCOOP` after get).
	HoleUse.dig(ctx, cell, false)
	return true


## A free diggable unit something could be buried in (`mMsm_GetDepositAbleNum`).
static func can_bury(grid: WorldGrid, cell: Vector2i, layout: WorldData = null) -> bool:
	return _can_deposit(grid, cell, layout, false)


## Buries `item_id` under a crack mark at `cell` (`mMsm_DepositItemBlock`).
static func bury_item(world: Node, cell: Vector2i, item_id: StringName) -> bool:
	var grid: WorldGrid = world.get("grid") as WorldGrid if world != null else null
	if grid == null:
		return false
	return _deposit(world, grid, _layout(world), cell, KIND_ITEM, item_id)


## `mAGrw_SetHaniwa`: three different gyroids (`mSP_RandomHaniwaSelect`), each under a
## crack mark in its own random acre with room. Returns the cells used.
static func bury_gyroids(world: Node, grid: WorldGrid, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var layout: WorldData = _layout(world)
	var by_block: Dictionary = {}
	for z: int in grid.rows:
		for x: int in grid.columns:
			var cell := Vector2i(x, z)
			var block: Vector2i = VillagerWalk.block_from_cell(cell)
			if VillagerWalk.is_fg_block(block) and _can_deposit(grid, cell, layout, false):
				if not by_block.has(block):
					by_block[block] = []
				(by_block[block] as Array).append(cell)
	var blocks: Array = by_block.keys()
	blocks.sort()
	var picked: Array[StringName] = []
	for i: int in HANIWA_NUM:
		if blocks.is_empty():
			break
		var id: StringName = FtrCatalog.pick(HANIWA_BIRTH, rng, picked)
		if id == &"":
			break
		picked.append(id)
		## One gyroid an acre while more than one acre is left (`block_candidates[0] > 1`).
		var bi: int = rng.randi_range(0, blocks.size() - 1)
		var cells: Array = by_block[blocks[bi]]
		var cell: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		if blocks.size() > 1:
			blocks.remove_at(bi)
		if _deposit(world, grid, layout, cell, KIND_ITEM, id):
			out.append(cell)
			cells.erase(cell)
	return out


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
	item_id: StringName,
	into_hole: bool = false
) -> bool:
	## A filled hole was diggable already; `_can_deposit` would refuse the unit it vacated.
	if not into_hole and not _can_deposit(grid, cell, layout, kind == KIND_SHINE):
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
	if world == null or kind == KIND_PITFALL:
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


static func _host_for(world: Node, pid: StringName) -> Node:
	if world == null or pid == &"":
		return null
	var objects: Node = world.get_node_or_null("Objects")
	if objects == null:
		return null
	for child: Node in objects.get_children():
		if child.get("persist_id") == pid and not child.is_queued_for_deletion():
			return child
	return null
