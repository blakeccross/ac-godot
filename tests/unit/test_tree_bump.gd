extends GdUnitTestSuite

## `Player_actor_check_little_shake_tree`: walking up to a tree shakes it once.


func _grid() -> WorldGrid:
	var grid := WorldGrid.new()
	grid.configure(12, 12, 2.0, Vector3.ZERO)
	return grid


func _tree(grid: WorldGrid, cell: Vector2i) -> Node3D:
	var tree: Node3D = auto_free(Node3D.new())
	tree.position = grid.cell_to_world(cell)
	return tree


func _tick(bump: TreeBump, grid: WorldGrid, pos: Vector3, yaw: float, trees: Array[Node3D]) -> Node3D:
	return bump.tick(1.0 / 60.0, pos, yaw, WorldData.new(), grid, trees)


func test_shakes_tree_ahead_within_a_unit_once() -> void:
	var grid: WorldGrid = _grid()
	var tree: Node3D = _tree(grid, Vector2i(5, 4))
	var trees: Array[Node3D] = [tree]
	var bump := TreeBump.new()
	## Player in cell (5,5) near its north edge, facing north (−Z): 1.2 m to the centre.
	var pos: Vector3 = grid.cell_to_world(Vector2i(5, 5)) + Vector3(0.0, 0.0, -0.8)
	var north: float = PI
	assert_object(_tick(bump, grid, pos, north, trees)).is_same(tree)
	## Still pushing on it: the table holds the tree, no second shake.
	for _i: int in 200:
		assert_object(_tick(bump, grid, pos, north, trees)).is_null()


func test_rearms_after_looking_away() -> void:
	var grid: WorldGrid = _grid()
	var tree: Node3D = _tree(grid, Vector2i(5, 4))
	var trees: Array[Node3D] = [tree]
	var bump := TreeBump.new()
	var pos: Vector3 = grid.cell_to_world(Vector2i(5, 5)) + Vector3(0.0, 0.0, -0.8)
	assert_object(_tick(bump, grid, pos, PI, trees)).is_same(tree)
	## Timer (16 frames) runs out while facing away → entry clears.
	for _i: int in 30:
		_tick(bump, grid, pos, 0.0, trees)
	assert_bool(bump.has_entry(Vector2i(5, 4))).is_false()
	assert_object(_tick(bump, grid, pos, PI, trees)).is_same(tree)


func test_ignores_far_behind_and_own_unit() -> void:
	var grid: WorldGrid = _grid()
	var bump := TreeBump.new()
	var pos: Vector3 = grid.cell_to_world(Vector2i(5, 5)) + Vector3(0.0, 0.0, -0.8)
	## Behind the player (outside ±45°).
	var behind: Array[Node3D] = [_tree(grid, Vector2i(5, 4))]
	assert_object(_tick(bump, grid, pos, 0.0, behind)).is_null()
	## Two units away is not one of the 8 neighbours.
	var far: Array[Node3D] = [_tree(grid, Vector2i(5, 3))]
	assert_object(_tick(bump, grid, pos, PI, far)).is_null()
	## The player's own unit is never a target.
	var own: Array[Node3D] = [_tree(grid, Vector2i(5, 5))]
	assert_object(_tick(bump, grid, pos, PI, own)).is_null()
	## Neighbour unit but centre more than one unit (2 m) away.
	var away: Vector3 = grid.cell_to_world(Vector2i(5, 5)) + Vector3(0.0, 0.0, 0.9)
	var ahead: Array[Node3D] = [_tree(grid, Vector2i(5, 4))]
	assert_object(_tick(bump, grid, away, PI, ahead)).is_null()


func test_picks_tree_closest_to_straight_ahead() -> void:
	var grid: WorldGrid = _grid()
	var bump := TreeBump.new()
	var pos: Vector3 = grid.cell_to_world(Vector2i(5, 5)) + Vector3(0.0, 0.0, -0.8)
	var straight: Node3D = _tree(grid, Vector2i(5, 4))
	var side: Node3D = _tree(grid, Vector2i(6, 4))
	var trees: Array[Node3D] = [side, straight]
	assert_object(_tick(bump, grid, pos, PI, trees)).is_same(straight)


func test_button_shake_claims_the_tree() -> void:
	var grid: WorldGrid = _grid()
	var tree: Node3D = _tree(grid, Vector2i(5, 4))
	var trees: Array[Node3D] = [tree]
	var bump := TreeBump.new()
	var pos: Vector3 = grid.cell_to_world(Vector2i(5, 5)) + Vector3(0.0, 0.0, -0.8)
	bump.note_big_shake(Vector2i(5, 4))
	assert_object(_tick(bump, grid, pos, PI, trees)).is_null()


func test_tree_scene_bumps_but_stump_does_not() -> void:
	var tree: Node = auto_free(load("res://scenes/world/tree.tscn").instantiate())
	assert_bool(tree.can_bump()).is_true()
	tree.bump()
	Game.mark_stump(&"tree_bump_stump")
	var stump: Node = auto_free(load("res://scenes/world/tree.tscn").instantiate())
	stump.set("persist_id", &"tree_bump_stump")
	assert_bool(stump.can_bump()).is_false()
