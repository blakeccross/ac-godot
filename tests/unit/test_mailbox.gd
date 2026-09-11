class_name TestMailbox
extends GdUnitTestSuite

## The player-house mailbox and the received-mail helpers behind it.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func _recv_letter(with_item: bool = false) -> MailData:
	var m := MailData.new()
	m.sender_name = "Farway Museum"
	m.sender_type = MailData.NameType.NPC
	m.font = MailData.LetterFont.RECV_PRESENT if with_item else MailData.LetterFont.RECV
	m.header = "Hello,"
	m.body = "A letter for you."
	if with_item:
		m.present_item_id = &"fossil"
	return m


func test_generated_town_places_a_mailbox_by_the_house() -> void:
	var data: WorldData = WorldGenerator.generate(4242)
	var house: Vector2i = Vector2i.ZERO
	var mailbox: Vector2i = Vector2i(-99, -99)
	for b: BuildingPlacement in data.buildings:
		if b != null and b.id == &"player_house":
			house = b.cell
	for o: ObjectPlacement in data.objects:
		if o != null and o.id == &"player_mailbox":
			mailbox = o.cell
			assert_that(o.kind).is_equal(&"mailbox")
	assert_int(absi(mailbox.x - house.x) + absi(mailbox.y - house.y)).is_between(1, 6)


func test_received_mail_helpers_count_unread_and_delivered() -> void:
	assert_int(Game.inventory.received_mail_count()).is_equal(0)
	Game.inventory.add_received_mail(_recv_letter())
	Game.inventory.add_received_mail(_recv_letter(true))
	assert_int(Game.inventory.received_mail_count()).is_equal(2)
	assert_int(Game.inventory.unread_mail_count()).is_equal(2)
	Game.inventory.mail_at(0).mark_read()
	assert_int(Game.inventory.unread_mail_count()).is_equal(1)


func test_mailbox_interaction_reports_empty_then_has_mail() -> void:
	Clock.month = 6
	var box: Node = load("res://scenes/world/mailbox.tscn").instantiate()
	auto_free(box)
	add_child(box)
	var notices: Array[String] = []
	Game.notice_posted.connect(func(t: String) -> void: notices.append(t))
	await box.interact(Interaction.of(Interaction.READ, "Check mailbox", 10), null)
	assert_str(notices[-1]).contains("empty")
	Game.inventory.add_received_mail(_recv_letter())
	## With no inventory UI mounted, the mailbox falls back to a notice.
	await box.interact(Interaction.of(Interaction.READ, "Check mailbox", 10), null)
	assert_str(notices[-1]).contains("letter")


func test_last_used_mail_index_matches_decomp_scan() -> void:
	## `mMB_get_last_mail_idx`: scans backward for the first occupied slot; all-empty
	## falls back to slot 0.
	assert_int(Game.inventory.last_used_mail_index()).is_equal(0)
	Game.inventory.add_received_mail(_recv_letter())
	assert_int(Game.inventory.last_used_mail_index()).is_equal(0)
	Game.inventory.add_received_mail(_recv_letter())
	Game.inventory.add_received_mail(_recv_letter())
	assert_int(Game.inventory.last_used_mail_index()).is_equal(2)
	Game.inventory.remove_mail(2)
	assert_int(Game.inventory.last_used_mail_index()).is_equal(1)


func test_mailbox_opens_letters_at_the_last_used_slot() -> void:
	Clock.month = 6
	var overlay: CanvasLayer = (
		load("res://scenes/ui/inventory_overlay.tscn") as PackedScene
	).instantiate() as CanvasLayer
	auto_free(overlay)
	add_child(overlay)
	overlay.add_to_group("inventory_ui")
	Game.inventory.add_received_mail(_recv_letter())
	Game.inventory.add_received_mail(_recv_letter())
	Game.inventory.select_mail(0)
	var box: Node = load("res://scenes/world/mailbox.tscn").instantiate()
	auto_free(box)
	add_child(box)
	var anim: AnimationPlayer = box.get("_anim")
	box.interact(Interaction.of(Interaction.READ, "Read mail (2)", 10), null)
	## `aMBX_pl_open`: the lid finishes opening before the Letters menu appears.
	await anim.animation_finished
	assert_int(Game.inventory.selected_mail_index).is_equal(1)
	overlay.call("close")


func test_mailbox_label_shows_unread_count() -> void:
	var box: Node = load("res://scenes/world/mailbox.tscn").instantiate()
	auto_free(box)
	add_child(box)
	Game.inventory.add_received_mail(_recv_letter())
	Game.inventory.add_received_mail(_recv_letter())
	var actions: Array = box.get_interactions(null)
	assert_str(actions[0].prompt).contains("2")


func test_mailbox_flag_raises_on_delivery_and_lowers_when_all_read() -> void:
	## `obj_w_post` (winter) has no baked flag clips yet — pin a summer date so the
	## `obj_s_post` visual (and its AnimationPlayer) loads.
	Clock.month = 6
	var box: Node = load("res://scenes/world/mailbox.tscn").instantiate()
	auto_free(box)
	add_child(box)
	var anim: AnimationPlayer = box.get("_anim")
	assert_object(anim).is_not_null()
	assert_str(anim.current_animation).is_equal("obj_s_post")
	Game.inventory.add_received_mail(_recv_letter())
	assert_str(anim.current_animation).is_equal("obj_s_post_flag_on1")
	await anim.animation_finished
	assert_str(anim.current_animation).is_equal("obj_s_post_flag_on_wait1")
	Game.inventory.remove_mail(0)
	assert_str(anim.current_animation).is_equal("obj_s_post_flag_off1")
	await anim.animation_finished
	assert_str(anim.current_animation).is_equal("obj_s_post")


func test_mailbox_check_plays_open_clip_then_resumes_flag_pose() -> void:
	## `aMBX_pl_open` / `aMBX_pl_close`: the lid finishes opening before the letters menu
	## appears (here, before the empty-UI fallback notice), then closes (same clip
	## reversed) before the flag pose resumes.
	Clock.month = 6
	var box: Node = load("res://scenes/world/mailbox.tscn").instantiate()
	auto_free(box)
	add_child(box)
	Game.inventory.add_received_mail(_recv_letter())
	var anim: AnimationPlayer = box.get("_anim")
	await anim.animation_finished
	assert_str(anim.current_animation).is_equal("obj_s_post_flag_on_wait1")
	box.interact(Interaction.of(Interaction.READ, "Read mail (1)", 10), null)
	assert_str(anim.current_animation).is_equal("obj_s_post_open1")
	await anim.animation_finished
	## Lid open finished; now closing (same clip, reversed) before any flag pose resumes.
	assert_str(anim.current_animation).is_equal("obj_s_post_open1")
	assert_bool(anim.is_playing()).is_true()
	await anim.animation_finished
	assert_str(anim.current_animation).is_equal("obj_s_post_flag_on_wait1")
