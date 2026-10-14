class_name BallUse
extends RefCounted

## Where the town's ball is (`Common_Get(ball_pos)`, `aBALL_Random_pos_set`). A fresh ball
## goes in a random acre that isn't the player houses', the shop's, the station's, the
## pond's or the beach (`mRF_BLOCKKIND_*`), on a free unit two in from its edges
## (`mNpc_GetMakeUtNuminBlock_hard_area`), and is one of the three balls at random. Not an
## autoload.

const SCENE := "res://scenes/world/field_ball.tscn"
const UT := 16
const MARGIN := 2


## `mFI_CheckBlockKind_OR` against the kinds the ball stays out of.
static func block_allowed(acre_type: int) -> bool:
	if acre_type < 0:
		return false
	if acre_type in [TownFieldGenerator.T_PLAYER_HOUSE, TownFieldGenerator.T_TRACKS_SHOP, TownFieldGenerator.T_TRACKS_STATION]:
		return false
	return not TownFieldGenerator.is_pool(acre_type) and not TownFieldGenerator.is_beach(acre_type)


static func _acre_type(layout: WorldData, block: Vector2i) -> int:
	if layout == null or layout.acre_types.is_empty():
		return -1
	var idx: int = block.y * TownFieldGenerator.BLOCK_X + block.x
	return int(layout.acre_types[idx]) if idx >= 0 and idx < layout.acre_types.size() else -1


static func _free(grid: WorldGrid, cell: Vector2i) -> bool:
	if not grid.is_in_bounds(cell) or not grid.is_walkable(cell) or grid.is_occupied(cell):
		return false
	var t: WorldGrid.Terrain = grid.terrain_at(cell)
	return t == WorldGrid.Terrain.GRASS or t == WorldGrid.Terrain.SOIL or t == WorldGrid.Terrain.STONE


## `aBALL_Random_pos_set`: from a random acre, the first allowed one (row by row) with a free
## unit. (-1, -1) when there's none.
static func pick_cell(layout: WorldData, grid: WorldGrid, rng: RandomNumberGenerator) -> Vector2i:
	if grid == null:
		return Vector2i(-1, -1)
	var nx: int = EventManager.BLOCK_X_MAX
	var nz: int = EventManager.BLOCK_Z_MAX
	var sx: int = rng.randi_range(0, nx - 1)
	var sz: int = rng.randi_range(0, nz - 1)
	for i: int in nx:
		for j: int in nz:
			var block := Vector2i(1 + (sx + i) % nx, 1 + (sz + j) % nz)
			if not block_allowed(_acre_type(layout, block)):
				continue
			var cells: Array[Vector2i] = []
			for uz: int in range(MARGIN, UT - MARGIN):
				for ux: int in range(MARGIN, UT - MARGIN):
					var cell: Vector2i = EventManager.block_unit_to_cell(block, Vector2i(ux, uz))
					if _free(grid, cell):
						cells.append(cell)
			if not cells.is_empty():
				return cells[rng.randi_range(0, cells.size() - 1)]
	return Vector2i(-1, -1)


static func restore(world: Node, layout: WorldData, grid: WorldGrid) -> Node3D:
	if world == null or grid == null or not ResourceLoader.exists(SCENE):
		return null
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pos: Vector3
	var type: int
	if Game.ball.is_empty():
		var cell: Vector2i = pick_cell(layout, grid, rng)
		if cell.x < 0:
			return null
		pos = grid.cell_to_world(cell)
		type = rng.randi_range(0, FieldBall.VISUALS.size() - 1)
	else:
		pos = Vector3(float(Game.ball.get("x", 0.0)), float(Game.ball.get("y", 0.0)), float(Game.ball.get("z", 0.0)))
		type = int(Game.ball.get("type", 0))
	var ball: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	ball.set("type", type)
	var parent: Node = world.get_node_or_null("Objects")
	if parent == null:
		parent = world
	parent.add_child(ball)
	ball.global_position = pos
	ball.call("_snap_ground")
	Game.ball = {"x": ball.global_position.x, "y": ball.global_position.y, "z": ball.global_position.z, "type": type}
	return ball
