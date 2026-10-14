extends GdUnitTestSuite

## The signboard from Nook's (`ac_sign`).


class _GridWorld extends Node3D:
	var grid: WorldGrid = WorldGrid.new()


func before_test() -> void:
	Game.reset_session()
	ItemCatalog.reload()


func after_test() -> void:
	Game.reset_session()


func _world() -> _GridWorld:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(16, 16, 2.0, Vector3.ZERO)
	var objects := Node3D.new()
	objects.name = "Objects"
	world.add_child(objects)
	add_child(world)
	return world


func test_put_up_post_and_take_down() -> void:
	assert_object(ItemCatalog.get_item(SignboardUse.ITEM_ID)).is_not_null()
	var world := _world()
	var cell := Vector2i(5, 5)
	assert_bool(SignboardUse.place(world, cell)).is_true()
	var pid: StringName = SignboardUse.persist_id(cell)
	assert_str(String(world.grid.occupant_at(cell))).is_equal(String(pid))
	assert_int(get_tree().get_nodes_in_group(SignboardUse.GROUP).size()).is_greater(0)
	## Not on top of another.
	assert_bool(SignboardUse.place(world, cell)).is_false()
	assert_object(SignboardUse.design_of(pid)).is_null()
	var design := DesignPattern.generate(DesignPattern.Motif.CHECK, 3)
	SignboardUse.post(pid, design)
	assert_int(SignboardUse.design_of(pid).palette).is_equal(3)
	## Saved with the town.
	var data: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(data)
	assert_int(SignboardUse.design_of(pid).palette).is_equal(3)
	SignboardUse.take(world, pid)
	assert_bool(world.grid.is_occupied(cell)).is_false()
	assert_bool(Game.signboards.has(String(pid))).is_false()


func test_visitors_are_told_hands_off() -> void:
	var sign: Node = auto_free(load("res://scenes/world/signboard.tscn").instantiate())
	var talk = sign.get_script().PostTalk.new()
	Game.foreigner = true
	assert_int(talk.start_msg()).is_equal(SignboardUse.MSG_HANDS_OFF)
	Game.foreigner = false
	assert_int(talk.start_msg()).is_equal(SignboardUse.MSG_POST)
	assert_int(talk.picked(SignboardUse.MSG_POST, 0)).is_equal(-1)
	assert_bool(talk.post).is_true()
