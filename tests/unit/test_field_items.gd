extends GdUnitTestSuite

## Items lying on the field stay there (`Save fg`), and turnips spoil
## (`mAGrw_SpoilKabu` / `mAGrw_ClearSpoiledKabu` / `mAGrw_SpoilAllPossession`).


class _GridWorld extends Node:
	var grid: WorldGrid = WorldGrid.new()


func before_test() -> void:
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()


func _world() -> _GridWorld:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(32, 32, 2.0, Vector3.ZERO)
	for z: int in 32:
		for x: int in 32:
			world.grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.GRASS)
	world.grid.set_terrain(Vector2i(5, 5), WorldGrid.Terrain.WATER)
	var objects := Node3D.new()
	objects.name = "Objects"
	world.add_child(objects)
	add_child(world)
	return world


func _items(world: Node) -> Array[Node]:
	return world.get_node("Objects").get_children()


func test_a_dropped_item_is_saved_and_comes_back() -> void:
	var world := _world()
	assert_object(FieldItems.put(world, Vector2i(3, 4), &"apple")).is_not_null()
	assert_bool(world.grid.is_occupied(Vector2i(3, 4))).is_true()
	var saved: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(saved)
	var again := _world()
	FieldItems.restore(again, again.grid)
	assert_int(_items(again).size()).is_equal(1)
	assert_str(String(FieldItems.item_at(Vector2i(3, 4)))).is_equal("apple")
	assert_bool(again.grid.is_occupied(Vector2i(3, 4))).is_true()


func test_one_item_a_unit_and_never_on_water() -> void:
	var world := _world()
	assert_object(FieldItems.put(world, Vector2i(3, 4), &"apple")).is_not_null()
	assert_object(FieldItems.put(world, Vector2i(3, 4), &"pear")).is_null()
	assert_object(FieldItems.put(world, Vector2i(5, 5), &"pear")).is_null()


func test_dropping_on_a_taken_unit_finds_the_next_one_around() -> void:
	var world := _world()
	FieldItems.put(world, Vector2i(10, 10), &"apple")
	## Facing south (+z): the unit in front is taken, so the player's left or right.
	var cell: Vector2i = FieldItems.drop_cell(world.grid, Vector2i(10, 10), Vector2i(0, 1))
	assert_int((cell - Vector2i(10, 10)).length_squared()).is_equal(1)
	assert_int(cell.y).is_equal(10)


func test_picking_it_up_forgets_it() -> void:
	var world := _world()
	FieldItems.put(world, Vector2i(3, 4), &"apple")
	assert_bool(FieldItems.picked(FieldItems.persist_id(Vector2i(3, 4)))).is_true()
	assert_bool(Game.field_items.is_empty()).is_true()
	assert_bool(Game.is_interactable_removed(FieldItems.persist_id(Vector2i(3, 4)))).is_false()


func test_turnips_spoil_once_a_sunday_comes_round() -> void:
	## 2001-01-07 was a Sunday.
	assert_bool(FieldItems.sunday_passed(2001, 1, 7, 1)).is_true()
	assert_bool(FieldItems.sunday_passed(2001, 1, 8, 1)).is_false()
	assert_bool(FieldItems.sunday_passed(2001, 1, 9, 3)).is_true()
	var world := _world()
	FieldItems.put(world, Vector2i(1, 1), &"turnips_10")
	FieldItems.put(world, Vector2i(2, 1), &"spoiled_turnips")
	FieldItems.put(world, Vector2i(3, 1), &"apple")
	var inv := Inventory.new()
	inv.add(ItemCatalog.get_item(&"turnips_50"), 1)
	FieldItems.renew(false, inv)
	## Spoiled ones are cleared at every renewal; fresh ones keep until Sunday.
	assert_str(String(FieldItems.item_at(Vector2i(2, 1)))).is_equal("")
	assert_str(String(FieldItems.item_at(Vector2i(1, 1)))).is_equal("turnips_10")
	FieldItems.renew(true, inv)
	assert_str(String(FieldItems.item_at(Vector2i(1, 1)))).is_equal("spoiled_turnips")
	assert_str(String(FieldItems.item_at(Vector2i(3, 1)))).is_equal("apple")
	assert_int(inv.count_of(&"spoiled_turnips")).is_equal(1)
	assert_int(inv.count_of(&"turnips_50")).is_equal(0)
