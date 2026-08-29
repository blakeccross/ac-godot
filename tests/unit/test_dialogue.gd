class_name TestDialogue
extends GdUnitTestSuite

## Dialogue graph: conditions, choices, events, variables, runner.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	DialogueCatalog.reset()


func after_test() -> void:
	DialogueCatalog.reset()
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_filbert_json_matches_legacy_greetings() -> void:
	var data: DialogueData = DialogueCatalog.conversation(&"filbert_greeting")
	var filbert: VillagerData = load("res://data/villagers/filbert.tres")
	var state := VillagerState.new()
	Clock.apply_snapshot({"year": 2001, "month": 1, "day": 1, "hour": 10, "minute": 0})
	assert_str(_line(data, DialogueContext.from_game(filbert, state))).is_equal("Nice plot you've got.")
	state.record_talk(VillagerTalk.day_key())
	assert_str(_line(data, DialogueContext.from_game(filbert, state))).is_equal("Still hanging around, huh?")
	Clock.apply_snapshot({"year": 2001, "month": 1, "day": 1, "hour": 2, "minute": 0})
	var fresh := VillagerState.new()
	assert_str(_line(data, DialogueContext.from_game(filbert, fresh))).is_equal("You're up late.")


func test_hello_msg_packs_looks_and_hour() -> void:
	## `aQMgr_actor_get_my_hello_msg_com`: base + looks * 12 + time_kind * 3 + variant.
	assert_int(DialogueGreeting.time_kind(10)).is_equal(DialogueGreeting.TIME_MORNING)
	assert_int(DialogueGreeting.time_kind(14)).is_equal(DialogueGreeting.TIME_DAY)
	assert_int(DialogueGreeting.time_kind(20)).is_equal(DialogueGreeting.TIME_EVENING)
	assert_int(DialogueGreeting.time_kind(2)).is_equal(DialogueGreeting.TIME_NIGHT)
	assert_int(DialogueGreeting.msg_offset(1213, 2, 10, 0)).is_equal(1237)
	assert_int(DialogueGreeting.msg_offset(1285, 2, 10, 0)).is_equal(1309)
	var filbert: VillagerData = load("res://data/villagers/filbert.tres")
	var rosie: VillagerData = load("res://data/villagers/rosie.tres")
	var state := VillagerState.new()
	var ctx := DialogueContext.from_game(filbert, state)
	ctx.hour = 10
	ctx.rng = RandomNumberGenerator.new()
	ctx.rng.seed = 1
	assert_int(DialogueGreeting.meet_type(state, ctx)).is_equal(DialogueGreeting.MEET_FIRST)
	var first: int = DialogueGreeting.hello_msg_no(filbert, state, ctx)
	assert_int(first).is_greater_equal(1213)
	assert_int(first).is_less(1213 + 6 * 12)
	ctx.rng.seed = 1
	var peppy: int = DialogueGreeting.hello_msg_no(rosie, state, ctx)
	assert_that(peppy).is_not_equal(first)
	state.last_spoke_day = "2001-01-01"
	ctx.already_talked = true
	ctx.days_since_talk = 0
	assert_int(DialogueGreeting.meet_type(state, ctx)).is_equal(DialogueGreeting.MEET_AGAIN)


func test_looks_fallback_uses_personality() -> void:
	var data: DialogueData = DialogueGreeting.fallback_conversation()
	var ctx := DialogueContext.new()
	ctx.personality = &"peppy"
	ctx.time_of_day = ClockService.TimeOfDay.DAY
	assert_str(_line(data, ctx)).is_equal("Hi hi!")
	ctx.personality = &"lazy"
	assert_str(_line(data, ctx)).is_equal("Hey Player.")
	ctx.already_talked = true
	assert_str(_line(data, ctx)).is_equal("Still hanging around, huh?")


func test_friendship_time_weather_item_conditions() -> void:
	var data: DialogueData = DialogueData.from_dict({
		"id": "cond",
		"start": "start",
		"nodes": {
			"start": {
				"type": "branch",
				"when": [
					{"if": {"weather": "rain"}, "goto": "rain"},
					{"if": {"friendship_gte": 10, "has_item": "apple"}, "goto": "friend"},
					{"if": {"hours": [6, 8]}, "goto": "morning"},
					{"goto": "else"},
				],
			},
			"rain": {"type": "line", "text": "rain"},
			"friend": {"type": "line", "text": "friend"},
			"morning": {"type": "line", "text": "morning"},
			"else": {"type": "line", "text": "else"},
		},
	})
	var ctx := DialogueContext.new()
	ctx.weather = &"rain"
	assert_str(_line(data, ctx)).is_equal("rain")
	ctx.weather = &"clear"
	ctx.friendship = 12
	ctx.items[&"apple"] = 1
	assert_str(_line(data, ctx)).is_equal("friend")
	ctx.friendship = 0
	ctx.items.clear()
	ctx.hour = 7
	assert_str(_line(data, ctx)).is_equal("morning")
	ctx.hour = 15
	assert_str(_line(data, ctx)).is_equal("else")


func test_choices_and_events_and_variables() -> void:
	var data: DialogueData = DialogueData.from_dict({
		"id": "shop",
		"start": "ask",
		"nodes": {
			"ask": {
				"type": "choice",
				"prompt": "Need anything?",
				"options": [
					{
						"text": "Yes",
						"goto": "give",
						"if": {"has_item": "apple"},
						"events": [{"op": "set_var", "name": "said_yes", "value": 1}],
					},
					{"text": "Bye", "goto": "bye"},
				],
			},
			"give": {
				"type": "line",
				"text": "Here you go, {player}.",
				"events": [{"op": "add_friendship", "amount": 5}, {"op": "take_item", "item": "apple", "count": 1}],
			},
			"bye": {"type": "line", "text": "Later."},
		},
	})
	var inv := Inventory.new()
	inv.add(load("res://data/items/apple.tres"), 1)
	var ctx := DialogueContext.new()
	ctx.player_name = "Blake"
	ctx.inventory = inv
	ctx.vars = Game.dialogue_vars
	var state := VillagerState.new()
	var runner := DialogueRunner.new()
	runner.start(data, ctx, state)
	assert_bool(runner.waiting_choice).is_true()
	assert_int(runner.choices.size()).is_equal(2)
	runner.choose(0)
	assert_str(runner.line).is_equal("Here you go, Blake.")
	assert_int(int(Game.dialogue_vars.get("said_yes", 0))).is_equal(1)
	assert_int(state.friendship).is_equal(5)
	assert_int(inv.count_of(&"apple")).is_equal(0)
	runner.advance()
	assert_bool(runner.done).is_true()


func test_hidden_choice_when_item_missing() -> void:
	var data: DialogueData = DialogueData.from_dict({
		"id": "gate",
		"start": "ask",
		"nodes": {
			"ask": {
				"type": "choice",
				"options": [
					{"text": "Apple", "goto": "ok", "if": {"has_item": "apple"}},
					{"text": "Nope", "goto": "no"},
				],
			},
			"ok": {"type": "line", "text": "ok"},
			"no": {"type": "line", "text": "no"},
		},
	})
	var runner := DialogueRunner.new()
	runner.start(data, DialogueContext.new(), null)
	assert_int(runner.choices.size()).is_equal(1)
	assert_str(str(runner.choices[0].get("text", ""))).is_equal("Nope")
	runner.choose(0)
	assert_str(runner.line).is_equal("no")


func test_catalog_loads_authored_json() -> void:
	DialogueCatalog.reset()
	var data: DialogueData = DialogueCatalog.conversation(&"filbert_greeting")
	assert_that(data).is_not_null()
	assert_that(data.speaker_id).is_equal(&"filbert")
	assert_bool(data.has_node(&"day")).is_true()


func test_save_round_trip_dialogue_vars_and_weather() -> void:
	Game.player_name = "Blake"
	Game.town_name = "Cedar"
	Game.set_weather(&"rain")
	Game.dialogue_vars["met_tom"] = 1
	var path := "user://test_dialogue_save.json"
	assert_int(SaveService.save_game(path)).is_equal(OK)
	Game.reset_session()
	assert_int(SaveService.load_game(path)).is_equal(OK)
	assert_str(Game.player_name).is_equal("Blake")
	assert_str(Game.town_name).is_equal("Cedar")
	assert_that(Game.weather).is_equal(&"rain")
	assert_int(int(Game.dialogue_vars.get("met_tom", 0))).is_equal(1)
	SaveService.delete_save(path)


func _line(data: DialogueData, ctx: DialogueContext) -> String:
	var runner := DialogueRunner.new()
	runner.start(data, ctx, null)
	return runner.line
