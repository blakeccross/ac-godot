class_name TestMuseumDialogue
extends GdUnitTestSuite

## Blathers greeting graph: nocturnal opener, one-time orientation, daily repeat.


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


func _ctx(hour: int, already_talked: bool = false, orientation_done: bool = false) -> DialogueContext:
	var ctx := DialogueContext.new()
	ctx.player_name = "Blake"
	ctx.town_name = "Oak"
	ctx.speaker_name = "Blathers"
	ctx.hour = hour
	ctx.already_talked = already_talked
	if orientation_done:
		ctx.set_var("museum_orientation_done", "yes")
	return ctx


func _greeting() -> DialogueData:
	return DialogueCatalog.conversation(&"blathers_greeting")


func test_daytime_first_visit_wakes_with_a_start() -> void:
	var runner := DialogueRunner.new()
	runner.start(_greeting(), _ctx(13), null)
	assert_str(runner.line).contains("lie-down")


func test_nighttime_first_visit_is_alert() -> void:
	var runner := DialogueRunner.new()
	runner.start(_greeting(), _ctx(22), null)
	assert_str(runner.line).contains("civilised")


func test_first_visit_reaches_orientation_then_menu() -> void:
	var runner := DialogueRunner.new()
	var ctx := _ctx(22)
	runner.start(_greeting(), ctx, null)
	var guard := 0
	while not runner.done and not runner.waiting_choice and guard < 40:
		guard += 1
		runner.advance()
	## First choice in the graph is the "shall I stop?" prompt.
	assert_bool(runner.waiting_choice).is_true()
	assert_str(runner.line).contains("prattle")
	runner.choose(1) # "That's quite alright."
	assert_str(str(ctx.get_var("museum_orientation_done", ""))).is_equal("yes")
	while not runner.done and not runner.waiting_choice and guard < 80:
		guard += 1
		runner.advance()
	assert_bool(runner.waiting_choice).is_true()
	assert_str(runner.line).contains("help you with")


func test_orientation_skipped_once_done() -> void:
	var runner := DialogueRunner.new()
	runner.start(_greeting(), _ctx(22, false, true), null)
	## Straight to the menu prompt, no orientation lines.
	var guard := 0
	while not runner.done and not runner.waiting_choice and guard < 20:
		guard += 1
		runner.advance()
	assert_bool(runner.waiting_choice).is_true()
	assert_str(runner.line).contains("help you with")


func test_repeat_visit_same_day_is_brief() -> void:
	var runner := DialogueRunner.new()
	runner.start(_greeting(), _ctx(22, true, true), null)
	assert_str(runner.line).contains("Well met")


func _game_ctx() -> DialogueContext:
	var ctx := DialogueContext.from_game()
	ctx.speaker_name = "Blathers"
	return ctx


func _walk_to_choice(runner: DialogueRunner) -> void:
	var guard := 0
	while not runner.done and not runner.waiting_choice and guard < 120:
		guard += 1
		runner.advance()


func test_donate_conversation_lists_donatable_pocket_items() -> void:
	Game.inventory.add(FishCatalog.get_fish(&"carp"), 1)
	var data: DialogueData = MuseumDialogue.build_donate()
	var runner := DialogueRunner.new()
	runner.start(data, _game_ctx(), null)
	assert_bool(runner.waiting_choice).is_true()
	var labels: Array = []
	for c: Dictionary in runner.choices:
		labels.append(str(c.get("text", "")))
	assert_array(labels).contains(["Carp"])


func test_donating_a_fish_commits_and_removes_it() -> void:
	Game.inventory.add(FishCatalog.get_fish(&"carp"), 1)
	var runner := DialogueRunner.new()
	runner.start(MuseumDialogue.build_donate(&"carp"), _game_ctx(), null)
	## preselect opens on the examine line; advance through examine -> trivia -> commit.
	_walk_to_choice(runner)
	assert_bool(Game.museum.has_fish_id(&"carp")).is_true()
	assert_int(Game.inventory.count_of(&"carp")).is_equal(0)
	## Lands on the "anything else?" choice.
	assert_str(runner.line).contains("anything else")


func test_generic_fossil_routes_to_farway_referral() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"fossil"), 1)
	var runner := DialogueRunner.new()
	runner.start(MuseumDialogue.build_donate(&"fossil"), _game_ctx(), null)
	assert_str(runner.line).contains("Farway")
	_walk_to_choice(runner)
	assert_int(Game.inventory.count_of(&"fossil")).is_equal(1) # not consumed


func test_already_donated_bug_gets_release_it_outdoors() -> void:
	var bug: BugData = BugCatalog.get_by_type(0)
	assert_that(bug).is_not_null()
	Game.museum.set_insect(bug.type_index, int(MuseumBook.Donator.PLAYER1))
	Game.inventory.add(bug, 1)
	var runner := DialogueRunner.new()
	runner.start(MuseumDialogue.build_donate(bug.id), _game_ctx(), null)
	assert_str(runner.line).contains("OUT of doors")
	assert_int(Game.inventory.count_of(bug.id)).is_equal(1)


func test_completing_a_skeleton_plays_the_lecture() -> void:
	## Donate the first two Triceratops parts, then the third completes the set.
	for i: int in [0, 1]:
		Game.museum.set_fossil(i, int(MuseumBook.Donator.PLAYER1))
	var part := FurnitureData.new()
	part.id = MuseumDisplay.FOSSIL_VISUALS[2]
	part.visual_id = MuseumDisplay.FOSSIL_VISUALS[2]
	ItemCatalog.remember(part)
	Game.inventory.add(part, 1)
	var runner := DialogueRunner.new()
	runner.start(MuseumDialogue.build_donate(part.id), _game_ctx(), null)
	var guard := 0
	var saw_triceratops := false
	while not runner.done and not runner.waiting_choice and guard < 120:
		guard += 1
		runner.advance()
		if runner.line.contains("Triceratops"):
			saw_triceratops = true
	assert_bool(saw_triceratops).is_true()


func test_donate_select_pockets_flow() -> void:
	## Blathers opens the pockets; a caught fish gets a "Donate" tag; picking it commits.
	Game.inventory.add(FishCatalog.get_fish(&"carp"), 1)
	Game.request_museum_donation()
	assert_bool(Game.museum_donate_pending).is_true()
	var slot: int = -1
	for i: int in Inventory.POCKET_SLOTS:
		var s: InventorySlot = Game.inventory.slot_at(i)
		if s != null and not s.is_empty() and s.item.item_id == &"carp":
			slot = i
	assert_array(Game.inventory.tags_for_slot(slot)).contains(["Donate"])
	var resolved: Array[bool] = []
	Game.museum_donate_resolved.connect(func(d: bool) -> void: resolved.append(d))
	Game.take_museum_donation(&"carp")
	assert_bool(Game.museum_donate_pending).is_false()
	assert_array(resolved).is_equal([true])
	assert_bool(Game.museum.has_fish_id(&"carp")).is_true()
	assert_int(Game.inventory.count_of(&"carp")).is_equal(0)


func test_cancel_donation_emits_false() -> void:
	Game.request_museum_donation()
	var resolved: Array[bool] = []
	Game.museum_donate_resolved.connect(func(d: bool) -> void: resolved.append(d))
	Game.cancel_museum_donation()
	assert_array(resolved).is_equal([false])
	assert_bool(Game.museum_donate_pending).is_false()


func test_build_outcome_uses_the_stored_result() -> void:
	## Donatable fish -> examine + trivia + "anything else?".
	Game.inventory.add(FishCatalog.get_fish(&"koi"), 1)
	var res: Dictionary = Game.donate_museum_result(&"koi")
	res["item_id"] = "koi"
	var runner := DialogueRunner.new()
	runner.start(MuseumDialogue.build_outcome(&"koi", res), _game_ctx(), null)
	var guard := 0
	var saw_koi := false
	while not runner.done and not runner.waiting_choice and guard < 60:
		guard += 1
		runner.advance()
		if runner.line.to_lower().contains("koi"):
			saw_koi = true
	assert_bool(saw_koi).is_true()
	assert_str(runner.line).contains("anything else")


func test_build_outcome_generic_fossil_is_farway_referral() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"fossil"), 1)
	var res: Dictionary = Game.donate_museum_result(&"fossil")
	var runner := DialogueRunner.new()
	runner.start(MuseumDialogue.build_outcome(&"fossil", res), _game_ctx(), null)
	assert_str(runner.line).contains("Farway")


func test_donate_choice_emits_museum_menu_event() -> void:
	var runner := DialogueRunner.new()
	var ctx := _ctx(22, true, true)
	runner.start(_greeting(), ctx, null)
	while not runner.done and not runner.waiting_choice:
		runner.advance()
	var seen: Array[Dictionary] = []
	runner.event_fired.connect(func(e: Dictionary) -> void: seen.append(e))
	runner.choose(0) # "I've something to donate."
	assert_int(seen.size()).is_greater_equal(1)
	assert_str(String(seen[0].get("op", ""))).is_equal("museum_menu")
	assert_str(String(seen[0].get("choice", ""))).is_equal("donate")
