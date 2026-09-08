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
	var box: Node = load("res://scenes/world/mailbox.tscn").instantiate()
	auto_free(box)
	add_child(box)
	var notices: Array[String] = []
	Game.notice_posted.connect(func(t: String) -> void: notices.append(t))
	box.interact(Interaction.of(Interaction.READ, "Check mailbox", 10), null)
	assert_str(notices[-1]).contains("empty")
	Game.inventory.add_received_mail(_recv_letter())
	## With no inventory UI mounted, the mailbox falls back to a notice.
	box.interact(Interaction.of(Interaction.READ, "Check mailbox", 10), null)
	assert_str(notices[-1]).contains("letter")


func test_mailbox_label_shows_unread_count() -> void:
	var box: Node = load("res://scenes/world/mailbox.tscn").instantiate()
	auto_free(box)
	add_child(box)
	Game.inventory.add_received_mail(_recv_letter())
	Game.inventory.add_received_mail(_recv_letter())
	var actions: Array = box.get_interactions(null)
	assert_str(actions[0].prompt).contains("2")
