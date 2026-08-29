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
	var pip: VillagerData = load("res://data/villagers/pip.tres")
	assert_that(pip.personality).is_not_null()
	assert_that(pip.dialogue).is_not_null()
	var state := VillagerState.new()
	state.villager_id = &"pip"
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 10, "minute": 0 })
	var first: String = VillagerTalk.greeting(pip, state)
	assert_str(first).is_equal("Nice plot you've got.")
	assert_int(state.record_talk(VillagerTalk.day_key())).is_equal(VillagerState.TALK_FIRST)
	assert_int(state.friendship).is_equal(VillagerState.TALK_FIRST)
	assert_bool(state.talked_on(VillagerTalk.day_key())).is_true()
	var again: String = VillagerTalk.greeting(pip, state)
	assert_str(again).is_equal("Still hanging around, huh?")
	assert_int(state.record_talk(VillagerTalk.day_key())).is_equal(VillagerState.TALK_REPEAT)
	assert_int(state.friendship).is_equal(VillagerState.TALK_FIRST + VillagerState.TALK_REPEAT)


func test_greeting_follows_time_of_day() -> void:
	var pip: VillagerData = load("res://data/villagers/pip.tres")
	var state := VillagerState.new()
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 2, "minute": 0 })
	assert_str(VillagerTalk.greeting(pip, state)).is_equal("You're up late.")
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 7, "minute": 0 })
	assert_str(VillagerTalk.greeting(pip, state)).is_equal("Morning!")
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 19, "minute": 0 })
	assert_str(VillagerTalk.greeting(pip, state)).is_equal("Evening already?")


func test_catchphrase_substitution() -> void:
	var pip: VillagerData = load("res://data/villagers/pip.tres")
	assert_str(VillagerTalk.substitute("Hey {name}, {catchphrase}!", pip)).is_equal("Hey Pip, nuts!")


func test_roster_save_round_trip() -> void:
	var state: VillagerState = Game.villagers.get_or_create(&"pip")
	state.friendship = 12
	state.last_spoke_day = "2001-01-01"
	state.mood = VillagerState.Mood.HAPPY
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	assert_bool(Game.villagers.has_id(&"pip")).is_false()
	Game.apply_snapshot(snap)
	assert_bool(Game.villagers.has_id(&"pip")).is_true()
	var loaded: VillagerState = Game.villagers.get_or_create(&"pip")
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


func test_pip_data_is_lazy_squirrel() -> void:
	var pip: VillagerData = load("res://data/villagers/pip.tres")
	assert_that(pip.display_name).is_equal("Pip")
	assert_that(pip.species).is_equal(&"squirrel")
	assert_that(pip.personality.id).is_equal(&"lazy")
	assert_that(pip.schedule_table().activity_at(9)).is_equal(VillagerActivity.FIELD)
	assert_that(pip.dialogue.speaker_id).is_equal(&"pip")


func test_scene_talks_when_in_field() -> void:
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 10, "minute": 0 })
	var villager: Villager = auto_free(load("res://scenes/actors/villager.tscn").instantiate()) as Villager
	assert_that(villager.current_activity()).is_equal(VillagerActivity.FIELD)
	var actions: Array[Interaction] = villager.get_interactions(InteractionContext.new())
	assert_int(actions.size()).is_equal(1)
	assert_bool(villager.interact(actions[0], InteractionContext.new())).is_true()
	assert_int(Game.villagers.get_or_create(&"pip").friendship).is_equal(VillagerState.TALK_FIRST)


func test_motor_stops_when_not_wandering() -> void:
	var motor := VillagerMotor.new()
	motor.reset(Vector3.ZERO)
	motor.set_target(Vector3(3, 0, 0))
	var step: Vector3 = motor.tick(0.1, Vector3.ZERO, Vector3(3, 0, 0), false)
	assert_vector(step).is_equal(Vector3.ZERO)
	motor.set_target(Vector3(3, 0, 0))
	var walk: Vector3 = motor.tick(0.1, Vector3.ZERO, Vector3(3, 0, 0), true)
	assert_float(walk.length()).is_greater(0.1)


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
	assert_that(kinds[kinds.size() - 2]).is_equal(ActivityKind.TALK)
	assert_that(kinds[kinds.size() - 1]).is_equal(ActivityKind.WANDER)


func test_sleep_plan_is_just_sleep_when_already_home() -> void:
	var plan: Array[VillagerAction] = VillagerPlan.build(
		VillagerActivity.SLEEP, &"", {"home": Vector3.ZERO, "outdoors": false}
	)
	assert_int(plan.size()).is_equal(1)
	assert_that(plan[0].kind).is_equal(ActivityKind.SLEEP)
	assert_bool(plan[0].is_present()).is_false()
	assert_bool(plan[0].is_talkable()).is_false()


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


func test_ai_advances_when_action_finishes() -> void:
	var ai := VillagerAI.new()
	ai.sync(
		VillagerActivity.FIELD,
		{
			"home": Vector3.ZERO,
			"outdoors": true,
			"field_actions": [ActivityKind.SIT],
			"sit": Vector3(1, 0, 0),
			"shop": Vector3.INF,
			"water": Vector3.INF,
		}
	)
	assert_that(ai.kind()).is_equal(ActivityKind.WALK_TO)
	ai.consider_arrive(Vector3(1, 0, 0))
	ai.step(0.0)
	assert_that(ai.kind()).is_equal(ActivityKind.SIT)
	ai.step(ActivityKind.SIT_SECONDS + 0.1)
	assert_that(ai.kind()).is_equal(ActivityKind.TALK)


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


func test_catalog_includes_pip_and_other_starters() -> void:
	VillagerCatalog.reload()
	assert_that(VillagerCatalog.get_villager(&"pip")).is_not_null()
	assert_int(VillagerCatalog.starters().size()).is_greater_equal(12)
