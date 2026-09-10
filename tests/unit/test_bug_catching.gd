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


const STEP := 1.0 / 60.0

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
	Netting.reset()


func after_test() -> void:
	Game.notice_posted.disconnect(_on_notice)
	Netting.reset()
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


func test_net_swing_catches_bug_in_volume() -> void:
	var ctx: InteractionContext = _ctx()
	var field: BugField = ctx.world.get("bugs") as BugField
	field.auto_spawn = false
	var bug: BugData = BugCatalog.get_bug(&"common_butterfly")
	var actor: BugActor = field.spawn(bug, BugData.Habitat.FLYING, Vector3(0.0, 0.0, 0.5))
	assert_that(actor).is_not_null()
	var out: Netting.Outcome = Netting.swing(ctx, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	assert_bool(out.caught()).is_true()
	assert_that(out.bug.id).is_equal(&"common_butterfly")
	assert_int(ctx.inventory.count_of(bug.id)).is_equal(1)


func test_net_miss_reports_nothing_caught() -> void:
	var ctx: InteractionContext = _ctx()
	var field: BugField = ctx.world.get("bugs") as BugField
	field.auto_spawn = false
	field.spawn(BugCatalog.get_bug(&"common_butterfly"), BugData.Habitat.FLYING, Vector3(12.0, 0.0, 12.0))
	var out: Netting.Outcome = Netting.swing(ctx, Vector3.ZERO, Vector3.FORWARD)
	assert_bool(out.missed).is_true()


func test_swing_resolves_on_catch_frame() -> void:
	assert_float(Netting.SWING_CATCH_FRAME).is_equal(6.0)
	var ctx: InteractionContext = _ctx()
	var net: ItemData = ItemCatalog.get_item(&"net")
	assert_that(net).is_not_null()
	assert_int(ctx.inventory.add(net, 1)).is_equal(0)
	assert_bool(ctx.inventory.equip_slot(0)).is_true()
	var action: Interaction = ToolUse.field_action(ctx)
	assert_that(action).is_not_null()
	assert_str(String(action.id)).is_equal(String(Interaction.SWING_NET))
	assert_float(action.effect_frame).is_equal(Netting.SWING_CATCH_FRAME)


func test_caught_bug_is_finished_and_flagged() -> void:
	var ctx: InteractionContext = _ctx()
	var field: BugField = ctx.world.get("bugs") as BugField
	field.auto_spawn = false
	var actor: BugActor = field.spawn(
		BugCatalog.get_bug(&"common_butterfly"), BugData.Habitat.FLYING, Vector3(0.0, 0.0, 0.5)
	)
	Netting.swing(ctx, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	assert_bool(actor.caught).is_true()
	assert_bool(actor.finished).is_true()


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
	assert_bool(pairs.has([38, 8])).is_true()   ## ant on candy
	assert_bool(pairs.has([38, 9])).is_true()   ## ant on trash
	assert_bool(pairs.has([28, 9])).is_true()   ## cockroach on trash


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
