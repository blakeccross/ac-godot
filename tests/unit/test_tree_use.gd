class_name TestTreeUse
extends GdUnitTestSuite

## Chop / shake / stump rules. Three hits on a full tree; fruit drops once.


func before_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = true


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_hit_counts_follow_size() -> void:
	assert_int(TreeUse.hits_for(TreeUse.Size.S0)).is_equal(1)
	assert_int(TreeUse.hits_for(TreeUse.Size.S1)).is_equal(2)
	assert_int(TreeUse.hits_for(TreeUse.Size.S2)).is_equal(3)
	assert_int(TreeUse.hits_for(TreeUse.Size.FULL)).is_equal(3)


func test_apple_tree_drops_three_once() -> void:
	var plant: PlantData = load("res://data/plants/apple_tree.tres")
	var use := TreeUse.new()
	use.configure(plant, &"TREE_APPLE_FRUIT", false)
	assert_that(use.stage).is_equal(TreeUse.Stage.FRUITING)
	var first: TreeUse.Outcome = use.shake()
	assert_int(first.dropped_fruit).is_equal(3)
	assert_bool(first.shook).is_true()
	assert_that(use.stage).is_equal(TreeUse.Stage.BARE)
	var second: TreeUse.Outcome = use.shake()
	assert_int(second.dropped_fruit).is_equal(0)
	assert_bool(second.shook).is_true()


func test_hardwood_has_no_fruit() -> void:
	var plant: PlantData = load("res://data/plants/hardwood_tree.tres")
	var use := TreeUse.new()
	use.configure(plant, &"TREE", false)
	assert_that(use.stage).is_equal(TreeUse.Stage.BARE)
	assert_int(use.shake().dropped_fruit).is_equal(0)


func test_palm_drops_two() -> void:
	var plant: PlantData = load("res://data/plants/apple_tree.tres")
	assert_int(TreeUse.fruit_count_for(&"TREE_PALM_FRUIT", plant)).is_equal(2)


func test_three_chops_fell_a_full_tree() -> void:
	var plant: PlantData = load("res://data/plants/apple_tree.tres")
	var use := TreeUse.new()
	use.configure(plant, &"TREE_APPLE_FRUIT", false)
	var first: TreeUse.Outcome = use.chop()
	assert_int(first.dropped_fruit).is_equal(3)
	assert_bool(first.felled).is_false()
	assert_int(use.hits_left).is_equal(2)
	assert_that(use.stage).is_equal(TreeUse.Stage.BARE)
	assert_bool(use.chop().felled).is_false()
	var last: TreeUse.Outcome = use.chop()
	assert_bool(last.felled).is_true()
	assert_int(last.dropped_fruit).is_equal(0)
	assert_that(use.stage).is_equal(TreeUse.Stage.STUMP)
	assert_bool(use.chop().felled).is_false()
	assert_bool(use.shake().shook).is_false()


func test_stump_configure_skips_fruit() -> void:
	var plant: PlantData = load("res://data/plants/apple_tree.tres")
	var use := TreeUse.new()
	use.configure(plant, &"TREE_APPLE_FRUIT", true)
	assert_that(use.stage).is_equal(TreeUse.Stage.STUMP)
	assert_int(use.shake().dropped_fruit).is_equal(0)
	assert_bool(use.chop().felled).is_false()


func test_drop_cells_prefer_west_east_south() -> void:
	var grid := WorldGrid.new()
	grid.configure(16, 16, 2.0, Vector3.ZERO)
	var cells: Array[Vector2i] = TreeUse.pick_drop_cells(Vector2i(8, 8), grid, 3)
	assert_int(cells.size()).is_equal(3)
	assert_that(cells[0]).is_equal(Vector2i(7, 8))
	assert_that(cells[1]).is_equal(Vector2i(9, 8))
	assert_that(cells[2]).is_equal(Vector2i(8, 9))
	grid.place(
		&"blocker", Vector2i(7, 8), Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT
	)
	var shifted: Array[Vector2i] = TreeUse.pick_drop_cells(Vector2i(8, 8), grid, 3)
	assert_bool(shifted.has(Vector2i(7, 8))).is_false()
	assert_int(shifted.size()).is_equal(3)
