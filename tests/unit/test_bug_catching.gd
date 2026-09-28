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


## Starts a wade into `cell` and runs the set manager's wait out.
func _wade_into(field: BugField, grid: WorldGrid, sense: BugActor.Sense, cell: Vector2i) -> void:
	sense.wade_end = grid.cell_to_world(cell)
	for _i: int in BugField.SET_WAIT_FRAMES + 1:
		field.tick(STEP, sense)
	sense.wade_end = Vector3.INF
	sense.player_position = grid.cell_to_world(cell)
	field.tick(STEP, sense)


func test_no_spawn_without_an_acre_crossing() -> void:
	## `aSOI_insect_set` only runs from the set manager on a wade: loading into an acre or
	## standing in it births nothing.
	var layout: WorldData = WorldGenerator.authored_test_town()
	var grid := WorldGrid.new()
	grid.configure_from_world(layout)
	var field := BugField.new()
	field.configure(grid, layout)
	field.seed_rng(1)
	var sense := BugActor.Sense.new()
	sense.player_position = grid.cell_to_world(Vector2i(8, 8))
	for _i: int in 60:
		field.tick(STEP, sense)
	assert_int(field.actor_count()).is_equal(0)
	assert_that(field._spawned_acre).is_equal(Vector2i(-999, -999))


func test_set_waits_for_the_set_manager_timer() -> void:
	var world: Array = _open_layout()
	var field := BugField.new()
	field.configure(world[1], world[0])
	var sense := BugActor.Sense.new()
	sense.player_position = (world[1] as WorldGrid).cell_to_world(Vector2i(8, 8))
	sense.wade_end = (world[1] as WorldGrid).cell_to_world(Vector2i(9, 8))
	for _i: int in BugField.SET_WAIT_FRAMES - 1:
		field.tick(STEP, sense)
	assert_that(field._spawned_acre).is_equal(Vector2i(-999, -999))
	field.tick(STEP, sense)
	assert_that(field._spawned_acre).is_not_equal(Vector2i(-999, -999))


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
	_wade_into(field, grid, sense, Vector2i(8, 8))
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
	sense.player_position = grid.cell_to_world(Vector2i(20, 8))
	_wade_into(field, grid, sense, Vector2i(4, 8))
	var first_acre: Vector2i = field._spawned_acre
	assert_that(first_acre).is_equal(Vector2i(1, 1))
	_wade_into(field, grid, sense, Vector2i(20, 8))
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
	assert_bool(pairs.has([38, 8])).is_true()   ## ant on candy
	assert_bool(pairs.has([38, 9])).is_true()   ## ant on trash
	assert_bool(pairs.has([28, 9])).is_true()   ## cockroach on trash


func test_spawn_table_uses_decomp_spawn_area_enum() -> void:
	## `l_insect_m_other_t`: PILL_BUG UNDER_ROCK (10), MOLE_CRICKET UNDERGROUND (11),
	## BAGWORM ON_TREE (0) — 8 / 9 are ON_CANDY / ON_TRASH, which only the additions use.
	var pairs: Array = []
	for e: BugSpawnEntry in BugSpawnTable.entries_for(1, 12):
		pairs.append([e.type_index, e.spawn_area])
	assert_array(pairs).contains_exactly_in_any_order([[36, 10], [33, 11], [35, 0]])
	for month: int in range(1, 13):
		for hour: int in [0, 6, 12, 16, 18, 20]:
			for e: BugSpawnEntry in BugSpawnTable.entries_for(month, hour):
				assert_bool(e.spawn_area == 8 or e.spawn_area == 9).is_false()
	assert_int(BugData.habitat_from_spawn_area(10)).is_equal(BugData.Habitat.ROCK)
	assert_int(BugData.habitat_from_spawn_area(11)).is_equal(BugData.Habitat.UNDERGROUND)
	assert_int(BugData.habitat_from_spawn_area(9)).is_equal(BugData.Habitat.GROUND)


func _pool_weight(pool: Array[BugSpawnEntry], type_index: int) -> float:
	var w: float = 0.0
	for e: BugSpawnEntry in pool:
		if e.type_index == type_index:
			w += e.weight
	return w


func test_scheduler_blends_next_month_in_before_it_starts() -> void:
	## Saved term = September (0-based 8), offset 5: the window runs Aug 27 – Aug 31. On
	## Aug 30 (day 3 of it) August weighs 2/6 and September 4/6.
	Clock.year = 2002
	Clock.month = 8
	Clock.day = 30
	Clock.hour = 12
	Game.insect_term_month = 8
	Game.insect_term_offset = 5
	var pool: Array[BugSpawnEntry] = BugSpawnScheduler.build_pool(null)
	var aug: float = _pool_weight(BugSpawnTable.entries_for(8, 12), 4)
	var sep: float = _pool_weight(BugSpawnTable.entries_for(9, 12), 4)
	assert_float(_pool_weight(pool, 4)).is_equal_approx(aug * 2.0 / 6.0 + sep * 4.0 / 6.0, 0.001)
	assert_int(Game.insect_term_month).is_equal(8)


func test_scheduler_no_blend_before_the_window() -> void:
	Clock.year = 2002
	Clock.month = 8
	Clock.day = 20
	Clock.hour = 12
	Game.insect_term_month = 8
	Game.insect_term_offset = 5
	var pool: Array[BugSpawnEntry] = BugSpawnScheduler.build_pool(null)
	assert_float(_pool_weight(pool, 4)).is_equal_approx(
		_pool_weight(BugSpawnTable.entries_for(8, 12), 4), 0.001
	)


func test_scheduler_is_pure_new_month_once_it_starts() -> void:
	## Offset 0: the window starts on Sep 1 itself, where both halves are September.
	Clock.year = 2002
	Clock.month = 9
	Clock.day = 2
	Clock.hour = 12
	Game.insect_term_month = 8
	Game.insect_term_offset = 0
	var pool: Array[BugSpawnEntry] = BugSpawnScheduler.build_pool(null)
	assert_float(_pool_weight(pool, 13)).is_equal_approx(
		_pool_weight(BugSpawnTable.entries_for(9, 12), 13), 0.001
	)


func test_scheduler_renews_the_term_after_the_window() -> void:
	Clock.year = 2002
	Clock.month = 9
	Clock.day = 20
	Clock.hour = 12
	Game.insect_term_month = 8
	Game.insect_term_offset = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	BugSpawnScheduler.build_pool(rng)
	assert_int(Game.insect_term_month).is_equal(9)   ## October, 0-based
	assert_int(Game.insect_term_offset).is_between(0, 5)


func _entry(type_index: int, area: int, weight: float) -> BugSpawnEntry:
	var e := BugSpawnEntry.new()
	e.type_index = type_index
	e.spawn_area = area
	e.weight = weight
	return e


func _open_layout() -> Array:
	var layout := WorldData.new()
	layout.columns = 16
	layout.rows = 16
	layout.bake()
	for x: int in 16:
		for z: int in 16:
			layout.set_terrain_cell(Vector2i(x, z), WorldGrid.Terrain.GRASS)
	var grid := WorldGrid.new()
	grid.configure_from_world(layout)
	return [layout, grid]


func _place(layout: WorldData, kind: StringName, cell: Vector2i, payload: Resource = null) -> void:
	var obj := ObjectPlacement.new()
	obj.id = StringName("%s_%d_%d" % [kind, cell.x, cell.y])
	obj.kind = kind
	obj.cell = cell
	obj.occupy_grid = false
	obj.payload = payload
	layout.objects.append(obj)


func test_flying_near_flowers_falls_back_to_flying_without_flowers() -> void:
	## `aSOI_ins_change_how_to_make`: no flower → FLYING, weight kept.
	var world: Array = _open_layout()
	var one: Array[BugSpawnEntry] = [_entry(0, 12, 30.0)]
	var info: Array[BugSpawnEntry] = BugSpawnScheduler.limit(
		one, world[0], world[1], Vector2i(-1, -1), false
	)
	assert_int(info[0].spawn_area).is_equal(BugHabitats.AREA_FLYING)
	assert_float(info[0].weight).is_equal(30.0)
	_place(world[0], &"flower", Vector2i(6, 6))
	info = BugSpawnScheduler.limit(one, world[0], world[1], Vector2i(-1, -1), false)
	assert_int(info[0].spawn_area).is_equal(BugHabitats.AREA_ON_FLOWER)
	assert_float(info[0].weight).is_equal(30.0)


func test_rain_clears_flower_entries_and_keeps_rain_ones() -> void:
	var world: Array = _open_layout()
	_place(world[0], &"flower", Vector2i(6, 6))
	var pool: Array[BugSpawnEntry] = [_entry(0, 12, 30.0), _entry(3, 1, 5.0), _entry(32, 2, 4.0)]
	var info: Array[BugSpawnEntry] = BugSpawnScheduler.limit(pool, world[0], world[1], Vector2i(-1, -1), true)
	assert_float(info[0].weight).is_equal(0.0)
	assert_float(info[1].weight).is_equal(0.0)
	assert_float(info[2].weight).is_equal(4.0)
	info = BugSpawnScheduler.limit(pool, world[0], world[1], Vector2i(-1, -1), false)
	assert_float(info[2].weight).is_equal(0.0)


func test_candy_on_the_ground_limits_the_pool_to_ants() -> void:
	## `aSOI_ins_limit_insect_data`: with candy lying there only the ON_CANDY entries keep
	## weight, and rocks no longer read as bait (their area is UNDER_ROCK, 10).
	var world: Array = _open_layout()
	_place(world[0], &"rock", Vector2i(5, 5))
	Game.weather = &"clear"
	var pool: Array[BugSpawnEntry] = [_entry(36, 10, 5.0)]
	for a: Dictionary in BugSpawnScheduler.ADDITIONS:
		pool.append(_entry(int(a["type_index"]), int(a["spawn_area"]), float(a["weight"])))
	var info: Array[BugSpawnEntry] = BugSpawnScheduler.limit(pool, world[0], world[1], Vector2i(-1, -1), false)
	assert_float(info[0].weight).is_equal(5.0)
	for i: int in range(1, info.size()):
		assert_float(info[i].weight).is_equal(0.0)
	_place(world[0], &"item", Vector2i(7, 7), ItemCatalog.get_item(&"candy"))
	info = BugSpawnScheduler.limit(pool, world[0], world[1], Vector2i(-1, -1), false)
	assert_float(info[0].weight).is_equal(0.0)   ## pill bug
	assert_float(info[1].weight).is_equal(1.0)   ## ant on candy
	assert_float(info[2].weight).is_equal(0.0)   ## ant on trash (no turnip)
	assert_float(info[3].weight).is_equal(0.0)
	Game.weather = &"snow"
	info = BugSpawnScheduler.limit(pool, world[0], world[1], Vector2i(-1, -1), false)
	assert_float(info[0].weight).is_equal(5.0)   ## candy ignored in snow
	assert_float(info[1].weight).is_equal(0.0)


func test_get_idx_rolls_against_100_below_100_total() -> void:
	var info: Array[BugSpawnEntry] = [_entry(0, 3, 10.0)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var hits: int = 0
	for _i: int in 2000:
		if BugSpawnScheduler.get_idx(info, false, rng) == 0:
			hits += 1
	assert_int(hits).is_between(120, 280)   ## ~10 %
	for _i: int in 50:
		assert_int(BugSpawnScheduler.get_idx(info, true, rng)).is_equal(0)


func test_acre_entry_is_spent_even_with_every_slot_full() -> void:
	var layout := WorldData.new()
	layout.columns = 32
	layout.rows = 16
	layout.bake()
	var grid := WorldGrid.new()
	grid.configure_from_world(layout)
	var world: Array = [layout, grid]
	var field := BugField.new()
	field.configure(grid, layout)
	var bug: BugData = BugCatalog.get_by_type(0)
	## Eight insects parked just over the border in the next acre (not culled: < 600 GX).
	for i: int in BugField.MAX_FIELD_SPAWNS:
		field.spawn(bug, BugData.Habitat.FLYING, grid.cell_to_world(Vector2i(17, 4 + i)))
	var sense := BugActor.Sense.new()
	sense.player_position = grid.cell_to_world(Vector2i(17, 8))
	_wade_into(field, grid, sense, Vector2i(14, 8))
	assert_that(field._spawned_acre).is_equal(
		BugHabitats.acre_of_world_pos(world[1], sense.player_position)
	)
	assert_int(field.field_slots_used()).is_equal(BugField.MAX_FIELD_SPAWNS)


func test_spawn_pool_is_kept_until_the_term_changes() -> void:
	var field := BugField.new()
	Clock.month = 7
	Clock.hour = 9
	var first: Array[BugSpawnEntry] = field.spawn_pool()
	Clock.hour = 10
	assert_bool(field.spawn_pool() == first).is_true()
	Clock.hour = 16
	assert_bool(field.spawn_pool() == first).is_false()


func _two_acre_field() -> Array:
	var layout := WorldData.new()
	layout.columns = 48
	layout.rows = 16
	layout.bake()
	var grid := WorldGrid.new()
	grid.configure_from_world(layout)
	var field := BugField.new()
	field.configure(grid, layout)
	return [layout, grid, field]


func test_cull_needs_off_screen_distance_and_another_block() -> void:
	## `aINS_cull_check`: > 600 GX away and born in another block than the player's.
	var w: Array = _two_acre_field()
	var grid: WorldGrid = w[1]
	var field: BugField = w[2]
	var bug: BugData = BugCatalog.get_by_type(0)
	var sense := BugActor.Sense.new()
	sense.player_position = grid.cell_to_world(Vector2i(40, 8))
	field.tick(STEP, sense)   ## player block = acre 3
	var far_other: BugActor = field.spawn(bug, BugData.Habitat.FLYING, grid.cell_to_world(Vector2i(2, 8)))
	far_other.block = Vector2i(1, 1)
	var far_same: BugActor = field.spawn(bug, BugData.Habitat.FLYING, grid.cell_to_world(Vector2i(3, 8)))
	far_same.block = Vector2i(3, 1)
	sense.on_screen = func(_p: Vector3) -> bool: return true
	field.tick(STEP * 2.0, sense)
	assert_bool(far_other.finished).is_false()
	sense.on_screen = Callable()
	field.tick(STEP * 2.0, sense)
	assert_bool(far_other.finished).is_true()
	assert_bool(far_same.finished).is_false()


func test_released_insect_is_culled_once_off_screen() -> void:
	var w: Array = _two_acre_field()
	var grid: WorldGrid = w[1]
	var field: BugField = w[2]
	var sense := BugActor.Sense.new()
	sense.player_position = grid.cell_to_world(Vector2i(8, 8))
	sense.on_screen = func(_p: Vector3) -> bool: return true
	var freed: BugActor = field.spawn(
		BugCatalog.get_by_type(0), BugData.Habitat.FLYING, grid.cell_to_world(Vector2i(8, 8)), true
	)
	field.tick(STEP * 2.0, sense)
	assert_bool(freed.finished).is_false()
	sense.on_screen = func(_p: Vector3) -> bool: return false
	field.tick(STEP * 2.0, sense)
	assert_bool(freed.finished).is_true()


func test_live_insect_check_uses_the_birth_block() -> void:
	## `aINS_chk_live_insect` reads `actor.block_x/z` (set at birth), not where it is now.
	var w: Array = _two_acre_field()
	var grid: WorldGrid = w[1]
	var field: BugField = w[2]
	var a: BugActor = field.spawn(BugCatalog.get_by_type(0), BugData.Habitat.FLYING, grid.cell_to_world(Vector2i(20, 8)))
	a.block = Vector2i(1, 1)
	assert_bool(field._acre_has_insect(Vector2i(1, 1))).is_true()
	assert_bool(field._acre_has_insect(Vector2i(2, 1))).is_false()


func test_a_walking_villager_stresses_an_insect_like_the_player() -> void:
	## `aINS_get_stress` reads the NPC actor list as well as the player: a villager
	## moving 2 GX a frame one unit away adds 2 × calc_table[2] × 0.5 patience.
	var bug: BugData = BugCatalog.get_bug(&"common_butterfly")
	var at := Vector3(0.0, 0.5, 0.0)
	var actor: BugActor = BugActor.create(bug, BugData.Habitat.FLYING, at, RandomNumberGenerator.new())
	actor.patience = 0.0
	var sense := BugActor.Sense.new()
	sense.npc_positions.append(at + Vector3(20.0 * FieldCatalog.GX_TO_METERS, 0.0, 0.0))
	sense.npc_moves_gx.append(2.0)
	assert_float(actor._calc_stress(sense)).is_equal_approx(2.0 * BugActor.STRESS_CALC_TABLE[2], 0.0001)
	actor._calc_patience(sense)
	assert_float(actor.patience).is_equal_approx(2.0 * BugActor.STRESS_CALC_TABLE[2] * 0.5, 0.0001)
	## A standing villager, or one past the 3-unit stress radius, does nothing.
	sense.npc_moves_gx[0] = 0.0
	assert_float(actor._calc_stress(sense)).is_equal(0.0)
	sense.npc_moves_gx[0] = 2.0
	sense.npc_positions[0] = at + Vector3(70.0 * FieldCatalog.GX_TO_METERS, 0.0, 0.0)
	assert_float(actor._calc_stress(sense)).is_equal(0.0)
