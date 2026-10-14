class_name TestVillagerLetters
extends GdUnitTestSuite

## `LetterCheck` (`m_mail_check_ovl.c`) and `VillagerLetters` (`mNpc_SendMailtoNpc`,
## `mNpc_Remail`, `mNpc_SendVtdayMail`).

const GOOD := "Hi there! How are you doing today? I hope you are having a great time in our town. See you soon at the shop!"
const BAD := "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"


func before_test() -> void:
	VillagerCatalog.reload()


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_encode_pads_to_the_body_length() -> void:
	var bytes: PackedByteArray = LetterCheck.encode("Hi\nyou")
	assert_int(bytes.size()).is_equal(192)
	assert_int(bytes[0]).is_equal(72)
	assert_int(bytes[2]).is_equal(LetterCheck.NEW_LINE)
	assert_int(bytes[10]).is_equal(LetterCheck.SPACE)


func test_structure_checks_without_the_syllable_tables() -> void:
	## Everything except type B is table-free; check a few rules directly.
	var bad: PackedByteArray = LetterCheck.encode(BAD)
	assert_int(LetterCheck._type_d(bad, 88)).is_equal(-50)
	assert_int(LetterCheck._type_e(bad, 88)).is_equal(-20)
	assert_int(LetterCheck._type_g(bad, 88)).is_equal(-40)
	var good: PackedByteArray = LetterCheck.encode(GOOD)
	var n: int = LetterCheck._strlen_new(good, 192)
	assert_int(LetterCheck._type_c(good, n)).is_equal(20)
	assert_int(LetterCheck._type_e(good, n)).is_equal(20)
	assert_int(LetterCheck._type_f(good, n)).is_equal(0)
	assert_int(LetterCheck._type_a(good, n)).is_greater(0)


func test_rank_good_and_bad_letters() -> void:
	assert_int(LetterCheck.rank(BAD)).is_equal(LetterCheck.Rank.BAD)
	if not LetterCheck.has_tables():
		return
	assert_int(LetterCheck.rank(GOOD)).is_equal(LetterCheck.Rank.OK)


func test_receive_moves_friendship_like_send_mail_to_npc() -> void:
	var bond := Relationship.new()
	bond.set_friendship(20)
	var mail := MailData.make_send(&"stu", "Stu", BAD)
	assert_int(VillagerLetters.receive(bond, mail, 100)).is_equal(LetterCheck.Rank.BAD)
	assert_int(bond.friendship).is_equal(18)
	assert_bool(bond.send_reply).is_true()
	assert_int(bond.letter_cond).is_equal(int(LetterCheck.Rank.BAD))
	mail.present_item_id = &"apple"
	VillagerLetters.receive(bond, mail, 100)
	assert_int(bond.friendship).is_equal(19)
	## A letter to someone never met makes the memory (friendship 0 + the letter's delta).
	var stranger := Relationship.new()
	VillagerLetters.receive(stranger, MailData.make_send(&"x", "X", BAD), 100)
	assert_bool(stranger.has_memory).is_true()
	assert_int(stranger.friendship).is_equal(0)


func _town() -> TownResidents:
	var t := TownResidents.new()
	var houses: Array[Dictionary] = []
	var rng := _rng(7)
	var i: int = 0
	for v: VillagerData in VillagerCatalog.pick_starters(rng, 6):
		houses.append({"id": v.id, "home": Vector2i(20 + i * 8, 40)})
		i += 1
	t.adopt_from_houses(houses)
	return t


func test_replies_wait_a_day_then_go_out() -> void:
	if not MailBank.has_bank():
		return
	var town: TownResidents = _town()
	var book := RelationshipBook.new()
	var id: StringName = town.slots[0]["id"]
	var bond: Relationship = book.get_or_create(id)
	bond.record_talk("2001-01-01")
	VillagerLetters.receive(bond, MailData.make_send(id, "V", BAD), 100)
	var box: Array[MailData] = []
	var deliver := func(m: MailData) -> bool:
		box.append(m)
		return true
	assert_int(VillagerLetters.send_replies(town, book, 100, "Ann", _rng(), deliver)).is_equal(0)
	assert_int(VillagerLetters.send_replies(town, book, 101, "Ann", _rng(), deliver)).is_equal(1)
	assert_bool(bond.send_reply).is_false()
	assert_str(box[0].header).contains("Ann")
	assert_that(box[0].sender_id).is_equal(id)
	## `mNpc_GetRemailWrongData`: 0xC5 + looks × 3 + 0..2.
	var looks: int = int(VillagerCatalog.get_villager(id).personality.looks)
	var wrong: Array[String] = []
	for k: int in 3:
		wrong.append(MailBank.text("mail", 0xC5 + looks * 3 + k).strip_edges(false, true))
	assert_bool(box[0].body in wrong).is_true()


func test_good_reply_is_stitched_from_the_z_pieces() -> void:
	if not MailBank.has_bank():
		return
	var v: VillagerData = VillagerCatalog.get_villager(&"stu")
	for seed_value: int in 10:
		var mail: MailData = VillagerLetters.reply(v, int(LetterCheck.Rank.OK), "Ann", "Bob", _rng(seed_value))
		if mail == null:
			continue
		assert_str(mail.body).is_not_empty()
		assert_bool(mail.body.contains("{free")).is_false()
		assert_bool(mail.header.contains("{name}")).is_false()


func test_valentines_go_to_the_other_sex_best_friends_first() -> void:
	if not MailBank.has_bank():
		return
	var town: TownResidents = _town()
	var book := RelationshipBook.new()
	for id: StringName in town.resident_ids():
		book.get_or_create(id).record_talk("2001-01-01")
	var close: StringName = &""
	for id: StringName in town.resident_ids():
		if TownResidents.looks_sex(int(VillagerCatalog.get_villager(id).personality.looks)) == TownResidents.SEX_MALE:
			close = id
			break
	book.get_or_create(close).set_friendship(90)
	var box: Array[MailData] = []
	var sent: int = VillagerLetters.send_valentines(
		town, book, true, "Ann", _rng(), func(m: MailData) -> bool:
			box.append(m)
			return true
	)
	## Three male starters (one per looks) → three letters, the best friend first.
	assert_int(sent).is_equal(3)
	assert_that(box[0].sender_id).is_equal(close)
	assert_that(box[0].present_item_id).is_not_equal(&"")
