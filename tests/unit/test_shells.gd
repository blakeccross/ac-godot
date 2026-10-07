extends GdUnitTestSuite

## Sea shells on the beach (`mFI_SetShell`).


class _GridWorld extends Node:
	var grid: WorldGrid = WorldGrid.new()


func before_test() -> void:
	Game.reset_session()
	ItemCatalog.reload()


func after_test() -> void:
	Game.reset_session()


## A town-sized grid (5×6 acres, FG block (1, 1) at cell 0) whose beach row is sand.
func _world() -> _GridWorld:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(5 * 16, 6 * 16, 2.0, Vector3.ZERO)
	for z: int in 6 * 16:
		for x: int in 5 * 16:
			var beach: bool = TownSpace.block_of_cell(Vector2i(x, z)).y == TownAssessment.FG_BLOCK_Z
			var t := WorldGrid.Terrain.SAND if beach else WorldGrid.Terrain.GRASS
			world.grid.set_terrain(Vector2i(x, z), t)
	var objects := Node3D.new()
	objects.name = "Objects"
	world.add_child(objects)
	add_child(world)
	return world


func _per_block() -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in Game.shells.keys():
		var b: Vector2i = TownSpace.block_of_cell(ShellUse.cell_from_persist(StringName(str(key))))
		out[b] = int(out.get(b, 0)) + 1
	return out


func test_twenty_wash_up_at_most_four_an_acre_never_by_the_player() -> void:
	var world := _world()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var player_block := Vector2i(2, TownAssessment.FG_BLOCK_Z)
	var placed: int = ShellUse.wash_up(world, ShellUse.FIRST_NUM, player_block, rng)
	## Four acres left, four each.
	assert_int(placed).is_equal(16)
	var per: Dictionary = _per_block()
	assert_bool(per.has(player_block)).is_false()
	for b: Variant in per:
		assert_int(int(per[b])).is_equal(ShellUse.MAX_PER_BLOCK)
		assert_int((b as Vector2i).y).is_equal(TownAssessment.FG_BLOCK_Z)
	for key: Variant in Game.shells:
		var id := StringName(str(Game.shells[key]))
		assert_bool(id in ShellUse.NORMAL or id in ShellUse.RARE).is_true()


func test_even_share_first() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var room: Array[int] = [4, 4, 1, 4]
	var share: Array[int] = ShellUse.divide(room, 7, rng)
	assert_int(share[0] + share[1] + share[2] + share[3]).is_equal(7)
	assert_int(share[2]).is_equal(1)
	for i: int in 4:
		assert_bool(share[i] <= room[i]).is_true()
		assert_bool(share[i] >= 1).is_true()


func test_one_more_every_tenth_minute() -> void:
	var world := _world()
	var rng := RandomNumberGenerator.new()
	var none := Vector2i(-1, -1)
	ShellUse.tick(world, 3, none, rng)
	assert_int(Game.shells_owed).is_equal(0)
	var before: int = Game.shells.size()
	## Pick one up so there is room again.
	var first: String = str(Game.shells.keys()[0])
	world.grid.remove(StringName(first))
	assert_bool(ShellUse.picked(StringName(first))).is_true()
	ShellUse.tick(world, 10, none, rng)
	assert_int(Game.shells.size()).is_equal(before)
	## Same tenth minute: nothing more owed.
	world.grid.remove(StringName(str(Game.shells.keys()[0])))
	ShellUse.picked(StringName(str(Game.shells.keys()[0])))
	ShellUse.tick(world, 10, none, rng)
	assert_int(Game.shells.size()).is_equal(before - 1)


func test_rare_one_in_four() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var rare: int = 0
	for _i: int in 4000:
		if ShellUse.pick(rng) in ShellUse.RARE:
			rare += 1
	assert_int(rare).is_between(850, 1150)


func test_prices_and_saves() -> void:
	assert_int(ShopBook.sell_price(ItemCatalog.get_item(&"white_scallop"))).is_equal(450)
	assert_int(ShopBook.sell_price(ItemCatalog.get_item(&"wentletrap"))).is_equal(20)
	Game.shells["shell_20_90"] = "conch"
	var data: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(data)
	assert_str(str(Game.shells.get("shell_20_90", ""))).is_equal("conch")
	assert_int(Game.shells_owed).is_equal(ShellUse.FIRST_NUM)
