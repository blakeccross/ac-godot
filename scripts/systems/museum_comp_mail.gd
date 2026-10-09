class_name MuseumCompMail
extends RefCounted

## The museum's thank-you once every wing is full (`mMsm_SetCompMail`, `mMsm_SendCompMail`):
## Blathers' last donation marks it for every resident, and each gets the letter with the
## museum model at their next start of play.
##
## The disc counts all 15 paintings, two of which Blathers always turns away, so there it never
## comes; here "full" is `MuseumBook.is_complete`, the same as Blathers' own lines.

const LETTER := 0x22F
const PAPER := 24
## `FTR_NOG_MUSEUM`.
const PRESENT := &"ftr_1036"
const SENDER := "Museum"
const SCHEDULED := 1
const RECEIVED := 2
const KEY := "museum_comp_mail"


## `mMsm_SetCompMail`: once, for every resident in town.
static func schedule() -> bool:
	if Game == null or Game.museum == null or not Game.museum.is_complete():
		return false
	if Game.museum_comp_mail & SCHEDULED:
		return false
	if Game.roster != null:
		for slot: int in PlayerRoster.MAX:
			var priv: Dictionary = Game.roster.slots[slot]
			if slot == Game.roster.current or not PlayerRoster.is_resident(priv):
				continue
			if int(priv.get(KEY, 0)) & SCHEDULED:
				return false
		for slot: int in PlayerRoster.MAX:
			var priv: Dictionary = Game.roster.slots[slot]
			if slot != Game.roster.current and PlayerRoster.is_resident(priv):
				priv[KEY] = int(priv.get(KEY, 0)) | SCHEDULED
	Game.museum_comp_mail |= SCHEDULED
	return true


## `mMsm_SendCompMail` at the start of play: the letter, if it is due and not had yet.
static func send() -> bool:
	if Game == null or Game.foreigner or Game.inventory == null:
		return false
	if Game.museum_comp_mail & SCHEDULED == 0 or Game.museum_comp_mail & RECEIVED:
		return false
	var mail: MailData = letter(Game.player_name, Game.town_name)
	if Game.inventory.add_received_mail(mail) < 0 and (Game.post == null or not Game.post.receipt_mail(mail)):
		return false
	Game.museum_comp_mail |= RECEIVED
	return true


static func letter(player: String, town: String) -> MailData:
	var text: Dictionary = MailBank.letter(LETTER, player, {0: town})
	var mail := MailData.new()
	mail.sender_id = PostUse.MUSEUM_RECIPIENT_ID
	mail.sender_name = SENDER
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = player
	mail.paper_type = PAPER
	mail.font = MailData.LetterFont.RECV_PRESENT
	mail.present_item_id = PRESENT
	mail.header = str(text.get("header", ""))
	mail.body = str(text.get("body", ""))
	mail.footer = str(text.get("footer", ""))
	return mail
