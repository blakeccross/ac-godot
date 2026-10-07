class_name TownAssessment
extends RefCounted

## Town environment rating (`m_field_assessment`). Each of the 30 field acres is judged on its
## trees, its weeds net of flowers, and trash left out of the dump:
##
## - trash in the acre, or 3+ (weeds − flowers): the acre scores nothing;
## - otherwise by tree count: ≤8 nothing, 9–11 good, 12–14 perfect, 15–17 good, more nothing.
##
## Perfect acres plus half the good ones give the town rank 0–6 (`l_block_max_by_rank`). Five
## pieces of trash anywhere zero it. The worst problem found (trash, too few trees, too many,
## too many weeds) is what the wishing well remarks on, naming an acre. Fifteen days at rank 6
## in a row (`mFAs_PERFECT_DAY_STREAK_MAX`) earn the golden axe.

enum Condition { NONE = -1, DUST_OVER, TREE_LESS, TREE_OVER, GRASS_OVER, NO_CASE }

const FG_BLOCK_X := 5
const FG_BLOCK_Z := 6
const BLOCK_RANK_TREES: Array[int] = [8, 11, 14, 17, 255]
const BLOCK_RANK: Array[int] = [0, 1, 2, 1, 0]
const FIELD_RANK_BLOCKS: Array[int] = [0, 2, 4, 7, 12, 16, 255]
const RANK_PERFECT := 6
const GRASS_OVER_NUM := 5
const DUST_OVER_NUM := 5
const PERFECT_STREAK_MAX := 15
## Trash that counts against the town outside the dump (`ITM_DUST0`–`2`).
const DUST_ITEMS: Array[StringName] = [&"empty_can", &"boot", &"old_tire"]


## One field acre's counts. `excluded` acres (shrine, pool, station, player houses, museum)
## and the beach row never draw the too-few / too-many-trees remark.
class AcreTally:
	var block := Vector2i.ZERO
	var trees: int = 0
	var flowers: int = 0
	var weeds: int = 0
	var dust: int = 0
	var excluded: bool = false


## `mFAs_GetIdx`: the first rung `value` does not exceed.
static func _rung(table: Array[int], value: int) -> int:
	for i: int in table.size():
		if value <= table[i]:
			return i
	return -1


static func block_rank(acre: AcreTally) -> int:
	if acre.dust > 0 or acre.weeds - acre.flowers >= 3:
		return 0
	return BLOCK_RANK[_rung(BLOCK_RANK_TREES, acre.trees)]


static func _check(condition: int, acre: AcreTally) -> int:
	var weeds: int = acre.weeds - acre.flowers
	for c: int in condition + 1:
		match c:
			Condition.TREE_LESS:
				if acre.trees <= BLOCK_RANK_TREES[0]:
					return c
			Condition.TREE_OVER:
				if acre.trees >= BLOCK_RANK_TREES[3]:
					return c
			Condition.GRASS_OVER:
				if weeds >= GRASS_OVER_NUM:
					return c
	return Condition.NONE


## `mFAs_GetFieldGoodBlockNum_common` + `mFAs_GetFieldRankbyFGoodBlock`.
## Returns {rank, condition, block, perfect, good, trees, flowers, weeds}.
static func evaluate(acres: Array, rng: RandomNumberGenerator) -> Dictionary:
	var condition: int = Condition.NO_CASE
	var block := Vector2i.ZERO
	var dust_block := Vector2i.ZERO
	var dust_seen := false
	var perfect: int = 0
	var good: int = 0
	var dust_total: int = 0
	var trees: int = 0
	var flowers: int = 0
	var weeds: int = 0
	for entry: Variant in acres:
		var acre := entry as AcreTally
		dust_total += acre.dust
		trees += acre.trees
		flowers += acre.flowers
		weeds += acre.weeds
		var found: int = _check(condition, acre)
		var allowed: bool = found == Condition.GRASS_OVER or not (acre.excluded or acre.block.y == FG_BLOCK_Z)
		if found != Condition.NONE and allowed:
			var take: int
			if found != condition:
				condition = found
				take = 1
			else:
				take = int(rng.randf() * 3.0)
			if take == 1:
				block = acre.block
		if acre.dust > 0:
			if not dust_seen or rng.randi_range(0, 2) == 1:
				dust_block = acre.block
			dust_seen = true
		match block_rank(acre):
			2:
				perfect += 1
			1:
				good += 1
	var score: int = perfect + good / 2
	if dust_total >= DUST_OVER_NUM:
		score = 0
		condition = Condition.DUST_OVER
		block = dust_block
	return {
		"rank": _rung(FIELD_RANK_BLOCKS, score),
		"condition": condition,
		"block": block,
		"score": score,
		"perfect": perfect,
		"good": good,
		"dust": dust_total,
		"trees": trees,
		"flowers": flowers,
		"weeds": weeds,
	}


## `mFAs_SetGoodField`: days in a row at rank 6, capped at 15; anything else resets it.
## `streak_day` is the day number it was last advanced (−1: never).
static func next_streak(rank: int, streak: int, streak_day: int, today: int) -> Vector2i:
	if rank != RANK_PERFECT:
		return Vector2i(0, -1)
	if streak_day < 0:
		return Vector2i(0, today)
	if today > streak_day:
		return Vector2i(mini(streak + (today - streak_day), PERFECT_STREAK_MAX), today)
	if today < streak_day:
		return Vector2i(0, today)
	return Vector2i(streak, streak_day)


## Counts from the live field: trees and flowers by their hosts, weeds from `Game.weeds`,
## trash from ground items outside the dump acre.
static func survey(world: Node) -> Array:
	var acres: Array = []
	if world == null:
		return acres
	var grid: WorldGrid = world.get("grid") as WorldGrid
	var layout: WorldData = world.get("layout") as WorldData
	if grid == null:
		return acres
	var by_block: Dictionary = {}
	for bz: int in range(1, FG_BLOCK_Z + 1):
		for bx: int in range(1, FG_BLOCK_X + 1):
			var acre := AcreTally.new()
			acre.block = Vector2i(bx, bz)
			acre.excluded = _excluded(layout, acre.block)
			by_block[acre.block] = acre
			acres.append(acre)
	var tree := world.get_tree()
	if tree != null:
		for node: Node in tree.get_nodes_in_group("plant"):
			if not node is Node3D or node.is_queued_for_deletion():
				continue
			var acre := by_block.get(_block_of(grid, (node as Node3D).global_position)) as AcreTally
			if acre == null:
				continue
			var plant: PlantData = node.get("plant") as PlantData
			if plant == null:
				continue
			if plant.kind == PlantData.Kind.FLOWER:
				acre.flowers += 1
			elif not Game.is_stump(StringName(str(node.get("persist_id")))):
				acre.trees += 1
		for node: Node in tree.get_nodes_in_group("interactable"):
			var item: ItemData = node.get("item") as ItemData if "item" in node else null
			if item == null or not DUST_ITEMS.has(item.id) or not node is Node3D:
				continue
			var block: Vector2i = _block_of(grid, (node as Node3D).global_position)
			if _acre_type(layout, block) == TownFieldGenerator.T_TRACKS_DUMP:
				continue
			var acre := by_block.get(block) as AcreTally
			if acre != null:
				acre.dust += 1
	for key: Variant in Game.weeds:
		var acre := by_block.get(TownSpace.block_of_cell(WeedUse.cell_from_persist(StringName(str(key))))) as AcreTally
		if acre != null:
			acre.weeds += 1
	return acres


static func _block_of(grid: WorldGrid, pos: Vector3) -> Vector2i:
	return TownSpace.block_of_cell(grid.world_to_cell(pos))


static func _acre_type(layout: WorldData, block: Vector2i) -> int:
	if layout == null or layout.acre_types.is_empty():
		return -1
	var idx: int = block.y * TownFieldGenerator.BLOCK_X + block.x
	return int(layout.acre_types[idx]) if idx >= 0 and idx < layout.acre_types.size() else -1


## `mFAs_GetFieldRank_Condition`'s excluded kinds: shrine, pool, station, player, museum.
static func _excluded(layout: WorldData, block: Vector2i) -> bool:
	var t: int = _acre_type(layout, block)
	return (
		t == TownFieldGenerator.T_SHRINE
		or TownFieldGenerator.is_pool(t)
		or t == TownFieldGenerator.T_TRACKS_STATION
		or t == TownFieldGenerator.T_PLAYER_HOUSE
		or t == TownFieldGenerator.T_MUSEUM
	)
