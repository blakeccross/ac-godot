class_name TestBugCatching
extends GdUnitTestSuite

## Framework + spawn + net-catch coverage. Program-specific movement is exercised
## by `test_bug_programs.gd`.

class _FacingActor extends Node3D:
	var yaw: float = 0.0

	func facing_yaw() -> float:
		return yaw


class _GridWorld extends Node:
	var grid: WorldGrid = WorldGrid.new()
	var layout: WorldData = WorldData.new()
	var bugs: BugField = BugField.new()


const STEP := DecompTime.TICK_SEC

var _heard: Array[String] = []


func before_test() -> void:
	Game.reset_session()
	ItemCatalog.reload()
	BugCatalog.reload()
	BugSpawnTable.reload()
	BugCatalog.seed_rng(1)
	Clock.reset_to_default()
	Clock.paused = true
	Clock.month = 6
	Clock.hour = 10
	_heard.clear()
	Game.notice_posted.connect(_on_notice)


func after_test() -> void:
	Game.notice_posted.disconnect(_on_notice)
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func _on_notice(text: String) -> void:
	_heard.append(text)


func test_catalog_loads_bugs_and_filters_windows() -> void:
	var butterfly: BugData = BugCatalog.get_bug(&"common_butterfly")
	assert_that(butterfly).is_not_null()
	assert_int(BugCatalog.all_bugs().size()).is_greater(30)
	var noon: Array[BugData] = BugCatalog.available(6, 10)
	assert_bool(noon.has(butterfly)).is_true()
	assert_bool(BugCatalog.available(1, 10).has(butterfly)).is_false()


func test_program_table_matches_decomp_aINS_program_type() -> void:
	## `aINS_program_type[]`: mantis + snail run the ladybug program; mosquito is KA;
	## spider is MINO; bee is SEMI; ant is DANGO.
	assert_int(BugCatalog.get_bug(&"mantis").program).is_equal(BugData.Program.TENTOU)
	assert_int(BugCatalog.get_bug(&"snail").program).is_equal(BugData.Program.TENTOU)
	assert_int(BugCatalog.get_bug(&"mosquito").program).is_equal(BugData.Program.KA)
	assert_int(BugCatalog.get_bug(&"spider").program).is_equal(BugData.Program.MINO)
	assert_int(BugCatalog.get_bug(&"bee").program).is_equal(BugData.Program.SEMI)
	assert_int(BugCatalog.get_bug(&"ant").program).is_equal(BugData.Program.DANGO)
	assert_int(BugCatalog.get_bug(&"common_butterfly").program).is_equal(BugData.Program.CHOU)
	assert_int(BugCatalog.get_bug(&"drone_beetle").program).is_equal(BugData.Program.KABUTO)


func test_term_for_hour_matches_decomp_buckets() -> void:
	assert_that(BugData.term_for_hour(3)).is_equal(BugData.TimeTerm.T0)
	assert_that(BugData.term_for_hour(23)).is_equal(BugData.TimeTerm.T0)
	assert_that(BugData.term_for_hour(4)).is_equal(BugData.TimeTerm.T1)
	assert_that(BugData.term_for_hour(12)).is_equal(BugData.TimeTerm.T2)
	assert_that(BugData.term_for_hour(16)).is_equal(BugData.TimeTerm.T3)
	assert_that(BugData.term_for_hour(18)).is_equal(BugData.TimeTerm.T4)
	assert_that(BugData.term_for_hour(20)).is_equal(BugData.TimeTerm.T5)


func test_spawn_table_january_uses_other_pool_on_trees() -> void:
	var entries: Array[BugSpawnEntry] = BugSpawnTable.entries_for(1, 12)
	var tree_types: Array[int] = []
	for entry: BugSpawnEntry in entries:
		if entry.spawn_area == 0:
			tree_types.append(entry.type_index)
	assert_int(tree_types.size()).is_equal(1)
	assert_int(tree_types[0]).is_equal(35)


func test_spawn_table_august_noon_includes_cicada_not_bagworm() -> void:
	var entries: Array[BugSpawnEntry] = BugSpawnTable.entries_for(8, 12)
	var types: Array[int] = []
	for entry: BugSpawnEntry in entries:
		types.append(entry.type_index)
	assert_bool(types.has(4)).is_true()
	assert_bool(types.has(35)).is_false()


func test_roll_spawn_entry_respects_hundred_point_gate() -> void:
	var pool: Array[BugSpawnEntry] = []
	var entry := BugSpawnEntry.new()
	entry.type_index = 35
	entry.spawn_area = 0
	entry.weight = 2.0
	pool.append(entry)
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	var misses: int = 0
	for _i: int in 100:
		if BugCatalog.roll_spawn_entry(pool, rng) == null:
			misses += 1
	assert_int(misses).is_greater(0)


func test_field_spawn_cap_matches_decomp_make_new() -> void:
	assert_int(BugField.MAX_ACTORS).is_equal(9)
	assert_int(BugField.MAX_FIELD_SPAWNS).is_equal(8)


func test_birth_sum_swarms_are_red_dragonfly_and_firefly() -> void:
	## `l_insect_birth_sum`: RED_DRAGONFLY (10) and FIREFLY (27) birth 6-8; ants,
	## mosquitoes and everyone else birth 1.
	assert_that(BugField.BIRTH_SUM[10]).is_equal(Vector2i(6, 3))
	assert_that(BugField.BIRTH_SUM[27]).is_equal(Vector2i(6, 3))
	assert_that(BugField.BIRTH_SUM[38]).is_equal(Vector2i(1, 0))
	assert_that(BugField.BIRTH_SUM[39]).is_equal(Vector2i(1, 0))
	assert_that(BugField.BIRTH_SUM[9]).is_equal(Vector2i(1, 0))


func test_life_time_default_is_two_game_hours() -> void:
	assert_int(BugActor.LIFE_TIME_FRAMES).is_equal(216000)


func test_auto_spawn_is_once_per_acre_and_skips_occupied() -> void:
	var layout: WorldData = WorldGenerator.authored_test_town()
	var grid := WorldGrid.new()
	grid.configure_from_world(layout)
	var field := BugField.new()
	field.auto_spawn = true
	field.configure(grid, layout)
	field.seed_rng(1)
	Clock.month = 6
	Clock.hour = 12
	var sense := BugActor.Sense.new()
	sense.player_position = grid.cell_to_world(Vector2i(8, 8))
	field.tick(STEP, sense)
	var after_first: int = field.actor_count()
	assert_int(after_first).is_less_equal(BugField.MAX_FIELD_SPAWNS)
	field.tick(STEP, sense)
	field.tick(STEP, sense)
	assert_int(field.actor_count()).is_equal(after_first)
	for actor: BugActor in field.actors:
		assert_that(BugHabitats.acre_of_world_pos(grid, actor.position)).is_equal(
			BugHabitats.acre_of_world_pos(grid, sense.player_position)
		)


func test_auto_spawn_retries_on_new_acre() -> void:
	var layout := WorldData.new()
	layout.columns = 32
	layout.rows = 16
	layout.bake()
	for x: int in 32:
		for z: int in 16:
			layout.set_terrain_cell(Vector2i(x, z), WorldGrid.Terrain.GRASS)
	var grid := WorldGrid.new()
	grid.configure_from_world(layout)
	var field := BugField.new()
	field.auto_spawn = true
	field.configure(grid, layout)
	field.seed_rng(42)
	Clock.month = 6
	Clock.hour = 12
	var sense := BugActor.Sense.new()
	sense.player_position = grid.cell_to_world(Vector2i(4, 8))
	field.tick(STEP, sense)
	var first_acre: Vector2i = field._spawned_acre
	assert_that(first_acre).is_equal(Vector2i(1, 1))
	sense.player_position = grid.cell_to_world(Vector2i(20, 8))
	field.tick(STEP, sense)
	assert_that(field._spawned_acre).is_equal(Vector2i(2, 1))
	assert_that(field._spawned_acre).is_not_equal(first_acre)


func test_catch_message_numbers() -> void:
	var butterfly: BugData = BugCatalog.get_bug(&"common_butterfly")
	assert_int(butterfly.catch_msg).is_equal(0xA2C)
	assert_int(BugData.catch_msg_for_type(0)).is_equal(0xA2C)


func test_net_candidates_register_catch_ranges() -> void:
	var ctx: InteractionContext = _ctx()
	var field: BugField = ctx.world.get("bugs") as BugField
	var butterfly: BugActor = field.spawn(
		BugCatalog.get_bug(&"common_butterfly"), BugData.Habitat.FLYING, Vector3(0.0, 1.0, 1.0)
	)
	var rows: Array[NetSwing.Candidate] = field.net_candidates(Vector3.ZERO)
	assert_int(rows.size()).is_equal(1)
	assert_object(rows[0].target).is_same(butterfly)
	## `aINS_get_catch_range`: butterflies register 24 GX.
	assert_float(rows[0].range_gx).is_equal(24.0)
	## Caught or let-go insects stop registering (`bit_1`).
	butterfly.release()
	assert_array(field.net_candidates(Vector3.ZERO)).is_empty()


func test_begin_catch_takes_bug_off_the_field() -> void:
	var ctx: InteractionContext = _ctx()
	var field: BugField = ctx.world.get("bugs") as BugField
	var actor: BugActor = field.spawn(
		BugCatalog.get_bug(&"common_butterfly"), BugData.Habitat.FLYING, Vector3(0.0, 0.0, 0.5)
	)
	var catch_: Netting.Catch = Netting.begin_catch(actor)
	assert_object(catch_).is_not_null()
	assert_bool(actor.caught).is_true()
	assert_bool(actor.finished).is_true()
	assert_int(catch_.report_msg()).is_equal(0xA2C)


func test_bank_puts_catch_in_pockets_and_on_the_record() -> void:
	var ctx: InteractionContext = _ctx()
	var field: BugField = ctx.world.get("bugs") as BugField
	var bug: BugData = BugCatalog.get_bug(&"common_butterfly")
	var catch_: Netting.Catch = Netting.begin_catch(field.spawn(bug, BugData.Habitat.FLYING, Vector3.ZERO))
	assert_bool(Netting.bank(catch_, ctx.inventory)).is_true()
	assert_int(ctx.inventory.count_of(bug.id)).is_equal(1)
	assert_bool(Game.catalog.has_insect(bug.type_index)).is_true()


func test_full_pockets_still_record_and_release() -> void:
	var ctx: InteractionContext = _ctx()
	var field: BugField = ctx.world.get("bugs") as BugField
	var filler: ItemData = ItemCatalog.get_item(&"axe")
	for i: int in Inventory.POCKET_SLOTS:
		ctx.inventory.add(filler, 1)
	var bug: BugData = BugCatalog.get_bug(&"common_butterfly")
	var catch_: Netting.Catch = Netting.begin_catch(field.spawn(bug, BugData.Habitat.FLYING, Vector3.ZERO))
	assert_bool(Netting.bank(catch_, ctx.inventory)).is_false()
	assert_int(ctx.inventory.count_of(bug.id)).is_equal(0)
	## `setup_main_Notice_net` sets the record bit whether or not it fit.
	assert_bool(Game.catalog.has_insect(bug.type_index)).is_true()
	var freed: BugActor = Netting.release(catch_, field, Vector3(0.0, 1.0, 0.0))
	assert_object(freed).is_not_null()
	assert_bool(freed.released).is_true()


func test_last_missing_insect_gets_the_complete_report() -> void:
	## `mSM_CHECK_LAST_INSECT_GET`: all but this one on the record.
	for i: int in Netting.INSECT_RECORD_NUM:
		if i != 5:
			Game.catalog.record_insect(i)
	assert_bool(Netting.completes_record(5)).is_true()
	assert_bool(Netting.completes_record(4)).is_false()
	Game.catalog.record_insect(5)
	assert_bool(Netting.completes_record(5)).is_false()


func test_mushi_msg_numbers() -> void:
	## `Player_actor_Get_mushi_msg_num`.
	assert_int(Netting.mushi_msg(0)).is_equal(0xA2C)
	assert_int(Netting.mushi_msg(0x1F)).is_equal(0xA2C + 0x1F)
	assert_int(Netting.mushi_msg(0x20)).is_equal(0x2FA1 + 0x20)


func test_insect_record_round_trips_save() -> void:
	Game.catalog.record_insect(3)
	Game.catalog.record_insect(35)
	var book := CatalogBook.new()
	book.apply_snapshot(Game.catalog.to_save())
	assert_bool(book.has_insect(3)).is_true()
	assert_bool(book.has_insect(35)).is_true()
	assert_int(book.insect_count()).is_equal(2)


func test_stop_net_is_seen_for_one_insect_frame() -> void:
	var ctx: InteractionContext = _ctx()
	var field: BugField = ctx.world.get("bugs") as BugField
	field.notify_stop_net(Vector3(1.0, 0.0, 1.0))
	var sense := BugActor.Sense.new()
	field.tick(STEP, sense)
	assert_bool(sense.net_swing_active).is_true()
	assert_vector(sense.net_swing_origin).is_equal(Vector3(1.0, 0.0, 1.0))
	field.tick(STEP, sense)
	assert_bool(sense.net_swing_active).is_false()


func test_npc_on_line_uses_the_villager_pipe() -> void:
	var actor := Node3D.new()
	auto_free(actor)
	add_child(actor)
	var ctx := InteractionContext.new()
	ctx.actor = actor
	var villager: Villager = auto_free(load("res://scenes/actors/villager.tscn").instantiate()) as Villager
	add_child(villager)
	## Villagers stay hidden until the roster places them.
	villager.visible = true
	villager.global_position = Vector3(0.0, 0.0, 2.0)
	var start := Vector3(0.0, 0.5, 0.0)
	var end := Vector3(0.0, 0.5, 2.75)
	assert_object(Netting.npc_on_line(ctx, start, end)).is_same(villager)
	## Beyond the 20 GX pipe radius, sideways.
	villager.global_position = Vector3(Netting.NPC_PIPE_RADIUS_GX * FieldCatalog.GX_TO_METERS + 0.2, 0.0, 2.0)
	assert_object(Netting.npc_on_line(ctx, start, end)).is_null()
	## A hidden (indoor) villager never registers.
	villager.global_position = Vector3(0.0, 0.0, 2.0)
	villager.visible = false
	assert_object(Netting.npc_on_line(ctx, start, end)).is_null()


func _ctx() -> InteractionContext:
	var world := _GridWorld.new()
	world.layout.columns = 16
	world.layout.rows = 16
	world.layout.bake()
	world.bugs.configure(world.grid, world.layout)
	world.bugs.auto_spawn = false
	var actor := _FacingActor.new()
	actor.yaw = 0.0
	var ctx := InteractionContext.new()
	ctx.actor = actor
	ctx.inventory = Game.inventory
	ctx.world = world
	return ctx


func test_scheduler_pool_includes_ant_and_cockroach_additions() -> void:
	Clock.month = 7
	Clock.hour = 12
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var pool: Array[BugSpawnEntry] = BugSpawnScheduler.build_pool(rng)
	var pairs: Array = []
	for e: BugSpawnEntry in pool:
		pairs.append([e.type_index, e.spawn_area])
	assert_bool(pairs.has([38, BugSpawnScheduler.AREA_ON_CANDY])).is_true()
	assert_bool(pairs.has([38, BugSpawnScheduler.AREA_ON_TRASH])).is_true()
	assert_bool(pairs.has([28, BugSpawnScheduler.AREA_ON_TRASH])).is_true()
	## Not the table's rock / underground areas.
	assert_bool(pairs.has([38, 8]) or pairs.has([38, 9])).is_false()


func _bait_town() -> Array:
	var layout: WorldData = WorldGenerator.authored_test_town()
	var grid := WorldGrid.new()
	grid.configure_from_world(layout)
	return [layout, grid]


func _no_cell(_c: Vector2i) -> bool:
	return false


func test_candy_on_the_ground_draws_ants_in_dry_weather() -> void:
	var town: Array = _bait_town()
	var layout: WorldData = town[0]
	var grid: WorldGrid = town[1]
	var acre: Vector2i = BugHabitats.acre_of_world_pos(grid, grid.cell_to_world(Vector2i(8, 8)))
	var candy := BugSpawnScheduler.AREA_ON_CANDY
	assert_bool(BugHabitats.has_spawn_area(candy, layout, grid, acre, _no_cell, false)).is_false()
	Game.field_items[String(FieldItems.persist_id(Vector2i(8, 8)))] = {"id": "candy", "wrapped": false}
	var sites: Array[BugHabitats.Site] = BugHabitats.sites_for_spawn_area(candy, layout, grid, acre, _no_cell, false)
	assert_int(sites.size()).is_equal(1)
	assert_that(sites[0].cell).is_equal(Vector2i(8, 8))
	assert_int(BugData.habitat_from_spawn_area(candy)).is_equal(BugData.Habitat.GROUND)
	## Not in the rain or snow, and a spoiled turnip is trash, not candy.
	assert_bool(BugHabitats.has_spawn_area(candy, layout, grid, acre, _no_cell, true)).is_false()
	Game.weather = &"snow"
	assert_bool(BugHabitats.has_spawn_area(candy, layout, grid, acre, _no_cell, false)).is_false()
	Game.weather = &"clear"
	assert_bool(BugHabitats.has_spawn_area(BugSpawnScheduler.AREA_ON_TRASH, layout, grid, acre, _no_cell, false)).is_false()
	## Nor right at the acre's edge.
	Game.field_items.clear()
	Game.field_items[String(FieldItems.persist_id(Vector2i(0, 0)))] = {"id": "candy", "wrapped": false}
	assert_bool(BugHabitats.has_spawn_area(candy, layout, grid, acre, _no_cell, false)).is_false()


func test_bait_brings_only_ants_and_roaches_and_rocks_do_not() -> void:
	var town: Array = _bait_town()
	var layout: WorldData = town[0]
	var grid: WorldGrid = town[1]
	var acre: Vector2i = BugHabitats.acre_of_world_pos(grid, grid.cell_to_world(Vector2i(8, 8)))
	Clock.month = 7
	Clock.hour = 12
	Game.weather = &"clear"
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var pool: Array[BugSpawnEntry] = BugSpawnScheduler.build_pool(rng)
	## The test town has a rock but no food: the rest of the table stays open.
	var seen: Dictionary = {}
	for _i: int in 60:
		var e: BugSpawnEntry = BugSpawnScheduler.decide(pool, layout, grid, acre, false, _no_cell, rng)
		if e != null:
			seen[e.type_index] = true
	assert_bool(seen.has(38)).is_false()
	assert_int(seen.size()).is_greater(1)
	Game.field_items[String(FieldItems.persist_id(Vector2i(8, 8)))] = {"id": "spoiled_turnips", "wrapped": false}
	for _i: int in 30:
		var e: BugSpawnEntry = BugSpawnScheduler.decide(pool, layout, grid, acre, false, _no_cell, rng)
		assert_object(e).is_not_null()
		assert_bool(e.type_index == 38 or e.type_index == 28).is_true()


func test_scheduler_blends_previous_month_early_in_the_month() -> void:
	Clock.month = 9
	Clock.day = 1
	Clock.hour = 12
	Game.insect_term_month = 9        ## already rolled; pin the offset to 0
	Game.insect_term_offset = 0
	var pool: Array[BugSpawnEntry] = BugSpawnScheduler.build_pool(null)
	var months := {"aug_only": false, "sep_only": false}
	for e: BugSpawnEntry in pool:
		if e.type_index == 4:        ## robust cicada — in Aug noon table, not Sep
			months["aug_only"] = true
		if e.type_index == 13:       ## long locust — Sep noon table
			months["sep_only"] = true
	assert_bool(months["aug_only"]).append_failure_message("no Aug bugs in the Sep-day-1 blend").is_true()
	assert_bool(months["sep_only"]).is_true()


func test_scheduler_no_blend_mid_month() -> void:
	Clock.month = 9
	Clock.day = 20
	Clock.hour = 12
	Game.insect_term_month = 9
	Game.insect_term_offset = 0
	var pool: Array[BugSpawnEntry] = BugSpawnScheduler.build_pool(null)
	for e: BugSpawnEntry in pool:
		assert_int(e.type_index).append_failure_message("Aug cicada leaked into mid-Sep").is_not_equal(4)
