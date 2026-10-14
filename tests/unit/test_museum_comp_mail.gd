class_name TestMuseumCompMail
extends GdUnitTestSuite

## The museum-complete letter (`mMsm_SetCompMail`, `mMsm_SendCompMail`).


func before_test() -> void:
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()


func test_nothing_until_the_museum_is_full() -> void:
	assert_bool(MuseumCompMail.schedule()).is_false()
	assert_bool(MuseumCompMail.send()).is_false()


func test_every_resident_gets_it_once_at_their_next_start() -> void:
	Game.roster.current = 0
	Game.roster.slots[2] = {"player_name": "Ann"}
	Game.museum.fill_complete()
	assert_bool(MuseumCompMail.schedule()).is_true()
	assert_bool(MuseumCompMail.schedule()).is_false()
	assert_int(int(Game.roster.slots[2][MuseumCompMail.KEY])).is_equal(MuseumCompMail.SCHEDULED)
	assert_bool(Game.roster.slots[1].has(MuseumCompMail.KEY)).is_false()
	assert_bool(MuseumCompMail.send()).is_true()
	assert_bool(MuseumCompMail.send()).is_false()
	var found: MailData = null
	for i: int in Inventory.MAIL_SLOTS:
		var mail: MailData = Game.inventory.mail_at(i)
		if mail != null and mail.present_item_id == MuseumCompMail.PRESENT:
			found = mail
	assert_object(found).is_not_null()
	assert_str(found.body).is_not_empty()
	assert_object(ItemCatalog.get_item(MuseumCompMail.PRESENT)).is_not_null()


func test_it_is_saved() -> void:
	Game.museum.fill_complete()
	assert_bool(MuseumCompMail.schedule()).is_true()
	var saved: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(saved)
	assert_int(Game.museum_comp_mail).is_equal(MuseumCompMail.SCHEDULED)
