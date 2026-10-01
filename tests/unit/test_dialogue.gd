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


func test_message_sex_matches_looks() -> void:
	var peppy: VillagerPersonality = load("res://data/personalities/peppy.tres")
	var lazy: VillagerPersonality = load("res://data/personalities/lazy.tres")
	assert_that(peppy).is_not_null()
	assert_that(lazy).is_not_null()
	## Female looks → pink nameplate; male → cyan (`m_msg_appear`).
	assert_that(peppy.message_sex()).is_equal(1)
	assert_that(lazy.message_sex()).is_equal(0)


func test_dialogue_overlay_matches_msg_timing() -> void:
	## Source constants — keep in sync with `m_msg_appear` / cursol pause frame.
	var src := FileAccess.get_file_as_string("res://scenes/ui/dialogue_overlay.gd")
	assert_str(src).contains("APPEAR_FRAMES := 18.0")
	assert_str(src).contains("CHOICE_APPEAR_FRAMES := 10.2")
	## PAUSE counts 30 Hz frames (`mMsg_Get_CursolSetTimeCode` doubles it).
	var overlay: GDScript = load("res://scenes/ui/dialogue_overlay.gd") as GDScript
	var consts: Dictionary = overlay.get_script_constant_map()
	assert_int(int(consts["PAUSE_FRAME_MULT"])).is_equal(2)


func _open_line(text: String, extra: Dictionary = {}) -> DialogueOverlay:
	var overlay: DialogueOverlay = auto_free(load("res://scenes/ui/dialogue_overlay.tscn").instantiate())
	add_child(overlay)
	var node := {"type": "line", "text": text}
	node.merge(extra)
	var data := DialogueData.from_dict({"id": "fx", "start": "a", "nodes": {"a": node, "b": {"type": "line",
		"text": "Next."}}})
	overlay.play(data, DialogueContext.new())
	overlay._finish_appear()
	return overlay


## `mMsg_Main_Cursol_ControlCursol`: a glyph every other frame; `{p:n}` holds the
## cursor 2n frames before the glyph that follows it.
func test_typewriter_steps_and_pauses_like_the_cursor() -> void:
	var overlay := _open_line("Ab{p:3}cd")
	for _i in 4:
		overlay._type_tick()
	assert_int(overlay._cursor).is_equal(2)
	for _i in 6:
		overlay._type_tick()
	assert_int(overlay._cursor).is_equal(2)
	for _i in 3:
		overlay._type_tick()
	assert_int(overlay._cursor).is_equal(3)


## A page ended by a bare MSGCLEAR turns by itself; a BTN page waits for A.
func test_auto_pages_turn_without_input() -> void:
	var overlay := _open_line("Hi", {"auto": true, "next": "b"})
	for _i in 10:
		overlay._type_tick()
	assert_str(String(overlay.runner().node_id)).is_equal("b")
	var waits := _open_line("Hi", {"next": "b"})
	for _i in 10:
		waits._type_tick()
	assert_str(String(waits.runner().node_id)).is_equal("a")


## `mFontSentence`: a Top-line glyph grows down from the cell top, a Bottom one up.
func test_message_body_scales_glyphs_about_the_line_pivot() -> void:
	var body: MessageBody = auto_free(MessageBody.new())
	body.set_text("{lt:2}{s:64}A{s:32}\nB{p:4}{se:1}")
	assert_int(body.glyph_count()).is_equal(2)
	assert_str(body.glyph_text()).is_equal("AB")
	var marks: Array[Dictionary] = body.marks()
	assert_int(marks.size()).is_equal(2)
	assert_int(int(marks[0]["at"])).is_equal(2)
	assert_str(str(marks[0]["kind"])).is_equal("p")
	assert_str(MessageBody.strip_tags("{c:1,2,3}x{p:4}y{cap}")).is_equal("xy")


func test_normalize_punct_maps_em_dash() -> void:
	## Authored KK/Nook lines use em dashes; NES atlas has ASCII hyphen only.
	var normalized := MessageWindowChrome._normalize_punct("Still — if you've got…")
	assert_str(normalized).is_equal("Still - if you've got...")
	assert_str(normalized).not_contains("—")
	assert_str(normalized).not_contains("…")


func test_body_width_matches_continue_mark() -> void:
	## Soft-wrap budget is the strip ending at `ARROW_UV` (~193 px), not full cloud.
	var max_w: float = MessageWindowChrome.WINDOW_SIZE.x * (
		MessageWindowChrome.ARROW_UV.position.x - MessageWindowChrome.BODY_UV.x
	)
	assert_float(max_w).is_equal_approx(193.0, 1.0)
	var src := FileAccess.get_file_as_string("res://scripts/ui/message_window_chrome.gd")
	assert_str(src).contains("_wrap_body_lines")
	assert_str(src).contains("_strip_style_tags")


func test_authored_dialogue_lines_fit_body() -> void:
	## Guardrail: each authored line (style tags stripped) stays within the body strip.
	## Runtime soft-wrap still covers misses; this keeps JSON readable like the GC bank.
	var dir := DirAccess.open("res://data/dialogue")
	assert_that(dir).is_not_null()
	dir.list_dir_begin()
	var name := dir.get_next()
	var checked := 0
	while name != "":
		if name.ends_with(".json"):
			var data: Variant = JSON.parse_string(
				FileAccess.get_file_as_string("res://data/dialogue/%s" % name)
			)
			assert_that(data).is_not_null()
			var nodes: Dictionary = (data as Dictionary).get("nodes", {})
			for nid: Variant in nodes.keys():
				var node: Dictionary = nodes[nid]
				for field: String in ["text", "prompt"]:
					if not node.has(field) or typeof(node[field]) != TYPE_STRING:
						continue
					var text: String = str(node[field])
					for line: String in text.split("\n"):
						var visible := MessageWindowChrome._strip_style_tags(
							MessageWindowChrome._normalize_punct(line)
						)
						## Placeholders expand shorter than their `{name}` spelling in most cases.
						if visible.contains("{"):
							continue
						checked += 1
						## Approx: average glyph ~6–8 px; hard fail only on extreme lines.
						assert_int(visible.length()).is_less(36)
		name = dir.get_next()
	assert_int(checked).is_greater(20)


func test_capitalize_flag_raises_the_next_string() -> void:
	var ctx := DialogueContext.new()
	ctx.catchphrase = "hum"
	assert_str(ctx.substitute("Pronto! {cap}{catchphrase}!")).is_equal("Pronto! Hum!")


func test_substitute_fills_slots_and_flags_empties() -> void:
	var ctx := DialogueContext.new()
	ctx.player_name = "Blake"
	ctx.speaker_name = "Filbert"
	ctx.town_name = "Oak"
	ctx.recipient = "Rosie"
	ctx.item0 = "apple"
	ctx.frees = PackedStringArray(["", "", "", "1200"])
	var line: String = ctx.substitute(
		"Hi {player} / {speaker} / {town} / {recipient} / {item0} / {free3}"
	)
	assert_str(line).is_equal("Hi Blake / Filbert / Oak / Rosie / apple / 1200")
	assert_array(DialogueContext.leftover_slot_keys(line)).is_empty()
	assert_array(DialogueContext.slot_keys_in("{c:1,2,3}{s:20}hi")).is_empty()
	assert_array(DialogueContext.slot_keys_in("See {recipient}")).contains("recipient")


func test_from_game_fills_first_job_recipient() -> void:
	Game.villagers.get_or_create(&"filbert")
	assert_bool(Game.first_job.setup_deliver_furniture(Game.inventory)).is_true()
	var who: String = Game.first_job.recipient_name()
	var ctx: DialogueContext = DialogueContext.from_game()
	assert_str(ctx.recipient).is_equal(who)
	assert_str(ctx.substitute("Go to {recipient}.")).contains(who)


func test_authored_dialogue_slots_expand() -> void:
	## Every authored `{slot}` must expand under a fully populated context.
	var ctx := DialogueContext.new()
	ctx.player_name = "Blake"
	ctx.speaker_name = "Filbert"
	ctx.catchphrase = "bucko"
	ctx.species = "squirrel"
	ctx.town_name = "Oak"
	ctx.island = "Isle"
	ctx.recipient = "Rosie"
	ctx.item0 = "apple"
	ctx.frees = PackedStringArray()
	for i: int in 20:
		ctx.frees.append("F%d" % i)
	var dir := DirAccess.open("res://data/dialogue")
	assert_that(dir).is_not_null()
	dir.list_dir_begin()
	var fname := dir.get_next()
	var checked := 0
	while fname != "":
		if fname.ends_with(".json"):
			var raw: Variant = JSON.parse_string(
				FileAccess.get_file_as_string("res://data/dialogue/%s" % fname)
			)
			assert_that(raw).is_not_null()
			var nodes: Dictionary = (raw as Dictionary).get("nodes", {})
			for nid: Variant in nodes.keys():
				var node: Dictionary = nodes[nid]
				for field: String in ["text", "prompt"]:
					if not node.has(field) or typeof(node[field]) != TYPE_STRING:
						continue
					var text: String = str(node[field])
					if DialogueContext.slot_keys_in(text).is_empty():
						continue
					var out: String = ctx.substitute(text)
					assert_array(DialogueContext.leftover_slot_keys(out)).override_failure_message(
						"%s %s/%s left unsubstituted slots" % [fname, str(nid), field]
					).is_empty()
					checked += 1
		fname = dir.get_next()
	assert_int(checked).is_greater(5)


func _line(data: DialogueData, ctx: DialogueContext) -> String:
	var runner := DialogueRunner.new()
	runner.start(data, ctx, null)
	return runner.line


## `mMsg_Main_Cursol_Button`: a mid-page BTN stops with the turn mark; A writes on, and
## the page stays the same one.
func test_mid_page_btn_waits_then_writes_on() -> void:
	var overlay := _open_line("Hm.{btn}OK", {"next": "b"})
	for _i in 20:
		overlay._type_tick()
	assert_int(overlay._cursor).is_equal(3)
	assert_bool(overlay._btn_wait).is_true()
	## A dump stops at the BTN too.
	overlay._dump_page()
	assert_int(overlay._cursor).is_equal(3)
	overlay._release_btn()
	for _i in 20:
		overlay._type_tick()
	assert_int(overlay._cursor).is_equal(5)
	assert_str(String(overlay.runner().node_id)).is_equal("a")
