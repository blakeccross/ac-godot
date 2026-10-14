class_name QuestField
extends RefCounted

## Field counts the flower contest reads for a villager's home acre
## (`mQst_GetFlowerSeedNum`, `mQst_GetFlowerNum`, `mQst_GetNullNoNum`, all
## `mFI_GetItemNumOnBlockInField`): flowers including leaf beds, bloomed flowers, and
## units with nothing on them. Read off the live outdoor field; indoors every count is -1
## and the contest can't start or finish until the talk happens outside.


static func counts(tree: SceneTree, block: Vector2i) -> Dictionary:
	var out := {"seed": -1, "flower": -1, "null": -1}
	if tree == null or block.x < 0:
		return out
	var world: World = World.find(tree)
	if world == null or world.grid == null:
		return out
	var grid: WorldGrid = world.grid
	var seed_num: int = 0
	var flower_num: int = 0
	for node: Node in tree.get_nodes_in_group("plant"):
		if not (node is Node3D) or not ("visual_id" in node):
			continue
		var visual: String = str(node.get("visual_id"))
		if not visual.begins_with("FLOWER_"):
			continue
		var cell: Vector2i = grid.world_to_cell((node as Node3D).global_position)
		if VillagerWalk.block_from_cell(cell) != block:
			continue
		seed_num += 1
		if not visual.begins_with("FLOWER_LEAVES"):
			flower_num += 1
	var null_num: int = 0
	var origin := Vector2i((block.x - 1) * WorldGenerator.UT, (block.y - 1) * WorldGenerator.UT)
	for z: int in WorldGenerator.UT:
		for x: int in WorldGenerator.UT:
			var cell := origin + Vector2i(x, z)
			if grid.is_in_bounds(cell) and not grid.is_occupied(cell):
				null_num += 1
	out["seed"] = seed_num
	out["flower"] = flower_num
	out["null"] = null_num
	return out
