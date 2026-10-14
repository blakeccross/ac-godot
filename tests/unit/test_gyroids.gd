extends GdUnitTestSuite

## Gyroids: buried after rain (`mEnv_PreRainNowFine_Init` → `mAGrw_SetHaniwa`) and their
## dance in a room (`ac_hnw_common.c`).


class _GridWorld extends Node:
	var grid: WorldGrid = WorldGrid.new()


func before_test() -> void:
	Game.reset_session()
	ItemCatalog.reload()


func after_test() -> void:
	Game.reset_session()


func test_fine_weather_after_rain_orders_them() -> void:
	assert_bool(Rainbow.pre_rain_now_fine(&"rain", &"clear")).is_true()
	assert_bool(Rainbow.pre_rain_now_fine(&"snow", &"sakura")).is_true()
	assert_bool(Rainbow.pre_rain_now_fine(&"clear", &"clear")).is_false()
	assert_bool(Rainbow.pre_rain_now_fine(&"rain", &"rain")).is_false()


func _town() -> _GridWorld:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(80, 96, 2.0, Vector3.ZERO)
	for z: int in 96:
		for x: int in 80:
			world.grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.GRASS)
	add_child(world)
	return world


func test_three_different_gyroids_in_three_acres() -> void:
	if FtrCatalog.list(BuriedUse.HANIWA_BIRTH).is_empty():
		return
	var world := _town()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var cells: Array[Vector2i] = BuriedUse.bury_gyroids(world, world.grid, rng)
	assert_int(cells.size()).is_equal(BuriedUse.HANIWA_NUM)
	var blocks: Array = []
	var items: Array = []
	for cell: Vector2i in cells:
		blocks.append(VillagerWalk.block_from_cell(cell))
		var rec: Dictionary = BuriedUse.record(BuriedUse.persist_id(cell))
		assert_str(str(rec.get(BuriedUse.KEY_KIND, ""))).is_equal(String(BuriedUse.KIND_ITEM))
		items.append(str(rec.get(BuriedUse.KEY_ITEM, "")))
	for b: Variant in blocks:
		assert_int(blocks.count(b)).is_equal(1)
	for it: Variant in items:
		assert_int(items.count(it)).is_equal(1)
		assert_bool(FtrCatalog.list(BuriedUse.HANIWA_BIRTH).has(StringName(str(it)))).is_true()


func test_renewal_buries_them_once() -> void:
	if FtrCatalog.list(BuriedUse.HANIWA_BIRTH).is_empty():
		return
	var world := _town()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	Game.haniwa_scheduled = true
	BuriedUse.renew(world, world.grid, rng)
	assert_bool(Game.haniwa_scheduled).is_false()
	var gyroids := 0
	var list: Array[StringName] = FtrCatalog.list(BuriedUse.HANIWA_BIRTH)
	for key: Variant in Game.buried_deposits.keys():
		var rec: Dictionary = BuriedUse.record(StringName(str(key)))
		if list.has(StringName(str(rec.get(BuriedUse.KEY_ITEM, "")))):
			gyroids += 1
	assert_int(gyroids).is_equal(BuriedUse.HANIWA_NUM)


func test_dance_counter() -> void:
	assert_int(GyroidRhythm.haniwa_index(0x16C)).is_equal(0)
	assert_int(GyroidRhythm.haniwa_index(0x16C + 126)).is_equal(126)
	assert_int(GyroidRhythm.haniwa_index(0x16B)).is_equal(-1)
	## Two steps a beat at 120 BPM: four a second.
	assert_float(GyroidRhythm.steps(1.0)).is_equal_approx(4.0, 0.0001)
	assert_float(GyroidRhythm.counter(2.25, 0)).is_equal_approx(0.25, 0.0001)
	## Sputnoid plays its clip twice a step.
	assert_float(GyroidRhythm.counter(0.75, 12)).is_equal_approx(0.5, 0.0001)
	## Plinkoids take two steps for one clip.
	assert_float(GyroidRhythm.counter(0.5, 122)).is_equal_approx(0.25, 0.0001)
	assert_float(GyroidRhythm.counter(1.5, 122)).is_equal_approx(0.75, 0.0001)
	assert_float(GyroidRhythm.clip_frame(0.5, 21.0)).is_equal_approx(11.0, 0.0001)
