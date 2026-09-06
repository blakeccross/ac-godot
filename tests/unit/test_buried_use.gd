class_name TestBuriedUse
extends GdUnitTestSuite

## Daily fossils + shine spots (`mMsm_DepositFossil` / `mAGrw_SetDigItem`).


class _GridWorld extends Node:
	var grid: WorldGrid = WorldGrid.new()


func before_test() -> void:
	Game.reset_session()
	ItemCatalog.reload()
	Clock.reset_to_default()
	Clock.paused = true


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_renew_places_fossils_and_shine() -> void:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	for z: int in 16:
		for x: int in 16:
			world.grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.GRASS)
	add_child(world)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	BuriedUse.renew(world, world.grid, rng)
	var fossils := 0
	var shines := 0
	for key: Variant in Game.buried_deposits.keys():
		var kind: StringName = BuriedUse.kind_of(StringName(str(key)))
		if kind == BuriedUse.KIND_FOSSIL:
			fossils += 1
		elif kind == BuriedUse.KIND_SHINE:
			shines += 1
	assert_int(fossils).is_equal(BuriedUse.FOSSIL_MAX)
	assert_int(shines).is_equal(1)


func test_renew_replaces_shine_keeps_fossil_cap() -> void:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	for z: int in 16:
		for x: int in 16:
			world.grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.GRASS)
	add_child(world)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	BuriedUse.renew(world, world.grid, rng)
	var first_shine := ""
	for key: Variant in Game.buried_deposits.keys():
		if BuriedUse.kind_of(StringName(str(key))) == BuriedUse.KIND_SHINE:
			first_shine = str(key)
	assert_str(first_shine).is_not_equal("")
	rng.seed = 99
	BuriedUse.renew(world, world.grid, rng)
	var fossils := 0
	var shines := 0
	var shine_key := ""
	for key: Variant in Game.buried_deposits.keys():
		var pid := StringName(str(key))
		if BuriedUse.kind_of(pid) == BuriedUse.KIND_FOSSIL:
			fossils += 1
		elif BuriedUse.kind_of(pid) == BuriedUse.KIND_SHINE:
			shines += 1
			shine_key = str(key)
	assert_int(fossils).is_equal(BuriedUse.FOSSIL_MAX)
	assert_int(shines).is_equal(1)
	assert_str(shine_key).is_not_equal(first_shine)


func test_visuals_match_kind() -> void:
	assert_that(BuriedUse.VISUAL_CRACK).is_equal(&"BURIED_CRACK")
	assert_that(BuriedUse.VISUAL_SHINE).is_equal(&"SHINE_SPOT")
	assert_bool(FieldCatalog.is_ground_decal(&"BURIED_CRACK")).is_true()
	assert_bool(FieldCatalog.is_ground_decal(&"SHINE_SPOT")).is_true()
	var crack: PackedStringArray = FieldCatalog.mesh_paths(&"BURIED_CRACK")
	if not crack.is_empty():
		assert_str(crack[0]).contains("obj_crack0")
	var shine: PackedStringArray = FieldCatalog.mesh_paths(&"SHINE_SPOT")
	if not shine.is_empty():
		assert_str(shine[0]).contains("ef_anahikari")


func test_deposit_attrs_match_decomp() -> void:
	## `mCoBG_CheckHole_OrgAttr` / `CheckSandHole_ClData`.
	assert_bool(FieldCatalog.is_diggable_attr(0)).is_true()
	assert_bool(FieldCatalog.is_diggable_attr(2)).is_true()
	assert_bool(FieldCatalog.is_diggable_attr(3)).is_false() ## grass3 excluded
	assert_bool(FieldCatalog.is_diggable_attr(4)).is_true()
	assert_bool(FieldCatalog.is_diggable_attr(FieldCatalog.SAND_ATTR)).is_true()
	assert_bool(FieldCatalog.is_diggable_attr(7)).is_false() ## stone
	assert_bool(FieldCatalog.is_sand_hole_attr(FieldCatalog.SAND_ATTR)).is_true()
	assert_bool(FieldCatalog.is_sand_hole_attr(0)).is_false()
	assert_bool(TownFieldGenerator.is_deposit_blocked_acre(TownFieldGenerator.T_PLAYER_HOUSE)).is_true()
	assert_bool(TownFieldGenerator.is_deposit_blocked_acre(TownFieldGenerator.T_SHRINE)).is_true()
	assert_bool(TownFieldGenerator.is_deposit_blocked_acre(TownFieldGenerator.T_TRACKS_STATION)).is_true()
	assert_bool(TownFieldGenerator.is_deposit_blocked_acre(70)).is_true() ## pool band
	assert_bool(TownFieldGenerator.is_deposit_blocked_acre(0)).is_false()


func test_shine_refuses_sand_terrain_without_layout() -> void:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	for z: int in 16:
		for x: int in 16:
			world.grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.SAND)
	add_child(world)
	assert_bool(BuriedUse._can_deposit(world.grid, Vector2i(8, 8), null, true)).is_false()
	assert_bool(BuriedUse._can_deposit(world.grid, Vector2i(8, 8), null, false)).is_true()


func test_deposit_skips_occupied_and_water() -> void:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	for z: int in 16:
		for x: int in 16:
			world.grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.GRASS)
	world.grid.set_terrain(Vector2i(5, 5), WorldGrid.Terrain.WATER)
	world.grid.place(&"tree_1", Vector2i(6, 6), Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	add_child(world)
	assert_bool(BuriedUse._can_deposit(world.grid, Vector2i(5, 5))).is_false()
	assert_bool(BuriedUse._can_deposit(world.grid, Vector2i(6, 6))).is_false()
	assert_bool(BuriedUse._can_deposit(world.grid, Vector2i(7, 7))).is_true()
