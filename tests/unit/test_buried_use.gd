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


func _hole_world() -> _GridWorld:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	for z: int in 16:
		for x: int in 16:
			world.grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.GRASS)
	var objects := Node3D.new()
	objects.name = "Objects"
	world.add_child(objects)
	add_child(world)
	return world


## `bIT_common_bury_after`: a pitfall seed in a hole is a hidden trap; anything else a
## marked deposit that digs back up.
func test_bury_into_a_hole_only() -> void:
	var world := _hole_world()
	var ctx := InteractionContext.new()
	ctx.world = world
	var cell := Vector2i(5, 5)
	assert_bool(BuriedUse.bury(ctx, cell, BuriedUse.PITFALL_ITEM)).is_false()
	assert_bool(HoleUse.dig(ctx, cell, false)).is_true()
	assert_bool(BuriedUse.bury(ctx, cell, BuriedUse.PITFALL_ITEM)).is_true()
	var pid: StringName = world.grid.occupant_at(cell)
	assert_bool(BuriedUse.is_pitfall(pid)).is_true()
	assert_bool(Game.is_hole(HoleUse.persist_id(cell))).is_false()
	## Nothing marks a pitfall above ground.
	await get_tree().process_frame
	for child: Node in world.get_node("Objects").get_children():
		assert_bool(child.is_queued_for_deletion() or child.get("persist_id") != pid).is_true()
	var other := Vector2i(7, 5)
	HoleUse.dig(ctx, other, false)
	assert_bool(BuriedUse.bury(ctx, other, &"apple")).is_true()
	var deposit: StringName = world.grid.occupant_at(other)
	assert_str(String(BuriedUse.kind_of(deposit))).is_equal(String(BuriedUse.KIND_ITEM))
	assert_str(str(BuriedUse.record(deposit).get(BuriedUse.KEY_ITEM))).is_equal("apple")


## `bIT_actor_pit_fall` / `pit_exit`: the trap opens into a hole, then closes to bare ground.
func test_pitfall_springs_open_then_closes() -> void:
	var world := _hole_world()
	var ctx := InteractionContext.new()
	ctx.world = world
	var cell := Vector2i(6, 6)
	HoleUse.dig(ctx, cell, false)
	BuriedUse.bury(ctx, cell, BuriedUse.PITFALL_ITEM)
	var hole: Node3D = BuriedUse.spring_pitfall(world, world.grid, cell)
	assert_object(hole).is_not_null()
	assert_bool(Game.is_hole(HoleUse.persist_id(cell))).is_true()
	assert_bool(BuriedUse.is_pitfall(world.grid.occupant_at(cell))).is_false()
	## Sprung once only.
	assert_object(BuriedUse.spring_pitfall(world, world.grid, cell)).is_null()
	BuriedUse.close_pit(world, cell)
	await await_millis(int(BuriedUse.PIT_CLOSE_TICKS * DecompTime.TICK_SEC * 1000.0) + 400)
	assert_bool(Game.is_hole(HoleUse.persist_id(cell))).is_false()
	assert_bool(world.grid.is_occupied(cell)).is_false()


func test_bury_tag_needs_a_hole_and_a_scoop() -> void:
	var inv: Inventory = Game.inventory
	inv.add(ItemCatalog.get_item(BuriedUse.PITFALL_ITEM), 1)
	var idx: int = -1
	for i: int in Inventory.POCKET_SLOTS:
		var s: InventorySlot = inv.slot_at(i)
		if s != null and not s.is_empty() and s.item.item_id == BuriedUse.PITFALL_ITEM:
			idx = i
	assert_int(idx).is_greater_equal(0)
	inv.bury_ready = false
	assert_bool(inv.tags_for_slot(idx).has("Bury")).is_false()
	inv.bury_ready = true
	assert_bool(inv.tags_for_slot(idx).has("Bury")).is_true()
	inv.bury_ready = false


## `setup_main_Get_scoop`: full pockets still dig it up; with no one to swap, it goes back in.
func test_full_pockets_dig_it_up_then_bury_it_again() -> void:
	var world := _hole_world()
	var ctx := InteractionContext.new()
	ctx.world = world
	ctx.inventory = Inventory.new()
	var fork: ItemData = ItemCatalog.get_item(&"knife_and_fork")
	for i: int in Inventory.POCKET_SLOTS:
		ctx.inventory.add_to_empty_slot(fork, 1)
	var cell := Vector2i(5, 5)
	HoleUse.dig(ctx, cell, false)
	BuriedUse.bury(ctx, cell, &"conch")
	assert_bool(BuriedUse.dig(ctx, cell)).is_true()
	assert_bool(bool(BuriedUse.last_find["banked"])).is_false()
	assert_bool(Game.is_hole(HoleUse.persist_id(cell))).is_true()
	await BuriedUse.report(ctx)
	var deposit: StringName = world.grid.occupant_at(cell)
	assert_str(str(BuriedUse.record(deposit).get(BuriedUse.KEY_ITEM))).is_equal("conch")


func test_dig_report_asks_to_swap_when_full() -> void:
	var t := DigReport.new(&"apple", false)
	t.current_msg = DigReport.MSG_GOT
	assert_int(int(t.next_step()["msg"])).is_equal(DigReport.MSG_FULL)
	t.picked(DigReport.MSG_FULL, 0)
	assert_bool(t.swap).is_true()
	var ok := DigReport.new(&"apple", true)
	ok.current_msg = DigReport.MSG_GOT
	assert_bool(ok.next_step().is_empty()).is_true()


func test_paying_off_the_loan_queues_the_cheer() -> void:
	Game.inventory.set_loan(100)
	Game.inventory.set_wallet(500)
	PostUse.repay_amount(-1)
	assert_str(String(Game.complete_payment)).is_equal(String(Game.PAYMENT_HOUSE))
