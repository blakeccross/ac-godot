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
	assert_that(BugData.term_for_hour(4)).is_equal(BugData.TimeTerm.T1)
	assert_that(BugData.term_for_hour(12)).is_equal(BugData.TimeTerm.T2)
	assert_that(BugData.term_for_hour(16)).is_equal(BugData.TimeTerm.T3)
	assert_that(BugData.term_for_hour(18)).is_equal(BugData.TimeTerm.T4)
	assert_that(BugData.term_for_hour(20)).is_equal(BugData.TimeTerm.T5)


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


func test_patience_flees_when_player_dashes_nearby() -> void:
	var actor := BugActor.create(
		BugCatalog.get_bug(&"common_butterfly"),
		BugData.Habitat.FLYING,
		Vector3.ZERO,
		RandomNumberGenerator.new()
	)
	var sense := BugActor.Sense.new()
	sense.player_position = Vector3(0.5, 0.0, 0.5)
	sense.player_dashing = true
	## Avoid sets `alpha_time = 80` frames @ 30 Hz (~2.7 s) before despawn.
	for _i: int in 200:
		actor.tick(STEP, sense)
	assert_bool(actor.finished).is_true()


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
