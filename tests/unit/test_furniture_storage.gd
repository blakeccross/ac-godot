class_name TestFurnitureStorage
extends GdUnitTestSuite

var _session: IndoorSession
var _chest: FurnitureData
var _stereo: FurnitureData


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	InteriorCatalog.reset()
	ItemCatalog.reload()
	FurnitureProfiles.reset()
	var room: Room = Game.interiors.room(&"player_main")
	room.placements.clear()
	_session = IndoorSession.new()
	_session.bind(room)
	_chest = ItemCatalog.get_item(&"wood_dresser") as FurnitureData
	_stereo = FurnitureData.new()
	_stereo.id = &"test_stereo"
	_stereo.kind = FurnitureData.Kind.MUSIC
	_stereo.can_store = true
	_stereo.storage_slots = 1
	_stereo.starts_off = true
	_stereo.visual_id = &"int_test_stereo"
	ItemCatalog.remember(_stereo)


func after_test() -> void:
	Game.reset_session()
	InteriorCatalog.reset()
	FurnitureProfiles.reset()
	Clock.reset_to_default()
	Clock.paused = false


func _chest_entry() -> FurniturePlacement:
	return _session.place(_chest, Vector2i(2, 2), WorldGrid.Facing.SOUTH)


func _player_entry() -> FurniturePlacement:
	return _session.place(_stereo, Vector2i(3, 1), WorldGrid.Facing.SOUTH)


func _line_of(dialogue: StringName, var_name: String, scene: StringName, prep: Callable = Callable()) -> DialogueRunner:
	var ctx := DialogueContext.new()
	if prep.is_valid():
		prep.call(ctx)
	ctx.set_var(var_name, String(scene))
	var runner := DialogueRunner.new()
	runner.start(DialogueCatalog.conversation(dialogue), ctx)
	return runner


## --- chest contents -----------------------------------------------------------------------


func test_scene_follows_how_many_things_are_inside() -> void:
	var entry: FurniturePlacement = _chest_entry()
	assert_that(FurnitureStorage.scene_for(entry, true)).is_equal(&"empty")
	FurnitureStorage.put_in(entry, &"apple")
	assert_that(FurnitureStorage.scene_for(entry, true)).is_equal(&"one")
	FurnitureStorage.put_in(entry, &"apple")
	assert_that(FurnitureStorage.scene_for(entry, true)).is_equal(&"two")
	FurnitureStorage.put_in(entry, &"apple")
	assert_that(FurnitureStorage.scene_for(entry, true)).is_equal(&"three")
	assert_that(FurnitureStorage.scene_for(entry, false)).is_equal(&"other_three")


func test_a_chest_holds_three_things() -> void:
	var entry: FurniturePlacement = _chest_entry()
	for _i: int in 3:
		assert_bool(FurnitureStorage.put_in(entry, &"apple")).is_true()
	assert_bool(FurnitureStorage.put_in(entry, &"apple")).is_false()
	assert_int(FurnitureStorage.count(entry)).is_equal(3)


func test_taking_out_closes_the_gap() -> void:
	var entry: FurniturePlacement = _chest_entry()
	entry.stored = PackedStringArray(["apple", "", "axe"])
	FurnitureStorage.tidy(entry)
	assert_array(Array(entry.stored)).is_equal(["apple", "axe"])
	assert_that(FurnitureStorage.take_out(entry, 0, Game.inventory)).is_equal(&"ok")
	assert_array(Array(entry.stored)).is_equal(["axe"])


func test_full_pockets_leave_the_item_inside() -> void:
	var entry: FurniturePlacement = _chest_entry()
	FurnitureStorage.put_in(entry, &"axe")
	var axe: ItemData = ItemCatalog.get_item(&"axe")
	while Game.inventory.has_space_for(axe, 1):
		Game.inventory.add(axe, 1)
	assert_that(FurnitureStorage.take_out(entry, 0, Game.inventory)).is_equal(&"full")
	assert_int(FurnitureStorage.count(entry)).is_equal(1)


func test_taking_from_an_empty_slot_is_nothing() -> void:
	assert_that(FurnitureStorage.take_out(_chest_entry(), 0, Game.inventory)).is_equal(&"none")


func test_message_reads_out_the_names() -> void:
	var entry: FurniturePlacement = _chest_entry()
	entry.stored = PackedStringArray(["apple", "axe"])
	var runner: DialogueRunner = _line_of(
		FurnitureStorage.DIALOGUE_ID,
		FurnitureStorage.VAR_SCENE,
		&"two",
		func(ctx: DialogueContext) -> void: FurnitureStorage.fill_context(ctx, entry)
	)
	var apple: ItemData = ItemCatalog.get_item(&"apple")
	assert_bool(runner.waiting_choice).is_true()
	assert_bool(runner.line.contains(apple.display_name)).is_true()
	assert_bool(runner.line.contains("{")).is_false()


func test_every_chest_scene_opens_a_conversation() -> void:
	for scene: StringName in [
		&"empty", &"one", &"two", &"three",
		&"other_empty", &"other_one", &"other_two", &"other_three",
		&"pockets_full", &"nothing_to_put",
	]:
		var runner: DialogueRunner = _line_of(FurnitureStorage.DIALOGUE_ID, FurnitureStorage.VAR_SCENE, scene)
		assert_bool(runner.line != "" or runner.waiting_choice).override_failure_message("no line for %s" % scene).is_true()


func test_the_owner_can_put_in_or_take_out_and_visitors_only_listen() -> void:
	var owner_run: DialogueRunner = _line_of(FurnitureStorage.DIALOGUE_ID, FurnitureStorage.VAR_SCENE, &"one")
	assert_bool(owner_run.waiting_choice).is_true()
	assert_int(owner_run.choices.size()).is_equal(3)
	var visitor: DialogueRunner = _line_of(FurnitureStorage.DIALOGUE_ID, FurnitureStorage.VAR_SCENE, &"other_one")
	assert_bool(visitor.waiting_choice).is_false()


func test_three_things_offer_only_taking_out() -> void:
	var runner: DialogueRunner = _line_of(FurnitureStorage.DIALOGUE_ID, FurnitureStorage.VAR_SCENE, &"three")
	assert_int(runner.choices.size()).is_equal(4)
	var events: Array[Dictionary] = []
	runner.event_fired.connect(func(event: Dictionary) -> void: events.append(event))
	runner.choose(1)
	assert_array(events).has_size(1)
	assert_that(events[0]["op"]).is_equal("storage_take")
	assert_int(int(events[0]["index"])).is_equal(1)


func test_put_in_answer_fires_the_put_event() -> void:
	var runner: DialogueRunner = _line_of(FurnitureStorage.DIALOGUE_ID, FurnitureStorage.VAR_SCENE, &"empty")
	var events: Array[Dictionary] = []
	runner.event_fired.connect(func(event: Dictionary) -> void: events.append(event))
	runner.choose(0)
	assert_that(events[0]["op"]).is_equal("storage_put")
	assert_bool(runner.done).is_true()


func test_each_chest_type_has_its_own_clips() -> void:
	for type: int in [FurnitureData.StorageType.DRAWERS, FurnitureData.StorageType.WARDROBE, FurnitureData.StorageType.CLOSET]:
		assert_bool(FurnitureStorage.OPEN_CLIPS.has(type)).is_true()
		assert_bool(FurnitureStorage.CLOSE_CLIPS.has(type)).is_true()
	assert_that(FurnitureStorage.OPEN_CLIPS[FurnitureData.StorageType.DRAWERS]).is_equal(&"ply_1_kagu_open_h1")


func test_open_offers_the_matching_open_clip() -> void:
	var node: Node = auto_free(load("res://scenes/world/furniture.tscn").instantiate())
	var wardrobe: FurnitureData = FurnitureData.new()
	wardrobe.id = &"test_wardrobe"
	wardrobe.kind = FurnitureData.Kind.STORAGE
	wardrobe.can_store = true
	wardrobe.storage_type = FurnitureData.StorageType.WARDROBE
	node.set("data", wardrobe)
	add_child(node)
	var ctx := InteractionContext.new()
	ctx.inventory = Game.inventory
	var action: Interaction = Interaction.primary(node.get_interactions(ctx))
	assert_that(action.id).is_equal(Interaction.OPEN)
	assert_that(action.player_anim).is_equal(&"ply_1_kagu_open_k1")


## --- profiles from the disc ---------------------------------------------------------------


func test_profile_flags_decide_kind_and_shape() -> void:
	var closet := FurnitureData.new()
	closet.apply_profile({"shape": "TYPEA", "contact": [], "interaction": ["STORAGE_CLOSET"], "vtable": 1})
	assert_that(closet.kind).is_equal(FurnitureData.Kind.STORAGE)
	assert_that(closet.storage_type).is_equal(FurnitureData.StorageType.CLOSET)
	var bed := FurnitureData.new()
	bed.apply_profile({"shape": "TYPEB_0", "contact": ["BED_SINGLE"], "interaction": []})
	assert_that(bed.kind).is_equal(FurnitureData.Kind.BED)
	assert_that(bed.footprint).is_equal(Vector2i(2, 1))
	var sofa := FurnitureData.new()
	sofa.apply_profile({"shape": "TYPEB_0", "contact": ["CHAIR_SOFA"], "interaction": []})
	assert_bool(sofa.is_sittable()).is_true()
	var stool := FurnitureData.new()
	stool.apply_profile({"shape": "TYPEA", "contact": ["CHAIR_MULTIDIRECTIONAL"], "interaction": []})
	assert_that(stool.contact).is_equal(FurnitureData.Contact.CHAIR_ANY)
	var player := FurnitureData.new()
	player.apply_profile({"shape": "TYPEB_0", "contact": [], "interaction": ["MUSIC_DISK"]})
	assert_bool(player.is_music_player()).is_true()
	assert_bool(player.starts_off).is_true()
	assert_int(player.keep_count()).is_equal(1)
	var radio := FurnitureData.new()
	radio.apply_profile({"shape": "TYPEA", "contact": [], "interaction": ["RADIO_AEROBICS"]})
	assert_bool(radio.is_toggleable()).is_true()
	var rug := FurnitureData.new()
	rug.apply_profile({"shape": "TYPEC", "contact": [], "interaction": ["NO_COLLISION"]})
	assert_bool(rug.blocks_walk).is_false()
	assert_that(rug.footprint).is_equal(Vector2i(2, 2))


func test_disc_profiles_when_generated() -> void:
	if not FurnitureProfiles.available():
		return
	var closet: FurnitureData = ItemCatalog.furniture_for_visual(&"int_sum_hal_chest02")
	assert_that(closet.kind).is_equal(FurnitureData.Kind.STORAGE)
	assert_that(closet.storage_type).is_equal(FurnitureData.StorageType.CLOSET)
	var bed: FurnitureData = ItemCatalog.furniture_for_visual(&"int_sum_asi_bed01")
	assert_bool(bed.is_bed()).is_true()
	assert_bool(bed.footprint.x * bed.footprint.y >= 2).is_true()


## --- music --------------------------------------------------------------------------------


func test_there_are_55_discs_with_songs() -> void:
	assert_int(MinidiskCatalog.COUNT).is_equal(55)
	for i: int in MinidiskCatalog.COUNT:
		var disc: ItemData = ItemCatalog.get_item(MinidiskCatalog.item_id(i))
		assert_that(disc).is_not_null()
		assert_int(MinidiskCatalog.index_of(disc.id)).is_equal(i)
	assert_bool(MinidiskCatalog.is_disc(&"apple")).is_false()
	assert_int(MinidiskCatalog.index_of(&"minidisk_99")).is_equal(-1)


func test_songs_map_to_the_md_bgm_numbers() -> void:
	assert_int(MinidiskCatalog.BGM_FIRST).is_equal(128)
	assert_int(MinidiskCatalog.BGM_FIRST + MinidiskCatalog.COUNT - 1).is_equal(182)


func test_music_box_bits_survive_a_save_past_53_bits() -> void:
	var house: House = Game.interiors.player_house()
	assert_bool(MinidiskCatalog.box_add(house, 54)).is_true()
	assert_bool(MinidiskCatalog.box_add(house, 54)).is_false()
	MinidiskCatalog.box_add(house, 0)
	var copy := House.new()
	copy.apply_snapshot(JSON.parse_string(JSON.stringify(house.to_save())))
	assert_bool(MinidiskCatalog.box_has(copy, 54)).is_true()
	assert_bool(MinidiskCatalog.box_has(copy, 0)).is_true()
	assert_array(MinidiskCatalog.box_songs(copy)).is_equal([0, 54])


func test_a_new_disc_joins_the_box_is_used_up_and_plays() -> void:
	var house: House = Game.interiors.player_house()
	var entry: FurniturePlacement = _player_entry()
	var disc: ItemData = ItemCatalog.get_item(MinidiskCatalog.item_id(7))
	Game.inventory.add(disc, 1)
	var result: Dictionary = FurnitureMusic.insert_disc(_session, entry, house, disc.id, Game.inventory)
	assert_that(result["result"]).is_equal(&"ok")
	assert_int(Game.inventory.count_of(disc.id)).is_equal(0)
	assert_bool(MinidiskCatalog.box_has(house, 7)).is_true()
	assert_int(FurnitureMusic.song_of(entry)).is_equal(7)
	assert_bool(entry.on).is_true()


func test_a_disc_the_box_already_has_stays_in_your_pocket() -> void:
	var house: House = Game.interiors.player_house()
	MinidiskCatalog.box_add(house, 3)
	var entry: FurniturePlacement = _player_entry()
	var disc: ItemData = ItemCatalog.get_item(MinidiskCatalog.item_id(3))
	Game.inventory.add(disc, 1)
	var result: Dictionary = FurnitureMusic.insert_disc(_session, entry, house, disc.id, Game.inventory)
	assert_that(result["result"]).is_equal(&"duplicate")
	assert_int(Game.inventory.count_of(disc.id)).is_equal(1)
	assert_int(FurnitureMusic.song_of(entry)).is_equal(-1)


func test_only_one_player_sounds_at_a_time() -> void:
	var first: FurniturePlacement = _player_entry()
	var second: FurniturePlacement = _session.place(_stereo, Vector2i(1, 1), WorldGrid.Facing.SOUTH)
	FurnitureMusic.select_song(_session, first, 1)
	FurnitureMusic.select_song(_session, second, 2)
	assert_bool(second.on).is_true()
	assert_bool(first.on).is_false()


func test_an_empty_player_cannot_be_switched_on() -> void:
	var entry: FurniturePlacement = _player_entry()
	FurnitureMusic.set_switch(_session, entry, true)
	assert_bool(entry.on).is_false()


func test_the_room_plays_the_active_players_song() -> void:
	var entry: FurniturePlacement = _player_entry()
	assert_that(FurnitureMusic.active_bgm(_session.room)).is_equal(&"")
	FurnitureMusic.select_song(_session, entry, 4)
	var expected: StringName = MinidiskCatalog.bgm_id(4)
	assert_that(FurnitureMusic.active_bgm(_session.room)).is_equal(expected)
	FurnitureMusic.set_switch(_session, entry, false)
	assert_that(FurnitureMusic.active_bgm(_session.room)).is_equal(&"")


func test_music_scenes_follow_the_disc_and_switch() -> void:
	var entry: FurniturePlacement = _player_entry()
	assert_that(FurnitureMusic.scene_for(entry, true)).is_equal(&"music_empty")
	FurnitureMusic.select_song(_session, entry, 2)
	assert_that(FurnitureMusic.scene_for(entry, true)).is_equal(&"music_on")
	FurnitureMusic.set_switch(_session, entry, false)
	assert_that(FurnitureMusic.scene_for(entry, true)).is_equal(&"music_off")
	assert_that(FurnitureMusic.scene_for(entry, false)).is_equal(&"other_music")


func test_every_music_scene_opens_a_conversation() -> void:
	for scene: StringName in [
		&"music_empty", &"music_off", &"music_on", &"other_music", &"other_music_empty",
		&"box_empty", &"box_pick", &"duplicate", &"no_disc",
	]:
		var runner: DialogueRunner = _line_of(FurnitureMusic.DIALOGUE_ID, FurnitureMusic.VAR_SCENE, scene)
		assert_bool(runner.line != "" or runner.waiting_choice).override_failure_message("no line for %s" % scene).is_true()


func test_the_music_box_steps_through_songs() -> void:
	var events: Array[Dictionary] = []
	var runner: DialogueRunner = _line_of(
		FurnitureMusic.DIALOGUE_ID,
		FurnitureMusic.VAR_SCENE,
		&"box_pick",
		func(ctx: DialogueContext) -> void: ctx.item0 = "First"
	)
	runner.event_fired.connect(func(event: Dictionary) -> void: events.append(event))
	runner.choose(1)
	assert_bool(runner.waiting_choice).is_true()
	assert_that(events[0]["op"]).is_equal("music_step")
	runner.choose(0)
	assert_that(events[1]["op"]).is_equal("music_play")
	assert_bool(runner.done).is_true()


func test_the_pockets_offer_put_in_only_for_what_was_asked() -> void:
	var apple: ItemData = ItemCatalog.get_item(&"apple")
	var disc: ItemData = ItemCatalog.get_item(MinidiskCatalog.item_id(0))
	assert_bool(Inventory.putin_allowed(apple, &"any")).is_true()
	assert_bool(Inventory.putin_allowed(apple, &"minidisk")).is_false()
	assert_bool(Inventory.putin_allowed(disc, &"minidisk")).is_true()
	assert_bool(Game.inventory.has_putin_candidates(&"minidisk")).is_false()
	Game.inventory.add(disc, 1)
	assert_bool(Game.inventory.has_putin_candidates(&"minidisk")).is_true()


func test_pocket_picker_hands_back_the_pick() -> void:
	var picked: Array[StringName] = []
	Game.storage_putin_resolved.connect(func(id: StringName) -> void: picked.append(id))
	Game.storage_putin_pending = true
	Game.take_storage_putin(&"apple")
	assert_array(picked).is_equal([&"apple"])
	Game.storage_putin_pending = true
	Game.cancel_storage_putin()
	assert_array(picked).is_equal([&"apple", &""])
	Game.cancel_storage_putin()
	assert_int(picked.size()).is_equal(2)


## --- radio and gyroids --------------------------------------------------------------------


func test_the_aerobics_radio_plays_its_own_music_and_silences_players() -> void:
	var radio := FurnitureData.new()
	radio.id = &"test_radio"
	radio.radio_aerobics = true
	radio.starts_off = true
	radio.visual_id = &"int_test_radio"
	ItemCatalog.remember(radio)
	var entry: FurniturePlacement = _session.place(radio, Vector2i(1, 1), WorldGrid.Facing.SOUTH)
	var player: FurniturePlacement = _player_entry()
	FurnitureMusic.select_song(_session, player, 2)
	FurnitureMusic.set_switch(_session, entry, true)
	assert_bool(entry.on).is_true()
	assert_bool(player.on).is_false()
	assert_that(FurnitureMusic.active_bgm(_session.room)).is_equal(FurnitureMusic.AEROBICS_BGM)
	FurnitureMusic.set_switch(_session, entry, false)
	assert_that(FurnitureMusic.active_bgm(_session.room)).is_equal(&"")


func test_the_radio_only_answers_from_the_front() -> void:
	var radio := FurnitureData.new()
	radio.radio_aerobics = true
	var node: Node = auto_free(load("res://scenes/world/furniture.tscn").instantiate())
	node.set("data", radio)
	add_child(node)
	var ctx := InteractionContext.new()
	ctx.inventory = Game.inventory
	ctx.contact_side = FurnitureGrip.ContactSide.BACK
	assert_int(node.get_interactions(ctx).size()).is_equal(0)
	ctx.contact_side = FurnitureGrip.ContactSide.FRONT
	assert_int(node.get_interactions(ctx).size()).is_equal(1)
