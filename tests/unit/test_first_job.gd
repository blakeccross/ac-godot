class_name TestFirstJob
extends GdUnitTestSuite

## Post-house first job (`ac_npc_rcn_guide2` full chore chain).


func before_test() -> void:
	Game.reset_session()
	ItemCatalog.reload()
	DialogueCatalog.reset()


func after_test() -> void:
	DialogueCatalog.reset()
	Game.reset_session()


func test_uniform_item_exists() -> void:
	var item: ItemData = ItemCatalog.get_item(FirstJob.UNIFORM_ID)
	assert_that(item).is_not_null()
	assert_that(item.category).is_equal(ItemData.Category.CLOTH)
	assert_int(item.cloth_index).is_equal(16)


func test_complete_intro_station_starts_first_job() -> void:
	Game.complete_intro_station()
	assert_that(Game.first_job.kind).is_equal(FirstJob.Kind.START)
	assert_bool(Game.first_job.is_active()).is_true()
	assert_that(Game.phase).is_equal(Game.Phase.PLAYING)


func test_change_cloth_finishes_when_worn() -> void:
	var job := FirstJob.new()
	job.setup_change_cloth()
	assert_int(job.progress).is_equal(2)
	job.tick_cloth(FirstJob.UNIFORM_ID)
	assert_int(job.progress).is_equal(0)
	assert_bool(job.cloth_job_finished()).is_true()
	job.tick_cloth(FirstJob.DEFAULT_CLOTH_ID)
	assert_int(job.progress).is_equal(2)


func test_wear_cloth_swaps_pockets() -> void:
	var inv: Inventory = Game.inventory
	var uniform: ItemData = ItemCatalog.get_item(FirstJob.UNIFORM_ID)
	assert_that(uniform).is_not_null()
	Game.cloth_id = FirstJob.DEFAULT_CLOTH_ID
	inv.add(uniform, 1)
	var idx: int = -1
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inv.slot_at(i)
		if slot != null and not slot.is_empty() and slot.item.item_id == FirstJob.UNIFORM_ID:
			idx = i
			break
	assert_int(idx).is_greater_equal(0)
	assert_bool(Game.wear_cloth_from_slot(idx)).is_true()
	assert_that(Game.cloth_id).is_equal(FirstJob.UNIFORM_ID)
	assert_int(inv.count_of(FirstJob.DEFAULT_CLOTH_ID)).is_equal(1)
	assert_int(inv.count_of(FirstJob.UNIFORM_ID)).is_equal(0)


func test_give_uniform_and_plant_kit() -> void:
	var job := FirstJob.new()
	var inv: Inventory = Game.inventory
	assert_bool(job.give_uniform(inv)).is_true()
	assert_int(inv.count_of(FirstJob.UNIFORM_ID)).is_equal(1)
	inv.clear()
	assert_bool(job.give_plant_kit(inv)).is_true()
	assert_int(inv.count_of(&"flower")).is_equal(FirstJob.PLANT_FLOWER_COUNT)
	assert_int(inv.count_of(&"apple_sapling")).is_equal(FirstJob.PLANT_SAPLING_COUNT)


func test_plant_job_finishes_when_pockets_empty_of_plants() -> void:
	var job := FirstJob.new()
	job.setup_plant_flower()
	var inv: Inventory = Game.inventory
	job.give_plant_kit(inv)
	assert_bool(job.plant_job_finished(inv)).is_false()
	inv.clear()
	assert_bool(job.plant_job_finished(inv)).is_true()
	job.mark_plant_finished()
	assert_int(job.progress).is_equal(0)


func test_cloth_tag_includes_wear() -> void:
	var inv: Inventory = Game.inventory
	var uniform: ItemData = ItemCatalog.get_item(FirstJob.UNIFORM_ID)
	inv.add(uniform, 1)
	var idx: int = 0
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inv.slot_at(i)
		if slot != null and not slot.is_empty() and slot.item.item_id == FirstJob.UNIFORM_ID:
			idx = i
			break
	var tags: PackedStringArray = inv.tags_for_slot(idx)
	assert_bool("Wear" in tags).is_true()


func test_job_dialogue_authored() -> void:
	for id: StringName in [
		&"nook_job_arrive",
		&"nook_job_uniform",
		&"nook_job_uniform_wait",
		&"nook_job_uniform_hint",
		&"nook_job_uniform_done",
		&"nook_job_plant",
		&"nook_job_plant_done",
		&"nook_job_intro",
		&"nook_job_furniture",
		&"nook_job_letter",
		&"nook_job_open",
		&"nook_job_carpet",
		&"nook_job_axe",
		&"nook_job_notice",
		&"nook_job_all_done",
		&"tortimer_greeting",
	]:
		assert_that(DialogueCatalog.conversation(id)).is_not_null()


func test_delivery_dialogue_names_recipient() -> void:
	## Every assign / hint graph must keep `{recipient}` so Tom Nook names the target.
	Game.villagers.get_or_create(&"filbert")
	var job: FirstJob = Game.first_job
	assert_bool(job.setup_deliver_furniture(Game.inventory)).is_true()
	assert_bool(job.needs_named_recipient()).is_true()
	var who: String = job.recipient_name()
	assert_str(who).is_not_equal("")
	assert_str(who).is_not_equal("a villager")
	var ctx := DialogueContext.new()
	ctx.recipient = who
	var ids: Array[StringName] = FirstJob.recipient_dialogue_ids()
	assert_int(ids.size()).is_equal(8)
	for id: StringName in ids:
		var data: DialogueData = DialogueCatalog.conversation(id)
		assert_that(data).override_failure_message("missing %s" % String(id)).is_not_null()
		assert_bool(FirstJob.dialogue_names_recipient(data)).override_failure_message(
			"%s must include {recipient}" % String(id)
		).is_true()
		var text: String = ctx.substitute(str(data.node(&"start").get("text", "")))
		assert_str(text).contains(who)
		assert_str(text).not_contains("{recipient}")
	## Broken authored line is replaced so the player still hears a name.
	var broken := DialogueData.from_dict({
		"id": String(FirstJob.DIALOGUE_FURNITURE),
		"start": "start",
		"nodes": {"start": {"type": "line", "text": "Deliver this. Don't open it!"}},
	})
	assert_bool(FirstJob.dialogue_names_recipient(broken)).is_false()
	var fixed: DialogueData = FirstJob.ensure_dialogue_names_recipient(broken, false)
	assert_bool(FirstJob.dialogue_names_recipient(fixed)).is_true()
	assert_str(ctx.substitute(str(fixed.node(&"start").get("text", "")))).contains(who)


func test_advance_plant_to_introductions() -> void:
	var job: FirstJob = Game.first_job
	job.setup_plant_flower()
	job.mark_plant_finished()
	assert_bool(job.needs_introductions()).is_true()
	assert_bool(job.advance_after_finished(Game.inventory)).is_true()
	assert_that(job.kind).is_equal(FirstJob.Kind.INTRODUCTIONS)


func test_introductions_need_tortimer_and_talks() -> void:
	var job: FirstJob = Game.first_job
	job.setup_introductions()
	assert_bool(job.chore_finished()).is_false()
	job.mark_met_tortimer()
	## Still need resident talks unless none exist.
	var ids: Array[StringName] = FirstJob.resident_ids()
	for id: StringName in ids:
		Game.relationships.record_talk(id, "2001-01-01")
	job.refresh_introductions()
	assert_bool(job.chore_finished()).is_true()


func test_delivery_quest_item_and_handoff() -> void:
	var job: FirstJob = Game.first_job
	var inv: Inventory = Game.inventory
	## Seed a known resident.
	Game.villagers.get_or_create(&"filbert")
	assert_bool(job.setup_deliver_furniture(inv)).is_true()
	assert_that(job.kind).is_equal(FirstJob.Kind.DELIVER_FTR)
	assert_that(job.recipient_id).is_not_equal(&"")
	assert_bool(FirstJob._has_quest_item(inv, FirstJob.FURNITURE_ID)).is_true()
	assert_bool(job.can_deliver_to(job.recipient_id, inv)).is_true()
	assert_bool(job.try_deliver_to(job.recipient_id, inv)).is_true()
	assert_bool(job.chore_finished()).is_true()
	assert_bool(FirstJob._has_quest_item(inv, FirstJob.FURNITURE_ID)).is_false()


func test_letter_mail_finishes_chore() -> void:
	var job: FirstJob = Game.first_job
	Game.villagers.get_or_create(&"filbert")
	Game.villagers.get_or_create(&"rosie")
	assert_bool(job.setup_send_letter(Game.inventory)).is_true()
	assert_that(job.kind).is_equal(FirstJob.Kind.SEND_LETTER)
	job.note_letter_mailed(job.recipient_id)
	assert_bool(job.chore_finished()).is_true()


func test_furniture_advance_unlocks_map_and_letter() -> void:
	var job: FirstJob = Game.first_job
	Game.villagers.get_or_create(&"filbert")
	Game.villagers.get_or_create(&"rosie")
	assert_bool(job.setup_deliver_furniture(Game.inventory)).is_true()
	job.try_deliver_to(job.recipient_id, Game.inventory)
	assert_bool(Game.has_map).is_false()
	assert_bool(job.advance_after_finished(Game.inventory)).is_true()
	assert_bool(Game.has_map).is_true()
	assert_that(job.kind).is_equal(FirstJob.Kind.SEND_LETTER)


func test_open_notice_and_finish_chain_tail() -> void:
	var job: FirstJob = Game.first_job
	job.setup_open_quest()
	assert_bool(job.open_quest).is_true()
	job.mark_open_finished()
	Game.villagers.get_or_create(&"filbert")
	assert_bool(job.advance_after_finished(Game.inventory)).is_true()
	assert_that(job.kind).is_equal(FirstJob.Kind.DELIVER_CARPET)
	job.try_deliver_to(job.recipient_id, Game.inventory)
	assert_bool(job.advance_after_finished(Game.inventory)).is_true()
	assert_that(job.kind).is_equal(FirstJob.Kind.DELIVER_AXE)
	job.try_deliver_to(job.recipient_id, Game.inventory)
	assert_bool(job.advance_after_finished(Game.inventory)).is_true()
	assert_that(job.kind).is_equal(FirstJob.Kind.POST_NOTICE)
	job.mark_notice_posted()
	assert_bool(job.advance_after_finished(Game.inventory)).is_true()
	assert_that(job.kind).is_equal(FirstJob.Kind.DONE)
	assert_bool(job.is_active()).is_false()


func test_save_roundtrip() -> void:
	Game.first_job.begin_after_house()
	Game.first_job.setup_change_cloth()
	Game.cloth_id = FirstJob.UNIFORM_ID
	Game.has_map = true
	Game.first_job.recipient_id = &"filbert"
	Game.first_job.used_ids = [&"filbert", &"rosie"]
	var bag: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(bag)
	assert_that(Game.cloth_id).is_equal(FirstJob.UNIFORM_ID)
	assert_bool(Game.has_map).is_true()
	assert_that(Game.first_job.kind).is_equal(FirstJob.Kind.CHANGE_CLOTH)
	assert_int(Game.first_job.progress).is_equal(2)
	assert_that(Game.first_job.recipient_id).is_equal(&"filbert")
