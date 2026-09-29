class_name VillagerLetters
extends RefCounted

## Letters between the player and town villagers (`m_npc.c`).
##
## - `receive` (`mNpc_SendMailtoNpc`, run when the post office takes the letter): the villager
##   keeps it in the player's memory, scores it (`LetterCheck`), and friendship moves +3,
##   −5 more for a bad letter, +3 more with a present. A good or bad letter (not an
##   in-between one) earns a reply.
## - `send_replies` (`mNpc_Remail`, at load): every villager holding a letter from an
##   earlier day writes back. Good letters get a reply stitched from the `mailz` pieces, half
##   the time with a present; bad ones get a short "that was odd" letter.

## `mNpc_GetRemailGoodData` first message per looks (`this_start_no`).
const GOOD_START: Array[int] = [0x020, 0x040, 0x000, 0x060, 0x080, 0x0A0]
## `mNpc_GetRemailWrongData`: `0xC5 + looks × 3 + rand 3`.
const WRONG_START := 0xC5
## `mNpc_SetRemailFreeString` word tables (string_data), FREE_STR3…13.
const FREE_WORDS: Array[int] = [0x314, 0x334, 0x2F4, 0x6A1, 0x679, 0x354, 0x374, 0x394, 0x3D4, 0x3F4, 0x3B4]
const FREE_WORD_COUNT: Array[int] = [32, 32, 32, 40, 40, 32, 32, 32, 32, 32, 32]
const BODY_LEN := 192
## `mHandbillz_dummy_size_tbl` for the three body pieces.
const PIECE_MAX := 200
## `mNpc_EVENT_MAIL_*`.
const EVENT_BEST_FRIEND := 0
const EVENT_OK_FRIEND := 1
const EVENT_NOT_FRIEND := 2


## `mNpc_SendMailtoNpc`. Returns the letter's rank.
static func receive(bond: Relationship, mail: MailData, day: int) -> LetterCheck.Rank:
	if bond == null or mail == null:
		return LetterCheck.Rank.NONE
	bond.has_memory = true
	bond.letter_exists = true
	bond.letter = {
		"header": mail.header,
		"body": mail.body,
		"footer": mail.footer,
		"present": String(mail.present_item_id),
		"paper_type": mail.paper_type,
	}
	bond.letter_day = day
	var rank: LetterCheck.Rank = LetterCheck.rank(mail.body)
	## `mNpc_SetMailCondThisLand`: only a clear verdict records a reply.
	if rank != LetterCheck.Rank.NONE:
		bond.letter_cond = int(rank)
		bond.send_reply = true
	var delta: int = 3
	if rank == LetterCheck.Rank.BAD:
		delta -= 5
	if mail.present_item_id != &"":
		delta += 3
	bond.add_friendship(delta)
	return rank


## `mNpc_Remail`: replies, residents in slot order, while the mailbox / post office has room.
static func send_replies(
	residents: TownResidents, book: RelationshipBook, day: int, player: String, rng: RandomNumberGenerator,
	deliver: Callable
) -> int:
	var sent: int = 0
	for id: StringName in residents.resident_ids():
		if not book.has_id(id):
			continue
		var bond: Relationship = book.get_or_create(id)
		if not bond.has_memory or not bond.send_reply:
			continue
		## `mNpc_CheckLetterTime`: not on the day it arrived.
		if bond.letter_day < 0 or bond.letter_day == day:
			continue
		var villager: VillagerData = VillagerCatalog.get_villager(id)
		var mail: MailData = reply(villager, bond.letter_cond, player, other_villager(residents, id, rng), rng)
		if mail == null or not bool(deliver.call(mail)):
			break
		bond.send_reply = false
		sent += 1
	return sent


## `mNpc_GetRemailData` for a town villager.
static func reply(
	villager: VillagerData, cond: int, player: String, other: String, rng: RandomNumberGenerator
) -> MailData:
	if villager == null or not MailBank.has_bank():
		return null
	var looks: int = int(villager.personality.looks) if villager.personality != null else 0
	var free: Dictionary = free_strings(player, villager.display_name, other, rng)
	var mail := MailData.new()
	if cond == int(LetterCheck.Rank.OK):
		var parts: Dictionary = _good_parts(looks, free, rng)
		if parts.is_empty():
			return null
		mail.header = parts["header"]
		mail.body = parts["body"]
		mail.footer = parts["footer"]
		mail.present_item_id = parts["present"]
	else:
		var text: Dictionary = MailBank.letter(WRONG_START + looks * 3 + rng.randi_range(0, 2), player, free)
		mail.header = text["header"]
		mail.body = text["body"]
		mail.footer = text["footer"]
	mail.sender_id = villager.id
	mail.sender_name = villager.display_name
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = player
	mail.font = MailData.LetterFont.RECV_PRESENT if mail.present_item_id != &"" else MailData.LetterFont.RECV
	## `mSP_SelectRandomItem_New(mSP_KIND_PAPER, ABC)`; the shop paper lists aren't ported.
	mail.paper_type = rng.randi_range(0, MailBank.PAPER_NUM - 1)
	return mail


## `mNpc_GetRemailGoodData` + `mNpc_GetHandbillz` / `mHandbillz_load`.
static func _good_parts(looks: int, free: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var base: int = GOOD_START[clampi(looks, 0, 5)]
	## `RANDOM(4) & 1`: 0 → a present, picked before the text.
	var give_present: int = rng.randi_range(0, 3) & 1
	var present: StringName = &""
	if give_present == 0:
		present = reply_present(rng)
	var super_no: int = base + rng.randi_range(0, 31)
	var a_no: int = base + rng.randi_range(0, 31)
	var b_no: int = base + rng.randi_range(0, 15) + give_present * 16
	var c_no: int = base + rng.randi_range(0, 31)
	var ps_no: int = base + rng.randi_range(0, 31)
	var body := ""
	var total: int = 0
	for piece: Array in [["maila", a_no], ["mailb", b_no], ["mailc", c_no]]:
		var size: int = MailBank.size_of(str(piece[0]), int(piece[1]))
		total += size
		if size > PIECE_MAX or total > BODY_LEN:
			return {}
		body += MailBank.text(str(piece[0]), int(piece[1]))
	var header: String = MailBank.text("superz", super_no).replace("{name}", str(free.get(0, "")))
	var footer: String = MailBank.text("psz", ps_no)
	for key: Variant in free.keys():
		var tag: String = "{free%d}" % int(key)
		header = header.replace(tag, str(free[key]))
		body = body.replace(tag, str(free[key]))
		footer = footer.replace(tag, str(free[key]))
	var spaces := RegEx.create_from_string(" {2,}")
	return {
		"header": header,
		"body": body.strip_edges(false, true),
		"footer": spaces.sub(footer, " ", true).strip_edges(),
		"present": present,
	}


## `mNpc_SendVtdayMail` (Valentine's Day): every villager of the other sex who has a memory
## of the player writes, best friends (friendship ≥ 80) first. With one player the "fond,
## but someone else is the best friend" letter can't happen. Mail `0x60 + looks × 3 + type`
## with a rare / uncommon furniture or common clothing present (`mNpc_GetEventPresent`).
## Goes straight to the mailbox; stops when it's full.
static func send_valentines(
	residents: TownResidents, book: RelationshipBook, player_female: bool, player: String,
	rng: RandomNumberGenerator, deliver_mailbox: Callable
) -> int:
	var by_type: Array = [[], [], []]
	for id: StringName in residents.resident_ids():
		var villager: VillagerData = VillagerCatalog.get_villager(id)
		if villager == null or villager.personality == null or not book.has_id(id):
			continue
		var bond: Relationship = book.get_or_create(id)
		if not bond.has_memory:
			continue
		var villager_female: bool = TownResidents.looks_sex(int(villager.personality.looks)) == TownResidents.SEX_FEMALE
		if villager_female == player_female:
			continue
		(by_type[EVENT_BEST_FRIEND if bond.friendship >= 80 else EVENT_NOT_FRIEND] as Array).append(villager)
	var sent: int = 0
	for type: int in 3:
		for villager: VillagerData in by_type[type]:
			var mail: MailData = event_mail(villager, type, player, rng)
			if mail == null or not bool(deliver_mailbox.call(mail)):
				return sent
			sent += 1
	return sent


## `mNpc_GetEventMail`.
static func event_mail(villager: VillagerData, type: int, player: String, rng: RandomNumberGenerator) -> MailData:
	if not MailBank.has_bank():
		return null
	var looks: int = int(villager.personality.looks)
	var text: Dictionary = MailBank.letter(0x60 + looks * 3 + type, player, {0: player, 6: villager.display_name})
	var mail := MailData.new()
	mail.header = text["header"]
	mail.body = text["body"]
	mail.footer = text["footer"]
	mail.sender_id = villager.id
	mail.sender_name = villager.display_name
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = player
	mail.paper_type = rng.randi_range(0, MailBank.PAPER_NUM - 1)
	## `priority_table` RARE / UNCOMMON / COMMON; `category_table` furniture, furniture, cloth.
	var pool: Array[StringName] = (
		ShopGoods.category_pool(ItemData.Category.CLOTH) if type == EVENT_NOT_FRIEND
		else ShopGoods.furniture_pool()
	)
	if not pool.is_empty():
		mail.present_item_id = pool[rng.randi_range(0, pool.size() - 1)]
		mail.font = MailData.LetterFont.RECV_PRESENT
	else:
		mail.font = MailData.LetterFont.RECV
	return mail


## `mNpc_GetRemailPresent`: furniture or clothing (`RANDOM(4) & 1`) from the shop pools.
static func reply_present(rng: RandomNumberGenerator) -> StringName:
	var pool: Array[StringName] = (
		ShopGoods.furniture_pool() if (rng.randi_range(0, 3) & 1) == 0
		else ShopGoods.category_pool(ItemData.Category.CLOTH)
	)
	if pool.is_empty():
		return &""
	return pool[rng.randi_range(0, pool.size() - 1)]


## `mNpc_SetRemailFreeString`: FREE0 player, FREE1 the villager, FREE2 another villager,
## FREE3…13 a random word from each table.
static func free_strings(player: String, name: String, other: String, rng: RandomNumberGenerator) -> Dictionary:
	var free := {0: player, 1: name}
	if other != "":
		free[2] = other
	for i: int in FREE_WORDS.size():
		var pick: int = int(rng.randf() * float(FREE_WORD_COUNT[i]))
		free[3 + i] = DialogueCatalog.rom_string(FREE_WORDS[i] + pick)
	return free


## `mNpc_GetOtherAnimalPersonalID(id, 1)`: a random other resident.
static func other_villager(residents: TownResidents, id: StringName, rng: RandomNumberGenerator) -> String:
	var others: Array[StringName] = []
	for other: StringName in residents.resident_ids():
		if other != id:
			others.append(other)
	if others.is_empty():
		return ""
	var v: VillagerData = VillagerCatalog.get_villager(others[rng.randi_range(0, others.size() - 1)])
	return v.display_name if v != null else ""
