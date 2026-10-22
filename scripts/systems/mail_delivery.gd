class_name MailDelivery
extends RefCounted

## Who writes to the player and where the letters land. A letter goes to the home mailbox,
## and when that is full the post office keeps it (see `to_mailbox_or_post`).

const NEW_MAIL_NOTICE := "You've got mail!"


## `mQst_SendRemail`: straight to the home mailbox, nowhere else.
static func to_mailbox(mail: MailData) -> bool:
	return Game.inventory.add_received_mail(mail) >= 0


## The mailbox, else the post office holds it for the player.
static func to_mailbox_or_post(mail: MailData) -> bool:
	return to_mailbox(mail) or Game.post.receipt_mail(mail)


## A letter the post office is carrying: it reaches whichever resident it is addressed to.
static func from_post_office(mail: MailData) -> bool:
	var resident: PlayerState = Game.resident
	if mail.recipient_name == resident.player_name:
		return to_mailbox(mail)
	var roster: PlayerRoster = Game.roster
	for slot: int in PlayerRoster.MAX:
		if slot != roster.current and roster.name_of(slot) == mail.recipient_name:
			return roster.deliver_mail(slot, mail)
	## Nobody here by that name any more (`mMl_hunt_for_send_address` -1): it is dropped.
	return true


## `mPO_business_proc`: the 9:00 and 17:00 rounds, and the first one of a session
## (`mPO_first_work`).
static func deliver_post_office_rounds(session_start: bool) -> void:
	if Game.foreigner:
		return
	Game.post.deliver(Clock.absolute_minute(), from_post_office, session_start)


## `vt_wt_mail_check`: Valentine's letters once, on February 14th.
static func send_valentines(rng: RandomNumberGenerator) -> void:
	var resident: PlayerState = Game.resident
	if Clock.month != 2 or Clock.day != 14 or resident.valentine_year == Clock.year:
		return
	resident.valentine_year = Clock.year
	VillagerLetters.send_valentines(
		Game.residents, Game.relationships, resident.player_gender == &"female",
		resident.player_name, rng, to_mailbox
	)


## Birthday cards once the birthday has passed since the last check
## (`mNpc_SendEventBirthdayCard2`). On the day itself the villager who will bring the present
## is picked now, so their card doesn't come as well.
static func send_birthday_cards(rng: RandomNumberGenerator) -> void:
	var resident: PlayerState = Game.resident
	var today: int = EventDates.ordinal(Clock.year, Clock.month, Clock.day)
	var last_check: int = resident.birthday_card_day
	resident.birthday_card_day = today
	var birthday: Vector2i = VillagerTalkManager.birthday()
	if not PresentVisit.birthday_passed(birthday, last_check, today):
		return
	if resident.celebrated_birthday_year != Clock.year:
		var is_today: bool = birthday == Vector2i(Clock.month, Clock.day)
		resident.birthday_present_npc = (
			PresentVisit.birthday_npc(Game.residents, Game.relationships) if is_today else &""
		)
	var sent: int = PresentVisit.send_cards(
		Game.residents, Game.relationships, resident.birthday_present_npc, resident.player_name,
		rng, to_mailbox_or_post
	)
	if sent > 0:
		Game.post_notice(NEW_MAIL_NOTICE)


## `mPr_SendMailFromMother`: Mom writes, at most once a day.
static func send_mother_mail(rng: RandomNumberGenerator) -> void:
	var resident: PlayerState = Game.resident
	var sent: int = MotherMail.check(
		resident.mother_mail, EventDates.ordinal(Clock.year, Clock.month, Clock.day),
		VillagerTalkManager.birthday(), MotherMail.holiday(Clock.year, Clock.month, Clock.day),
		resident.player_name, rng, to_mailbox_or_post
	)
	if sent >= 0:
		Game.post_notice(NEW_MAIL_NOTICE)


## `mNpc_ForceRemove`: the goodbye letter from a villager who is moving out
## (`mNpc_SetGoodbyMailData`, mail `0x20E + looks * 3 + rand(3)`). It goes to the mailbox, else
## the post office (`mNpc_SendGoodbyAnimalMailOne`).
static func send_goodbye(villager_id: StringName, looks: int, rng: RandomNumberGenerator) -> void:
	if looks < 0 or looks >= TownResidents.LOOKS_NUM or not MailBank.has_bank():
		return
	var resident: PlayerState = Game.resident
	var villager: VillagerData = VillagerCatalog.get_villager(villager_id)
	var villager_name: String = villager.display_name if villager != null else String(villager_id)
	var mail_no: int = 0x20E + looks * 3 + rng.randi_range(0, 2)
	var text: Dictionary = MailBank.letter(
		mail_no, resident.player_name,
		{0: resident.player_name, 1: villager_name, 3: Game.town.town_name}
	)
	var mail := MailData.new()
	mail.sender_id = villager_id
	mail.sender_name = villager_name
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = resident.player_name
	mail.font = MailData.LetterFont.RECV
	mail.header = str(text["header"])
	mail.body = str(text["body"])
	mail.footer = str(text["footer"])
	## `mNpc_GetPaperType`: a random stationery pick (the shop paper lists aren't ported).
	mail.paper_type = rng.randi_range(0, MailBank.PAPER_NUM - 1)
	to_mailbox_or_post(mail)


## `mMl_send_postoffice_mail`: a balance milestone's gift by mail, one per game start.
static func send_bank_gift() -> void:
	var resident: PlayerState = Game.resident
	var gift: Dictionary = BankTerminal.due_gift(Game.inventory.savings, resident.bank_gift_flags)
	if gift.is_empty():
		return
	var letter: MailData = BankTerminal.gift_letter(gift, Game.town.town_name, resident.player_name)
	if to_mailbox(letter):
		resident.bank_gift_flags |= int(gift["flag"])


## `mMkRm_MarkRoom` at game start: the Happy Room Academy's welcome, grade or tip.
static func send_academy_mark() -> void:
	var house: House = Game.interiors.player_house()
	if house == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var busy: bool = Game.first_job.is_active()
	var letter: MailData = Game.hra.mark(
		house, Game.interiors.room(PlayerHouse.MAIN), Game.interiors.room(PlayerHouse.UPPER),
		Vector3i(Clock.year, Clock.month, Clock.day), busy, Game.resident.player_name, rng
	)
	if letter != null:
		to_mailbox(letter)


## The Farway Museum returns identified fossils (and the one-time intro letter) each morning.
static func deliver_farway_mail() -> void:
	_deliver_all(Game.travel_book.process_delivery())


## Nook's letters each morning: catalog orders, mailed raffle tickets, renovation notices.
static func deliver_nook_mail() -> void:
	var letters: Array[MailData] = Game.shops.take_mail()
	letters.append_array(Game.catalog.take_deliveries())
	_deliver_all(letters)


static func _deliver_all(letters: Array[MailData]) -> void:
	var delivered: int = 0
	for letter: MailData in letters:
		if to_mailbox(letter):
			delivered += 1
	if delivered > 0:
		Game.post_notice(NEW_MAIL_NOTICE)
