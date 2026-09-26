class_name ShopMail
extends RefCounted

## Letters Nook's store sends (`mPO_delivery_mail_with_order_ftr`,
## `mPO_delivery_mail_with_ticket`, `aSL_SetShopRenewalChirashi_Notice`,
## `mSP_SetRenewalChiraswhi_AppoDay`). Wording is authored here, not the ROM bank.

const SENDER_ID := &"tom_nook"
const MONTHS: Array[String] = [
	"January", "February", "March", "April", "May", "June", "July", "August", "September",
	"October", "November", "December",
]


static func store_name(level: int) -> String:
	match level:
		1:
			return "Nook 'n' Go"
		2:
			return "Nookway"
		3:
			return "Nookington's"
		_:
			return "Nook's Cranny"


static func _base(level: int) -> MailData:
	var mail := MailData.new()
	mail.sender_id = SENDER_ID
	mail.sender_name = store_name(level)
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = Game.player_name if Game != null else "Resident"
	mail.font = MailData.LetterFont.RECV
	mail.header = "Dear %s," % mail.recipient_name
	mail.footer = "— Tom Nook, %s" % store_name(level)
	return mail


## Catalog order: the letter carries the item (`0x049 + shop_level` handbill).
static func order_letter(item_id: StringName, level: int) -> MailData:
	var mail: MailData = _base(level)
	var data: ItemData = ItemCatalog.get_item(item_id)
	mail.font = MailData.LetterFont.RECV_PRESENT
	mail.present_item_id = item_id
	mail.body = (
		"Here is the %s you ordered from our catalog. Thank you for your business!"
		% (data.display_name if data != null else String(item_id))
	)
	return mail


## Raffle tickets that didn't fit in the pockets, up to five per letter.
static func ticket_letter(month: int, count: int) -> MailData:
	var mail: MailData = _base(0)
	var year: int = Clock.year if Clock != null else 2001
	mail.font = MailData.LetterFont.RECV_PRESENT
	mail.present_item_id = ShopBook.ticket_id(month)
	mail.present_count = count
	mail.body = (
		"Your pockets were full, so here are %d raffle ticket%s. The drawing is on %s %d."
		% [count, "" if count == 1 else "s", MONTHS[clampi(month, 1, 12) - 1],
			EventDates.days_in_month(year, clampi(month, 1, 12))]
	)
	return mail


## The store will close the day before its renovation date.
static func renovation_notice(level: int, reopen_ordinal: int) -> MailData:
	var mail: MailData = _base(level)
	var closed: Vector3i = EventDates.from_ordinal(reopen_ordinal - 1)
	var reopen: Vector3i = EventDates.from_ordinal(reopen_ordinal)
	mail.body = (
		"Thanks to your patronage, we're expanding! The store will be closed for renovations "
		+ "on %s %d and will reopen on %s %d."
	) % [MONTHS[closed.y - 1], closed.z, MONTHS[reopen.y - 1], reopen.z]
	return mail


static func grand_opening(level: int) -> MailData:
	var mail: MailData = _base(level)
	mail.body = (
		"Renovations are done, and %s is now open for business! Come see our bigger selection."
		% store_name(level)
	)
	return mail
