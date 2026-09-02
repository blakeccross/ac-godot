class_name TestBugCatching
extends GdUnitTestSuite

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
	var origin := Vector3.ZERO
	var direction := Vector3(0.0, 0.0, 1.0)
	var out: Netting.Outcome = Netting.swing(ctx, origin, direction)
	assert_bool(out.caught()).is_true()
	assert_that(out.bug.id).is_equal(&"common_butterfly")
	assert_int(ctx.inventory.count_of(bug.id)).is_equal(1)


func test_net_miss_reports_nothing_caught() -> void:
	var ctx: InteractionContext = _ctx()
	var field: BugField = ctx.world.get("bugs") as BugField
	field.auto_spawn = false
	var bug: BugData = BugCatalog.get_bug(&"common_butterfly")
	field.spawn(bug, BugData.Habitat.FLYING, Vector3(12.0, 0.0, 12.0))
	var out: Netting.Outcome = Netting.swing(ctx, Vector3.ZERO, Vector3.FORWARD)
	assert_bool(out.missed).is_true()


func test_swing_resolves_on_catch_frame() -> void:
	assert_float(Netting.SWING_CATCH_FRAME).is_equal(6.0)
	var ctx: InteractionContext = _ctx()
	ItemCatalog.reload()
	var net: ItemData = ItemCatalog.get_item(&"net")
	assert_that(net).is_not_null()
	assert_int(ctx.inventory.add(net, 1)).is_equal(0)
	assert_bool(ctx.inventory.equip_slot(0)).is_true()
	var action: Interaction = ToolUse.field_action(ctx)
	assert_that(action).is_not_null()
	assert_str(String(action.id)).is_equal(String(Interaction.SWING_NET))
	assert_float(action.effect_frame).is_equal(Netting.SWING_CATCH_FRAME)


func test_test_town_seeds_bugs_on_trees() -> void:
	var layout: WorldData = WorldGenerator.authored_test_town()
	var grid := WorldGrid.new()
	grid.configure_from_world(layout)
	var field := BugField.new()
	field.auto_spawn = false
	field.configure(grid, layout)
	field.seed_rng(1)
	Clock.month = 1
	Clock.hour = 12
	field.seed_trees()
	assert_int(field.actor_count()).is_equal(3)
	for actor: BugActor in field.actors:
		assert_that(actor.habitat).is_equal(BugData.Habitat.TREE)
		assert_float(actor.pitch).is_greater(0.0)
		var base: Vector3 = _nearest_tree_base(layout, grid, actor.position)
		assert_float(actor.position.y).is_greater(base.y)
		## January tree pool is bagworms: hang −25 GX on Z (`ac_ins_mino`).
		assert_float(absf(actor.position.x - base.x)).is_less(0.01)
		assert_float(actor.position.z - base.z).is_equal_approx(
			BugActor.BAGWORM_OFFSET_Z_GX * FieldCatalog.GX_TO_METERS, 0.01
		)
		assert_float(absf(angle_difference(actor.yaw, BugActor.TREE_FACE_YAW))).is_less(0.01)


func test_test_town_seeds_tree_bugs_after_world_build() -> void:
	var layout: WorldData = WorldGenerator.authored_test_town()
	var grid := WorldGrid.new()
	var world := Node3D.new()
	world.add_to_group("world")
	var objects := Node3D.new()
	objects.name = "Objects"
	world.add_child(objects)
	world.set("grid", grid)
	var field := BugField.new()
	world.set("bugs", field)
	WorldBuilder.new().build(world, layout, grid)
	field.configure(grid, layout)
	field.seed_rng(1)
	Clock.month = 8
	Clock.hour = 12
	field.seed_trees()
	assert_int(field.actor_count()).is_equal(3)
	for actor: BugActor in field.actors:
		var base: Vector3 = _nearest_tree_base(layout, grid, actor.position)
		assert_float(absf(actor.position.x - base.x)).is_less(0.01)
		assert_float(actor.position.z - base.z).is_equal_approx(
			BugActor.BEETLE_SOUTH_Z_GX * FieldCatalog.GX_TO_METERS, 0.01
		)


func test_tree_beetle_clings_with_trunk_pitch() -> void:
	var beetle: BugData = BugCatalog.get_bug(&"drone_beetle")
	var anchor := Vector3(9.0, 0.0, 13.0)
	var actor := BugActor.create(beetle, BugData.Habitat.TREE, anchor, RandomNumberGenerator.new())
	assert_float(actor.pitch).is_equal(PI * 0.5)
	assert_float(actor.height).is_equal(0.0)
	assert_float(actor.position.y).is_equal_approx(
		anchor.y + BugActor.BEETLE_HEIGHT_GX * FieldCatalog.GX_TO_METERS, 0.01
	)
	assert_float(actor.position.x).is_equal_approx(anchor.x, 0.01)
	assert_float(actor.position.z).is_equal_approx(
		anchor.z + BugActor.BEETLE_SOUTH_Z_GX * FieldCatalog.GX_TO_METERS, 0.01
	)
	assert_float(absf(angle_difference(actor.yaw, -BugActor.TREE_FACE_YAW))).is_less(0.01)


func test_tree_beetle_sway_stays_near_base_yaw() -> void:
	var beetle: BugData = BugCatalog.get_bug(&"drone_beetle")
	var actor := BugActor.create(
		beetle, BugData.Habitat.TREE, Vector3(9.0, 0.0, 13.0), RandomNumberGenerator.new()
	)
	for _i: int in 180:
		actor.tick(1.0 / 30.0, BugActor.Sense.new())
	assert_float(absf(angle_difference(actor.yaw, -BugActor.TREE_FACE_YAW))).is_less(
		deg_to_rad(8.0)
	)


func test_tree_cicada_faces_south_and_does_not_wander_yaw() -> void:
	var cicada: BugData = BugCatalog.get_bug(&"robust_cicada")
	var actor := BugActor.create(
		cicada, BugData.Habitat.TREE, Vector3(9.0, 0.0, 13.0), RandomNumberGenerator.new()
	)
	assert_float(absf(angle_difference(actor.yaw, BugActor.TREE_FACE_YAW))).is_less(0.01)
	var start_yaw: float = actor.yaw
	for _i: int in 120:
		actor.tick(1.0 / 30.0, BugActor.Sense.new())
	assert_float(absf(angle_difference(actor.yaw, start_yaw))).is_less(0.001)


func test_anime_pose_flips_from_program_step() -> void:
	var butterfly: BugData = BugCatalog.get_bug(&"common_butterfly")
	var actor := BugActor.create(
		butterfly, BugData.Habitat.FLYING, Vector3.ZERO, RandomNumberGenerator.new()
	)
	assert_int(actor.pose_index()).is_equal(0)
	for _i: int in 3:
		actor.tick(1.0 / 30.0, BugActor.Sense.new())
	assert_int(actor.pose_index()).is_equal(0)
	actor.tick(1.0 / 30.0, BugActor.Sense.new())
	assert_int(actor.pose_index()).is_equal(1)
	var cicada: BugData = BugCatalog.get_bug(&"robust_cicada")
	var tree_cicada := BugActor.create(
		cicada, BugData.Habitat.TREE, Vector3(9.0, 0.0, 13.0), RandomNumberGenerator.new()
	)
	assert_int(tree_cicada.pose_index()).is_equal(0)
	for _i: int in 60:
		tree_cicada.tick(1.0 / 30.0, BugActor.Sense.new())
	assert_int(tree_cicada.pose_index()).is_equal(0)


func test_pose_pattern_tables() -> void:
	assert_int(BugData.pose_pattern(0).size()).is_equal(1)
	assert_int(BugData.pose_pattern(1).size()).is_equal(8)
	assert_int(BugData.pose_pattern(2).size()).is_equal(16)
	assert_int(BugData.pose_pattern(1)[4]).is_equal(1)


func test_patience_threshold_triggers_flee() -> void:
	var butterfly := BugActor.create(
		BugCatalog.get_bug(&"common_butterfly"),
		BugData.Habitat.FLYING,
		Vector3.ZERO,
		RandomNumberGenerator.new()
	)
	butterfly._patience = BugActor.PATIENCE_FLEE_FLYING + 1.0
	butterfly.tick(STEP, BugActor.Sense.new())
	assert_that(butterfly.action).is_equal(BugActor.Action.FLEE)


func test_patience_flee_threshold_matches_decomp() -> void:
	var beetle := BugActor.create(
		BugCatalog.get_bug(&"drone_beetle"),
		BugData.Habitat.TREE,
		Vector3(9.0, 0.0, 13.0),
		RandomNumberGenerator.new()
	)
	beetle._patience = BugActor.PATIENCE_FLEE_TREE
	assert_bool(beetle._patience_triggers_flee()).is_false()
	beetle._patience = BugActor.PATIENCE_FLEE_TREE + 0.1
	assert_bool(beetle._patience_triggers_flee()).is_true()
	var butterfly := BugActor.create(
		BugCatalog.get_bug(&"common_butterfly"),
		BugData.Habitat.FLYING,
		Vector3.ZERO,
		RandomNumberGenerator.new()
	)
	butterfly._patience = BugActor.PATIENCE_FLEE_FLYING
	assert_bool(butterfly._patience_triggers_flee()).is_true()


func test_running_player_builds_patience_and_flees() -> void:
	var butterfly := BugActor.create(
		BugCatalog.get_bug(&"common_butterfly"),
		BugData.Habitat.FLYING,
		Vector3(0.0, 0.0, 0.0),
		RandomNumberGenerator.new()
	)
	var sense := BugActor.Sense.new()
	sense.player_move_gx = PlayerLocomotion.ORIG_RUN
	sense.player_position = Vector3(0.0, 0.0, 2.0)
	for _i: int in 90:
		butterfly.position = Vector3.ZERO
		butterfly.tick(STEP, sense)
	assert_that(butterfly.action).is_equal(BugActor.Action.FLEE)


func test_wander_moves_at_decomp_cruise_rate() -> void:
	var butterfly := BugActor.create(
		BugCatalog.get_bug(&"common_butterfly"),
		BugData.Habitat.FLYING,
		Vector3(0.0, 0.0, 0.0),
		RandomNumberGenerator.new()
	)
	butterfly.yaw = 0.0
	butterfly._timer = 999.0
	var start := butterfly.position
	for _i: int in 30:
		butterfly.tick(1.0 / 30.0, BugActor.Sense.new())
	var moved: float = Vector2(
		butterfly.position.x - start.x, butterfly.position.z - start.z
	).length()
	assert_float(moved).is_equal_approx(2.0 * FieldCatalog.GX_TO_METERS * 30.0, 0.15)


func test_grasshopper_hops_instead_of_crawling() -> void:
	var hopper := BugActor.create(
		BugCatalog.get_bug(&"grasshopper"),
		BugData.Habitat.GROUND,
		Vector3(4.0, 0.0, 4.0),
		RandomNumberGenerator.new()
	)
	hopper.yaw = 0.0
	hopper._begin_locust_jump(false)
	var start := hopper.position
	var peak_y: float = start.y
	for _i: int in 12:
		hopper.tick(1.0 / 30.0, BugActor.Sense.new())
		peak_y = maxf(peak_y, hopper.position.y)
	assert_float(Vector2(hopper.position.x - start.x, hopper.position.z - start.z).length()).is_greater(
		0.15
	)
	assert_float(peak_y).is_greater(start.y)


func test_grasshopper_scare_triggers_avoid_hops() -> void:
	var hopper := BugActor.create(
		BugCatalog.get_bug(&"grasshopper"),
		BugData.Habitat.GROUND,
		Vector3(0.0, 0.0, 0.0),
		RandomNumberGenerator.new()
	)
	var sense := BugActor.Sense.new()
	sense.player_move_gx = PlayerLocomotion.ORIG_RUN
	sense.player_position = Vector3(0.0, 0.0, 1.5)
	hopper._patience = BugActor.PATIENCE_FLEE_FLYING + 5.0
	hopper.tick(STEP, sense)
	assert_that(hopper._locust_phase).is_equal(BugActor.LocustPhase.AVOID)
	hopper._begin_locust_jump(true)
	var start := hopper.position
	for _i: int in 20:
		hopper.tick(1.0 / 30.0, sense)
	assert_float(Vector2(hopper.position.x - start.x, hopper.position.z - start.z).length()).is_greater(
		0.2
	)


func test_net_nearby_sets_patience_to_flee() -> void:
	var beetle := BugActor.create(
		BugCatalog.get_bug(&"drone_beetle"),
		BugData.Habitat.TREE,
		Vector3(9.0, 0.0, 13.0),
		RandomNumberGenerator.new()
	)
	var sense := BugActor.Sense.new()
	sense.net_swing_active = true
	sense.net_swing_origin = Vector3(9.0, 0.0, 13.5)
	actor_tick(beetle, sense, 1)
	assert_that(beetle.action).is_equal(BugActor.Action.FLEE)


func actor_tick(actor: BugActor, sense: BugActor.Sense, frames: int) -> void:
	for _i: int in frames:
		actor.tick(STEP, sense)


func test_tree_beetle_flee_levels_pitch_and_flies_up() -> void:
	var beetle: BugData = BugCatalog.get_bug(&"drone_beetle")
	var actor := BugActor.create(
		beetle, BugData.Habitat.TREE, Vector3(9.0, 1.75, 13.0), RandomNumberGenerator.new()
	)
	var start_y: float = actor.position.y
	assert_float(actor.pitch).is_equal(PI * 0.5)
	var sense := BugActor.Sense.new()
	sense.player_position = Vector3(9.0, 0.0, 15.0)
	actor._patience = BugActor.PATIENCE_MAX
	actor.tick(STEP, sense)
	assert_that(actor.action).is_equal(BugActor.Action.FLEE)
	assert_float(actor.pitch).is_equal(0.0)
	var start_xz := Vector2(actor.position.x, actor.position.z)
	for _i: int in 30:
		actor.tick(STEP, sense)
	assert_float(actor.position.y).is_greater(start_y)
	assert_float(Vector2(actor.position.x, actor.position.z).distance_to(start_xz)).is_greater(0.05)
	assert_bool(actor.finished).is_false()


func _nearest_tree_base(layout: WorldData, grid: WorldGrid, at: Vector3) -> Vector3:
	var best: Vector3 = at
	var best_dist: float = INF
	for obj: ObjectPlacement in layout.objects:
		if obj == null or obj.kind != &"tree":
			continue
		var base: Vector3 = grid.footprint_center(obj.cell, Vector2i(1, 1))
		base.y = FieldCollision.ground_y(layout, obj.cell)
		var dist: float = Vector2(at.x - base.x, at.z - base.z).length()
		if dist < best_dist:
			best_dist = dist
			best = base
	return best


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
