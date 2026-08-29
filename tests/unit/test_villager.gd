class_name TestVillager
extends GdUnitTestSuite

## Villager framework: looks tables, runtime schedule, talk memory. No per-NPC AI.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_activity_presence() -> void:
	assert_bool(VillagerActivity.is_present(VillagerActivity.FIELD)).is_true()
	assert_bool(VillagerActivity.is_talkable(VillagerActivity.FIELD)).is_true()
	assert_bool(VillagerActivity.is_wandering(VillagerActivity.FIELD)).is_true()
	assert_bool(VillagerActivity.hides_actor(VillagerActivity.SLEEP)).is_true()
	assert_bool(VillagerActivity.hides_actor(VillagerActivity.IN_HOUSE)).is_true()
	assert_bool(VillagerActivity.is_talkable(VillagerActivity.SLEEP)).is_false()
	assert_bool(VillagerActivity.is_wandering(VillagerActivity.STAND)).is_false()


func test_lazy_looks_table_matches_boy_schedule() -> void:
	var personality: VillagerPersonality = load("res://data/personalities/lazy.tres")
	assert_that(personality).is_not_null()
	assert_that(personality.looks).is_equal(VillagerPersonality.Looks.LAZY)
	var table: ScheduleData = personality.schedule
	assert_that(table.activity_at(7)).is_equal(VillagerActivity.SLEEP)
	assert_that(table.activity_at(8)).is_equal(VillagerActivity.IN_HOUSE)
	assert_that(table.activity_at(9)).is_equal(VillagerActivity.FIELD)
	assert_that(table.activity_at(12)).is_equal(VillagerActivity.IN_HOUSE)
	assert_that(table.activity_at(14)).is_equal(VillagerActivity.FIELD)
	assert_that(table.activity_at(20)).is_equal(VillagerActivity.IN_HOUSE)
	assert_that(table.activity_at(22)).is_equal(VillagerActivity.SLEEP)


func test_all_looks_tables_follow_decomp_hours() -> void:
	var normal: ScheduleData = load("res://data/schedules/normal.tres")
	assert_that(normal.activity_at(4)).is_equal(VillagerActivity.SLEEP)
	assert_that(normal.activity_at(5)).is_equal(VillagerActivity.IN_HOUSE)
	assert_that(normal.activity_at(9)).is_equal(VillagerActivity.FIELD)
	assert_that(normal.activity_at(12)).is_equal(VillagerActivity.IN_HOUSE)
	assert_that(normal.activity_at(18)).is_equal(VillagerActivity.FIELD)
	assert_that(normal.activity_at(19)).is_equal(VillagerActivity.IN_HOUSE)
	var peppy: ScheduleData = load("res://data/schedules/peppy.tres")
	assert_that(peppy.activity_at(6)).is_equal(VillagerActivity.SLEEP)
	assert_that(peppy.activity_at(8)).is_equal(VillagerActivity.FIELD)
	assert_that(peppy.activity_at(22)).is_equal(VillagerActivity.IN_HOUSE)
	var jock: ScheduleData = load("res://data/schedules/jock.tres")
	assert_that(jock.activity_at(0)).is_equal(VillagerActivity.IN_HOUSE)
	assert_that(jock.activity_at(3)).is_equal(VillagerActivity.SLEEP)
	assert_that(jock.activity_at(7)).is_equal(VillagerActivity.FIELD)
	assert_that(jock.activity_at(12)).is_equal(VillagerActivity.IN_HOUSE)
	assert_that(jock.activity_at(13)).is_equal(VillagerActivity.FIELD)
	var cranky: ScheduleData = load("res://data/schedules/cranky.tres")
	assert_that(cranky.activity_at(3)).is_equal(VillagerActivity.FIELD)
	assert_that(cranky.activity_at(9)).is_equal(VillagerActivity.SLEEP)
	assert_that(cranky.activity_at(11)).is_equal(VillagerActivity.FIELD)
	assert_that(cranky.activity_at(22)).is_equal(VillagerActivity.IN_HOUSE)
	var snooty: ScheduleData = load("res://data/schedules/snooty.tres")
	assert_that(snooty.activity_at(0)).is_equal(VillagerActivity.FIELD)
	assert_that(snooty.activity_at(2)).is_equal(VillagerActivity.IN_HOUSE)
	assert_that(snooty.activity_at(3)).is_equal(VillagerActivity.SLEEP)
	assert_that(snooty.activity_at(10)).is_equal(VillagerActivity.FIELD)


func test_runtime_schedule_force_override() -> void:
	var table: ScheduleData = load("res://data/schedules/pip_weekday.tres")
	var sched := VillagerSchedule.new()
	sched.bind(table)
	assert_that(sched.tick(10 * 3600)).is_equal(VillagerActivity.FIELD)
	sched.force(VillagerActivity.STAND)
	assert_that(sched.tick(10 * 3600)).is_equal(VillagerActivity.STAND)
	sched.clear_force()
	assert_that(sched.tick(10 * 3600)).is_equal(VillagerActivity.FIELD)
	assert_that(sched.tick(7 * 3600)).is_equal(VillagerActivity.SLEEP)


func test_talk_updates_friendship_and_repeat_greeting() -> void:
	var filbert: VillagerData = load("res://data/villagers/filbert.tres")
	assert_that(filbert.personality).is_not_null()
	assert_that(filbert.dialogue).is_not_null()
	var state := VillagerState.new()
	state.villager_id = &"filbert"
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 10, "minute": 0 })
	var first: String = VillagerTalk.greeting(filbert, state)
	assert_str(first).is_equal("Nice plot you've got.")
	assert_int(state.record_talk(VillagerTalk.day_key())).is_equal(VillagerState.TALK_FIRST)
	assert_int(state.friendship).is_equal(VillagerState.TALK_FIRST)
	assert_bool(state.talked_on(VillagerTalk.day_key())).is_true()
	var again: String = VillagerTalk.greeting(filbert, state)
	assert_str(again).is_equal("Still hanging around, huh?")
	assert_int(state.record_talk(VillagerTalk.day_key())).is_equal(VillagerState.TALK_REPEAT)
	assert_int(state.friendship).is_equal(VillagerState.TALK_FIRST + VillagerState.TALK_REPEAT)


func test_greeting_follows_time_of_day() -> void:
	var filbert: VillagerData = load("res://data/villagers/filbert.tres")
	var state := VillagerState.new()
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 2, "minute": 0 })
	assert_str(VillagerTalk.greeting(filbert, state)).is_equal("You're up late.")
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 7, "minute": 0 })
	assert_str(VillagerTalk.greeting(filbert, state)).is_equal("Morning!")
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 19, "minute": 0 })
	assert_str(VillagerTalk.greeting(filbert, state)).is_equal("Evening already?")


func test_catchphrase_substitution() -> void:
	var filbert: VillagerData = load("res://data/villagers/filbert.tres")
	assert_str(VillagerTalk.substitute("Hey {name}, {catchphrase}!", filbert)).is_equal("Hey Filbert, bucko!")


func test_roster_save_round_trip() -> void:
	var state: VillagerState = Game.villagers.get_or_create(&"filbert")
	state.friendship = 12
	state.last_spoke_day = "2001-01-01"
	state.mood = VillagerState.Mood.HAPPY
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	assert_bool(Game.villagers.has_id(&"filbert")).is_false()
	Game.apply_snapshot(snap)
	assert_bool(Game.villagers.has_id(&"filbert")).is_true()
	var loaded: VillagerState = Game.villagers.get_or_create(&"filbert")
	assert_int(loaded.friendship).is_equal(12)
	assert_str(loaded.last_spoke_day).is_equal("2001-01-01")
	assert_that(loaded.mood).is_equal(VillagerState.Mood.HAPPY)


func test_scene_composition() -> void:
	var villager: Node = auto_free(load("res://scenes/actors/villager.tscn").instantiate())
	assert_that(villager.get_node_or_null("Model")).is_not_null()
	assert_that(villager.get_node_or_null("Collision")).is_not_null()
	assert_that(villager.get_node_or_null("NavigationAgent3D")).is_not_null()
	assert_that(villager.get_node_or_null("InteractionArea")).is_not_null()
	assert_that(villager.get_node_or_null("Animation")).is_not_null()
	assert_bool(villager is CharacterBody3D).is_true()


func test_filbert_data_is_lazy_squirrel() -> void:
	var filbert: VillagerData = load("res://data/villagers/filbert.tres")
	assert_that(filbert.display_name).is_equal("Filbert")
	assert_that(filbert.species).is_equal(&"squirrel")
	assert_that(filbert.personality.id).is_equal(&"lazy")
	assert_that(filbert.schedule_table().activity_at(9)).is_equal(VillagerActivity.FIELD)
	assert_that(filbert.dialogue.speaker_id).is_equal(&"filbert")


func test_scene_talks_when_in_field() -> void:
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 10, "minute": 0 })
	var villager: Villager = auto_free(load("res://scenes/actors/villager.tscn").instantiate()) as Villager
	assert_that(villager.current_activity()).is_equal(VillagerActivity.FIELD)
	var actions: Array[Interaction] = villager.get_interactions(InteractionContext.new())
	assert_int(actions.size()).is_equal(1)
	assert_bool(villager.interact(actions[0], InteractionContext.new())).is_true()
	assert_int(Game.villagers.get_or_create(&"filbert").friendship).is_equal(VillagerState.TALK_FIRST)


func test_motor_stops_when_not_wandering() -> void:
	var motor := VillagerMotor.new()
	motor.reset(Vector3.ZERO)
	motor.set_target(Vector3(3, 0, 0))
	var step: Vector3 = motor.tick(0.1, Vector3.ZERO, Vector3(3, 0, 0), false)
	assert_vector(step).is_equal(Vector3.ZERO)
	motor.set_target(Vector3(3, 0, 0))
	var walk: Vector3 = motor.tick(0.1, Vector3.ZERO, Vector3(3, 0, 0), true)
	assert_float(walk.length()).is_greater(0.1)
	motor.set_target(Vector3(10, 0, 0))
	var boxed: Vector3 = motor.tick(0.1, Vector3.ZERO, Vector3.ZERO, true)
	assert_vector(boxed).is_equal(Vector3.ZERO)
	assert_bool(motor.has_target).is_true()


func test_field_plan_is_reusable_actions() -> void:
	var plan: Array[VillagerAction] = VillagerPlan.build(
		VillagerActivity.FIELD,
		VillagerActivity.IN_HOUSE,
		{
			"home": Vector3.ZERO,
			"outdoors": false,
			"field_actions": [ActivityKind.WANDER],
			"shop": Vector3.INF,
			"water": Vector3.INF,
		}
	)
	var kinds: Array[StringName] = []
	for action: VillagerAction in plan:
		kinds.append(action.kind)
	assert_that(kinds[0]).is_equal(ActivityKind.LEAVE_HOME)
	assert_that(kinds[kinds.size() - 1]).is_equal(ActivityKind.WANDER)
	assert_bool(ActivityKind.loops(ActivityKind.WANDER)).is_true()


func test_field_plan_walks_to_goal_acre() -> void:
	var goal := Vector3(24, 0, 16)
	var plan: Array[VillagerAction] = VillagerPlan.build(
		VillagerActivity.FIELD,
		VillagerActivity.FIELD,
		{
			"home": Vector3.ZERO,
			"goal": goal,
			"outdoors": true,
			"field_actions": [ActivityKind.WANDER],
			"shop": Vector3.INF,
			"water": Vector3.INF,
		}
	)
	assert_that(plan[0].kind).is_equal(ActivityKind.WALK_TO)
	assert_vector(plan[0].target).is_equal(goal)
	assert_that(plan[1].kind).is_equal(ActivityKind.WANDER)
	assert_vector(plan[1].target).is_equal(goal)
	assert_bool(plan[1].is_finished()).is_false()
	plan[1].tick_time(ActivityKind.STAY_SECONDS + 1.0)
	assert_bool(plan[1].is_finished()).is_false()


func test_sleep_plan_is_just_sleep_when_already_home() -> void:
	var plan: Array[VillagerAction] = VillagerPlan.build(
		VillagerActivity.SLEEP, &"", {"home": Vector3.ZERO, "outdoors": false}
	)
	assert_int(plan.size()).is_equal(1)
	assert_that(plan[0].kind).is_equal(ActivityKind.SLEEP)
	assert_bool(plan[0].is_present()).is_false()
	assert_bool(plan[0].is_talkable()).is_false()


func test_already_outdoors_skips_leave_house() -> void:
	var plan: Array[VillagerAction] = VillagerPlan.build(
		VillagerActivity.FIELD,
		&"",
		{"home": Vector3.ZERO, "outdoors": true, "field_actions": [ActivityKind.WANDER]}
	)
	assert_that(plan[0].kind).is_equal(ActivityKind.WANDER)
	assert_int(plan.size()).is_equal(1)


func test_wake_then_leave_home_then_sleep() -> void:
	var indoors: Array[VillagerAction] = VillagerPlan.build(
		VillagerActivity.IN_HOUSE, VillagerActivity.SLEEP, {"home": Vector3.ZERO, "outdoors": false}
	)
	assert_that(indoors[0].kind).is_equal(ActivityKind.WAKE)
	var field: Array[VillagerAction] = VillagerPlan.build(
		VillagerActivity.FIELD,
		VillagerActivity.IN_HOUSE,
		{"home": Vector3.ZERO, "outdoors": false, "field_actions": [ActivityKind.WANDER]}
	)
	assert_that(field[0].kind).is_equal(ActivityKind.LEAVE_HOME)
	var going: Array[VillagerAction] = VillagerPlan.build(
		VillagerActivity.IN_HOUSE,
		VillagerActivity.FIELD,
		{"home": Vector3.ZERO, "outdoors": true},
	)
	assert_that(going[0].kind).is_equal(ActivityKind.GO_HOME)


func test_shop_and_fish_are_picked_from_field_actions() -> void:
	var shop: VillagerAction = VillagerPlan.pick_perform(
		{
			"home": Vector3.ZERO,
			"shop": Vector3(10, 0, 4),
			"water": Vector3(2, 0, 8),
			"shop_open": true,
			"field_actions": [ActivityKind.SHOP, ActivityKind.WANDER],
		}
	)
	assert_that(shop.kind).is_equal(ActivityKind.SHOP)
	var fish: VillagerAction = VillagerPlan.pick_perform(
		{
			"home": Vector3.ZERO,
			"shop": Vector3.INF,
			"water": Vector3(2, 0, 8),
			"shop_open": false,
			"field_actions": [ActivityKind.FISH, ActivityKind.WANDER],
		}
	)
	assert_that(fish.kind).is_equal(ActivityKind.FISH)


func test_walk_to_finishes_on_arrive() -> void:
	var action: VillagerAction = VillagerAction.make(ActivityKind.WALK_TO, Vector3(4, 0, 0))
	action.consider_arrive(Vector3.ZERO)
	assert_bool(action.is_finished()).is_false()
	action.consider_arrive(Vector3(4, 0, 0.1))
	assert_bool(action.is_finished()).is_true()
	var sit: VillagerAction = VillagerAction.make(ActivityKind.SIT, Vector3.ZERO, 2.0)
	sit.tick_time(1.0)
	assert_bool(sit.is_finished()).is_false()
	sit.tick_time(1.5)
	assert_bool(sit.is_finished()).is_true()
	var wander: VillagerAction = VillagerAction.make(ActivityKind.WANDER, Vector3.ZERO)
	assert_bool(wander.is_finished()).is_false()
	wander.tick_time(ActivityKind.STAY_SECONDS + 0.1)
	assert_bool(wander.is_finished()).is_false()


func test_ai_advances_when_action_finishes() -> void:
	var ai := VillagerAI.new()
	ai.sync(
		VillagerActivity.FIELD,
		{
			"home": Vector3.ZERO,
			"outdoors": false,
			"goal": Vector3(8, 0, 0),
			"field_actions": [ActivityKind.WANDER],
			"shop": Vector3.INF,
			"water": Vector3.INF,
		}
	)
	assert_that(ai.kind()).is_equal(ActivityKind.LEAVE_HOME)
	ai.consider_arrive(ActivityKind.YARD_OFFSET)
	ai.step(0.0)
	assert_that(ai.kind()).is_equal(ActivityKind.WALK_TO)
	ai.consider_arrive(Vector3(8, 0, 0))
	ai.step(0.0)
	assert_that(ai.kind()).is_equal(ActivityKind.WANDER)
	ai.step(ActivityKind.STAY_SECONDS + 0.1)
	assert_that(ai.kind()).is_equal(ActivityKind.WANDER)


func test_starter_pick_is_one_of_each_looks() -> void:
	VillagerCatalog.reload()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var picked: Array[VillagerData] = VillagerCatalog.pick_starters(rng, 6)
	assert_int(picked.size()).is_equal(6)
	var looks: Dictionary = {}
	for villager: VillagerData in picked:
		assert_bool(villager.starter).is_true()
		assert_that(villager.personality).is_not_null()
		looks[int(villager.personality.looks)] = true
	assert_int(looks.size()).is_equal(6)


func test_starter_pick_is_seeded() -> void:
	VillagerCatalog.reload()
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	var first: Array[VillagerData] = VillagerCatalog.pick_starters(a, 6)
	var second: Array[VillagerData] = VillagerCatalog.pick_starters(b, 6)
	assert_int(first.size()).is_equal(6)
	for i: int in first.size():
		assert_that(first[i].id).is_equal(second[i].id)


func test_catalog_includes_filbert_and_other_starters() -> void:
	VillagerCatalog.reload()
	assert_that(VillagerCatalog.get_villager(&"filbert")).is_not_null()
	assert_int(VillagerCatalog.starters().size()).is_greater_equal(12)


func test_lazy_walk_goals_match_boy_table() -> void:
	var morning: Array[StringName] = VillagerWalk.goal_kinds(VillagerPersonality.Looks.LAZY, 10 * 3600)
	assert_int(morning.size()).is_equal(1)
	assert_that(morning[0]).is_equal(VillagerWalk.GOAL_ALONE)
	assert_that(VillagerWalk.pick_kind(VillagerPersonality.Looks.LAZY, 10 * 3600)).is_equal(
		VillagerWalk.GOAL_ALONE
	)
	var noon: Array[StringName] = VillagerWalk.goal_kinds(VillagerPersonality.Looks.LAZY, 13 * 3600)
	assert_int(noon.size()).is_equal(0)
	assert_bool(VillagerWalk.can_town_walk(VillagerPersonality.Looks.LAZY, 13 * 3600)).is_false()
	assert_that(VillagerWalk.pick_kind(VillagerPersonality.Looks.LAZY, 13 * 3600)).is_equal(
		VillagerWalk.GOAL_MY_HOME
	)
	var afternoon: Array[StringName] = VillagerWalk.goal_kinds(VillagerPersonality.Looks.LAZY, 15 * 3600)
	assert_int(afternoon.size()).is_equal(2)
	assert_bool(afternoon.has(VillagerWalk.GOAL_SHRINE)).is_true()
	assert_bool(afternoon.has(VillagerWalk.GOAL_HOME)).is_true()


func test_peppy_walks_all_day_and_cranky_prefers_alone() -> void:
	var peppy: Array[StringName] = VillagerWalk.goal_kinds(VillagerPersonality.Looks.PEPPY, 3 * 3600)
	assert_bool(peppy.has(VillagerWalk.GOAL_SHRINE)).is_true()
	assert_bool(peppy.has(VillagerWalk.GOAL_HOME)).is_true()
	var cranky: Array[StringName] = VillagerWalk.goal_kinds(VillagerPersonality.Looks.CRANKY, 8 * 3600)
	var alone_n := 0
	var shrine_n := 0
	for kind: StringName in cranky:
		if kind == VillagerWalk.GOAL_ALONE:
			alone_n += 1
		elif kind == VillagerWalk.GOAL_SHRINE:
			shrine_n += 1
	assert_int(alone_n).is_equal(7)
	assert_int(shrine_n).is_equal(3)


func test_walk_slots_match_decomp_cap() -> void:
	VillagerWalk.reset()
	assert_int(VillagerWalk.walker_cap(6)).is_equal(2)
	assert_int(VillagerWalk.walker_cap(15)).is_equal(5)
	assert_int(VillagerWalk.walker_cap(1)).is_equal(1)
	assert_bool(VillagerWalk.claim(&"a", true, 6)).is_true()
	assert_bool(VillagerWalk.claim(&"b", true, 6)).is_true()
	assert_bool(VillagerWalk.claim(&"c", true, 6)).is_false()
	VillagerWalk.release(&"a")
	assert_bool(VillagerWalk.claim(&"c", true, 6)).is_true()
	assert_bool(VillagerWalk.claim(&"b", false, 6)).is_false()
	assert_bool(VillagerWalk.is_claimed(&"b")).is_false()


func test_alone_acre_skips_occupied_and_defaults_to_d3() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var occupied: Array[Vector2i] = []
	for bz: int in range(1, 7):
		for bx: int in range(1, 6):
			occupied.append(Vector2i(bx, bz))
	var full: Vector2i = VillagerWalk.resolve_block(
		VillagerWalk.GOAL_ALONE, Vector2i(2, 2), Vector2i(4, 2), [], occupied, rng
	)
	assert_that(full).is_equal(VillagerWalk.ALONE_DEFAULT)
	var shrine: Vector2i = VillagerWalk.resolve_block(
		VillagerWalk.GOAL_SHRINE, Vector2i(2, 3), Vector2i(3, 2), [], [], rng
	)
	assert_that(shrine).is_equal(Vector2i(3, 2))
	var mine: Vector2i = VillagerWalk.resolve_block(
		VillagerWalk.GOAL_MY_HOME, Vector2i(5, 6), Vector2i(3, 2), [], [], rng
	)
	assert_that(mine).is_equal(Vector2i(5, 6))


func test_other_home_goal_picks_a_different_house_acre() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var homes: Array[Vector2i] = [Vector2i(1, 2), Vector2i(4, 5)]
	var block: Vector2i = VillagerWalk.resolve_block(
		VillagerWalk.GOAL_HOME, Vector2i(1, 2), Vector2i(3, 2), homes, [], rng
	)
	assert_that(block).is_equal(Vector2i(4, 5))


func test_attach_villager_is_noop_without_mesh() -> void:
	var host := Node3D.new()
	auto_free(host)
	var vis: Node3D = GeneratedVisual.attach_villager(host, &"squirrel")
	if FieldCatalog.villager_path(&"squirrel").is_empty():
		assert_that(vis).is_null()
		assert_int(host.get_child_count()).is_equal(0)
	else:
		assert_that(vis).is_not_null()
		assert_that(host.get_node_or_null("GeneratedVisual")).is_not_null()


func test_lazy_wait_walk_run_weights() -> void:
	var waits := 0
	var walks := 0
	var runs := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i: int in 200:
		var act: StringName = VillagerWalk.pick_act(VillagerPersonality.Looks.LAZY, rng)
		if act == VillagerWalk.ACT_WAIT:
			waits += 1
		elif act == VillagerWalk.ACT_WALK:
			walks += 1
		else:
			runs += 1
	## boy boarders 5,7 → 60% wait, 20% walk, 20% run
	assert_int(waits).is_greater(90)
	assert_int(walks).is_greater(20)
	assert_int(runs).is_greater(20)
	var jock_runs := 0
	rng.seed = 3
	for _j: int in 200:
		if VillagerWalk.pick_act(VillagerPersonality.Looks.JOCK, rng) == VillagerWalk.ACT_RUN:
			jock_runs += 1
	assert_int(jock_runs).is_greater(70)


func test_wander_point_is_away_from_feet() -> void:
	var data := WorldData.new()
	data.columns = 16
	data.rows = 16
	data.cell_size = 2.0
	data.bake()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var from: Vector3 = data.cell_to_world(Vector2i(8, 8))
	var stand: Vector3 = VillagerWalk.wander_in_block(data, Vector2i(1, 1), from, rng)
	var delta: Vector3 = stand - from
	delta.y = 0.0
	assert_float(delta.length()).is_greater_equal(VillagerWalk.MIN_STEP)


func test_wander_dest_is_on_acre_circle() -> void:
	var data := WorldData.new()
	data.columns = 16
	data.rows = 16
	data.cell_size = 2.0
	data.bake()
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var center: Vector3 = data.cell_to_world(Vector2i(8, 8))
	for _i: int in 12:
		var stand: Vector3 = VillagerWalk.wander_in_block(data, Vector2i(1, 1), center, rng)
		var to_center: Vector3 = stand - center
		to_center.y = 0.0
		assert_float(to_center.length()).is_equal_approx(VillagerWalk.RANGE_RADIUS, 0.05)


func test_starters_use_names_and_disc_species() -> void:
	var expected := {
		&"filbert": "Filbert",
		&"rosie": "Rosie",
		&"bunnie": "Bunnie",
		&"biskit": "Biskit",
		&"midge": "Midge",
		&"ribbot": "Ribbot",
		&"dora": "Dora",
		&"gruff": "Gruff",
		&"lobo": "Lobo",
		&"sprocket": "Sprocket",
		&"friga": "Friga",
		&"olivia": "Olivia",
	}
	var known: Array[String] = [
		"squ", "cat", "brd", "wol", "flg", "mos", "goa", "dog", "ost", "pgn", "rbt"
	]
	VillagerCatalog.reload()
	assert_int(VillagerCatalog.starters().size()).is_equal(expected.size())
	for villager: VillagerData in VillagerCatalog.starters():
		assert_that(expected.has(villager.id)).is_true()
		assert_str(villager.display_name).is_equal(str(expected[villager.id]))
		assert_that(villager.display_name).is_not_equal("Villager")
		var code: String = FieldCatalog.species_code(villager.species)
		assert_bool(known.has(code)).is_true()


func test_motor_wait_then_walk() -> void:
	var motor := VillagerMotor.new()
	motor.reset(Vector3.ZERO)
	motor.wait_in_place(0.2)
	var paused: Vector3 = motor.tick(0.1, Vector3.ZERO, Vector3(4, 0, 0), true)
	assert_vector(paused).is_equal(Vector3.ZERO)
	assert_bool(motor.needs_new_target()).is_false()
	motor.tick(0.2, Vector3.ZERO, Vector3(4, 0, 0), true)
	assert_bool(motor.needs_new_target()).is_true()
	motor.set_target(Vector3(4, 0, 0), VillagerWalk.ACT_RUN)
	assert_float(motor.speed_now()).is_equal_approx(motor.walk_speed * VillagerMotor.RUN_SCALE, 0.01)
	motor.arrive()
	assert_bool(motor.needs_new_target()).is_true()


func test_field_run_is_three_times_walk() -> void:
	## `aNPC_spd_data` walk 1.0 / run 3.0 GX/frame, same for every looks.
	var motor := VillagerMotor.new()
	motor.reset(Vector3.ZERO)
	assert_float(motor.walk_speed).is_equal_approx(VillagerMotor.WALK_SPEED, 0.01)
	motor.set_target(Vector3(8, 0, 0), VillagerWalk.ACT_WALK)
	assert_float(motor.speed_now()).is_equal_approx(1.5, 0.01)
	motor.set_target(Vector3(8, 0, 0), VillagerWalk.ACT_RUN)
	assert_float(motor.speed_now()).is_equal_approx(4.5, 0.01)
	assert_float(VillagerMotor.RUN_SCALE).is_equal_approx(3.0, 0.01)
	var jock: VillagerPersonality = load("res://data/personalities/jock.tres")
	motor.configure(jock)
	assert_float(motor.walk_speed).is_equal_approx(1.5, 0.01)
	assert_float(motor.speed_now()).is_equal_approx(4.5, 0.01)


func test_looks_share_field_walk_speed() -> void:
	var paths: Array[String] = [
		"res://data/personalities/normal.tres",
		"res://data/personalities/peppy.tres",
		"res://data/personalities/lazy.tres",
		"res://data/personalities/jock.tres",
		"res://data/personalities/cranky.tres",
		"res://data/personalities/snooty.tres",
	]
	for path: String in paths:
		var personality: VillagerPersonality = load(path)
		assert_that(personality).is_not_null()
		assert_float(personality.walk_speed).is_equal_approx(1.5, 0.01)


func test_house_cells_are_not_standable() -> void:
	var data := _plot_with_house()
	assert_bool(VillagerWalk.is_standable(data, Vector2i(7, 7))).is_false()
	assert_bool(VillagerWalk.is_standable(data, Vector2i(2, 2))).is_true()
	var flower := ObjectPlacement.new()
	flower.kind = &"flower"
	flower.cell = Vector2i(3, 2)
	flower.occupy_grid = true
	data.objects.append(flower)
	assert_bool(VillagerWalk.is_standable(data, Vector2i(3, 2))).is_true()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var from: Vector3 = data.cell_to_world(Vector2i(2, 2))
	for _i: int in 40:
		var stand: Vector3 = VillagerWalk.wander_in_block(data, Vector2i(1, 1), from, rng)
		var cell := Vector2i(
			int(floor((stand.x - data.origin().x) / data.cell_size)),
			int(floor((stand.z - data.origin().z) / data.cell_size))
		)
		assert_bool(VillagerWalk.is_standable(data, cell)).is_true()
		assert_that(cell).is_not_equal(Vector2i(6, 6))
		assert_that(cell).is_not_equal(Vector2i(7, 7))
		assert_that(cell).is_not_equal(Vector2i(8, 8))


func test_step_toward_skips_house_cells() -> void:
	var data := _plot_with_house()
	var from: Vector3 = data.cell_to_world(Vector2i(5, 7))
	var dest: Vector3 = data.cell_to_world(Vector2i(10, 7))
	var next: Vector3 = VillagerWalk.step_toward(data, from, dest)
	var cell := Vector2i(
		int(floor((next.x - data.origin().x) / data.cell_size)),
		int(floor((next.z - data.origin().z) / data.cell_size))
	)
	assert_bool(VillagerWalk.is_standable(data, cell)).is_true()
	assert_that(cell).is_not_equal(Vector2i(6, 7))
	assert_that(cell).is_not_equal(Vector2i(7, 7))


func test_avoid_around_skips_house() -> void:
	var data := _plot_with_house()
	var from: Vector3 = data.cell_to_world(Vector2i(5, 7))
	var around: Vector3 = VillagerWalk.avoid_around(data, from, deg_to_rad(90.0), Vector2i(1, 1))
	var cell := Vector2i(
		int(floor((around.x - data.origin().x) / data.cell_size)),
		int(floor((around.z - data.origin().z) / data.cell_size))
	)
	assert_bool(VillagerWalk.is_standable(data, cell)).is_true()
	assert_that(cell).is_not_equal(Vector2i(6, 7))
	assert_that(cell).is_not_equal(Vector2i(7, 7))
	var delta: Vector3 = around - from
	delta.y = 0.0
	assert_float(delta.length()).is_greater_equal(VillagerWalk.MIN_STEP)


func test_can_step_rejects_house_cell() -> void:
	var data := _plot_with_house()
	var from: Vector3 = data.cell_to_world(Vector2i(5, 7))
	var house: Vector3 = data.cell_to_world(Vector2i(7, 7))
	assert_bool(VillagerWalk.can_step(data, from, house)).is_false()
	var open: Vector3 = data.cell_to_world(Vector2i(5, 8))
	assert_bool(VillagerWalk.can_step(data, from, open)).is_true()


func test_wander_keeps_dest_past_the_next_cell() -> void:
	var motor := VillagerMotor.new()
	motor.reset(Vector3.ZERO)
	motor.set_target(Vector3(10, 0, 0), VillagerWalk.ACT_WALK, VillagerWalk.WANDER_ARRIVE)
	var step: Vector3 = motor.tick(0.1, Vector3.ZERO, Vector3(2, 0, 0), true)
	assert_float(step.length()).is_greater(0.1)
	assert_bool(motor.has_target).is_true()
	var near_cell: Vector3 = motor.tick(0.1, Vector3(1.97, 0, 0), Vector3(2, 0, 0), true)
	assert_float(near_cell.length()).is_greater(0.1)
	assert_bool(motor.has_target).is_true()


func test_avoid_keeps_rim_dest() -> void:
	## `aNPC_set_avoid_pos` must not replace `dst_pos`. Near avoid resumes the rim.
	var motor := VillagerMotor.new()
	motor.reset(Vector3.ZERO)
	var rim := Vector3(14, 0, 0)
	motor.set_target(rim, VillagerWalk.ACT_WALK, VillagerWalk.WANDER_ARRIVE)
	motor.set_avoid(Vector3(2, 0, 2))
	assert_bool(motor.is_avoiding()).is_true()
	assert_vector(motor.target).is_equal(rim)
	var at_avoid: Vector3 = motor.tick(0.1, Vector3(2, 0, 2), Vector3(2, 0, 2), true)
	assert_vector(at_avoid).is_equal(Vector3.ZERO)
	assert_bool(motor.has_target).is_true()
	assert_bool(motor.is_avoiding()).is_false()
	assert_vector(motor.steer).is_equal(rim)
	var resume: Vector3 = motor.tick(0.1, Vector3(2, 0, 2), Vector3(4, 0, 2), true)
	assert_float(resume.length()).is_greater(0.1)
	assert_vector(motor.target).is_equal(rim)


func test_pause_keeps_dest() -> void:
	var motor := VillagerMotor.new()
	motor.reset(Vector3.ZERO)
	motor.set_target(Vector3(10, 0, 0), VillagerWalk.ACT_WALK, VillagerWalk.WANDER_ARRIVE)
	motor.pause(0.2)
	assert_bool(motor.has_target).is_true()
	assert_bool(motor.needs_new_target()).is_false()
	var paused: Vector3 = motor.tick(0.1, Vector3.ZERO, Vector3(10, 0, 0), true)
	assert_vector(paused).is_equal(Vector3.ZERO)
	motor.tick(0.2, Vector3.ZERO, Vector3(10, 0, 0), true)
	var step: Vector3 = motor.tick(0.1, Vector3.ZERO, Vector3(10, 0, 0), true)
	assert_float(step.length()).is_greater(0.1)
	assert_bool(motor.has_target).is_true()


func test_wander_arrive_is_tight() -> void:
	var motor := VillagerMotor.new()
	motor.reset(Vector3.ZERO)
	motor.set_target(Vector3(0.2, 0, 0), VillagerWalk.ACT_RUN, VillagerWalk.WANDER_ARRIVE)
	var arrived: Vector3 = motor.tick(0.1, Vector3.ZERO, Vector3(0.2, 0, 0), true)
	assert_vector(arrived).is_equal(Vector3.ZERO)
	assert_bool(motor.has_target).is_false()
	motor.set_target(Vector3(8, 0, 0), VillagerWalk.ACT_RUN, VillagerWalk.WANDER_ARRIVE)
	var run: Vector3 = motor.tick(0.1, Vector3.ZERO, Vector3(8, 0, 0), true)
	assert_float(run.length()).is_equal_approx(motor.walk_speed * VillagerMotor.RUN_SCALE, 0.01)


func test_motor_turns_in_place_when_dest_is_behind() -> void:
	var motor := VillagerMotor.new()
	motor.reset(Vector3.ZERO, 0.0)
	motor.set_target(Vector3(0, 0, -5), VillagerWalk.ACT_WALK, VillagerWalk.WANDER_ARRIVE)
	var step: Vector3 = motor.tick(0.1, Vector3.ZERO, Vector3(0, 0, -5), true)
	assert_vector(step).is_equal(Vector3.ZERO)
	assert_bool(motor.has_target).is_true()


func _plot_with_house() -> WorldData:
	var data := WorldData.new()
	data.columns = 16
	data.rows = 16
	data.cell_size = 2.0
	data.bake()
	var house := BuildingPlacement.new()
	house.id = &"npc_house_0"
	house.kind = &"house"
	house.cell = Vector2i(6, 6)
	house.footprint = Vector2i(3, 3)
	house.occupy_grid = true
	data.buildings.append(house)
	return data
