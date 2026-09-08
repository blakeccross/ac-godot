class_name TestFarwayMail
extends GdUnitTestSuite

## Fossil dig -> Farway Museum mail-in -> identified fossil returns -> donatable.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_fossil_catalog_registers_identified_items() -> void:
	assert_int(FossilCatalog.count()).is_equal(25)
	var trex := FossilCatalog.get_item(FossilCatalog.item_id_for_index(3))
	assert_that(trex).is_not_null()
	assert_that(MuseumDisplay.map_item(trex).get("category")).is_equal(MuseumDisplay.Category.FOSSIL)


func test_send_fossils_queues_and_returns_next_day() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"fossil"), 2)
	var msg: String = Game.send_fossils_to_farway(2)
	assert_str(msg).contains("Farway")
	assert_int(Game.inventory.count_of(&"fossil")).is_equal(0)
	assert_int(Game.farway.in_transit_count()).is_equal(2)
	## Same day: nothing back yet.
	assert_array(Game.farway.process_delivery(FarwayBook.today_ordinal())).is_empty()
	## Next day: two identified-fossil letters.
	var letters: Array = Game.farway.process_delivery(FarwayBook.today_ordinal() + 1)
	assert_int(letters.size()).is_equal(2)
	for letter: MailData in letters:
		assert_bool(letter.has_enclosure()).is_true()
		var fossil := FossilCatalog.get_item(letter.present_item_id)
		assert_that(fossil).is_not_null()
	assert_int(Game.farway.in_transit_count()).is_equal(0)


func test_intro_letter_sends_once() -> void:
	Game.farway.request_intro_letter()
	var first: Array = Game.farway.process_delivery(FarwayBook.today_ordinal())
	assert_int(first.size()).is_equal(1)
	assert_bool((first[0] as MailData).is_received()).is_true()
	Game.farway.request_intro_letter()
	assert_array(Game.farway.process_delivery(FarwayBook.today_ordinal())).is_empty()


func test_delivered_letter_lands_in_mailbox_and_enclosure_is_takeable() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"fossil"), 1)
	Game.send_fossils_to_farway(1)
	var letters: Array = Game.farway.process_delivery(FarwayBook.today_ordinal() + 1)
	var slot: int = Game.inventory.add_received_mail(letters[0])
	assert_int(slot).is_greater_equal(0)
	var mail: MailData = Game.inventory.mail_at(slot)
	assert_str(mail.label()).contains("From")
	var fossil_id: StringName = mail.present_item_id
	Game.inventory.add(FossilCatalog.get_item(fossil_id), 1)
	## Donating the identified fossil writes the museum nibble.
	var res: Dictionary = Game.donate_museum_result(fossil_id)
	assert_bool(res.get("ok", false)).is_true()
	assert_int(Game.museum.count_fossils()).is_equal(1)


func test_field_renew_delivers_mail_and_notifies() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"fossil"), 1)
	Game.send_fossils_to_farway(1)
	## Roll the calendar forward a day and fire the 06:00 renew.
	Clock.apply_snapshot({"year": Clock.year, "month": Clock.month, "day": Clock.day + 1, "hour": 6})
	Game._on_field_renewed(1)
	assert_int(Game.inventory.count_mail()).is_greater_equal(1)
