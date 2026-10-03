class_name FishRecord
extends RefCounted

## The fishing tourney's records (`m_fishrecord.c`): up to five, one per tourney day, each
## the holder's name, whether that is the player, the size in inches and when it was set
## (`mEv_fishRecord_set`). Villagers keep fishing after the player has gone: once the day is
## over, every half hour from the record's time to 17:50 a villager lands a bass sized by the
## hour (`mFR_make_NpcRecord`), and the biggest of them takes the record if it beats the
## player's (`mEv_fishRecord_local`). A player who still holds it is mailed Chip's letter
## (0x23E + the week of the month) with a piece of lottery or event furniture they don't own
## (`mSP_SelectFishginPresent`) on deep-sea paper; the community board posts the winner
## (`mEv_fishRecord_holder`, handbill 0x242), a villager when nobody from town took part.
##
## The original rolls the villagers twice (for the notice and again for the mail), so the
## two could disagree; here a record is settled once and both use the result.

const MAX := 5
const END_HOUR := 18
## `l_record_time`: the last roll is at 17:50.
const LAST_ROLL := 17 * 60 + 50
const ROLL_STEP := 30
const MAIL_FIRST := 0x23E
const NOTICE := 0x242
## `paper_type = 15`, the deep-sea paper.
const PAPER := 15


## `mEv_fishday_day`: a Sunday in June or November.
static func is_tourney_day(year: int, month: int, day: int) -> bool:
	return (month == 6 or month == 11) and EventDates.weekday(year, month, day) == 0


## `mFR_make_NpcRecord`.
static func npc_size(hour: int, rng: RandomNumberGenerator) -> int:
	var rank: int = AnglerTalk.Size.SMALL
	if hour >= 15:
		rank = rng.randi_range(0, 2)
	elif hour >= 9:
		rank = rng.randi_range(0, 1)
	return AnglerTalk.fish_size(rank, rng.randf())


static func _find(records: Array, ordinal: int) -> Dictionary:
	for r: Dictionary in records:
		if int(r.get("ordinal", 0)) == ordinal:
			return r
	return {}


## `mEv_fishRecord_set` (with `mFR_new_record`): a new day drops records dated after it and
## villagers' records from other days, then takes a free slot or the oldest.
static func set_record(records: Array, name: String, player: bool, size: int, ordinal: int, minute: int) -> void:
	var rec: Dictionary = _find(records, ordinal)
	if rec.is_empty():
		for i: int in range(records.size() - 1, -1, -1):
			var r: Dictionary = records[i]
			if int(r["ordinal"]) > ordinal or not bool(r.get("player", false)):
				records.remove_at(i)
		if records.size() >= MAX:
			var oldest: int = 0
			for i: int in records.size():
				if int(records[i]["ordinal"]) < int(records[oldest]["ordinal"]):
					oldest = i
			records.remove_at(oldest)
		records.append(rec)
	rec.merge({"name": name, "player": player, "size": size, "ordinal": ordinal, "minute": minute,
		"settled": false}, true)


## `mEv_fishRecord_local`: the villagers' best from `minute` to 17:50 against `size`.
## Returns the beating size, or 0.
static func npc_best(minute: int, size: int, rng: RandomNumberGenerator) -> int:
	var best: int = 0
	var t: int = minute
	while t < LAST_ROLL:
		best = maxi(best, npc_size(t / 60, rng))
		t += ROLL_STEP
	return best if best > size else 0


static func _npc_name(names: Array, rng: RandomNumberGenerator) -> String:
	return str(names[rng.randi_range(0, names.size() - 1)]) if not names.is_empty() else "Someone"


## The record after the day's last villager rolls, settled once.
static func settle(rec: Dictionary, names: Array, rng: RandomNumberGenerator) -> void:
	if bool(rec.get("settled", false)):
		return
	var beaten: int = npc_best(int(rec.get("minute", 6 * 60)), int(rec.get("size", 0)), rng)
	if beaten > 0:
		rec["name"] = _npc_name(names, rng)
		rec["player"] = false
		rec["size"] = beaten
	rec["minute"] = END_HOUR * 60
	rec["settled"] = true


## `mEv_fishRecord_holder`: {name, size} who won on `ordinal`; a villager from 6:00 when
## nobody set a record.
static func holder(records: Array, ordinal: int, names: Array, rng: RandomNumberGenerator) -> Dictionary:
	var rec: Dictionary = _find(records, ordinal)
	if rec.is_empty():
		return {"name": _npc_name(names, rng), "size": npc_best(6 * 60, 0, rng)}
	settle(rec, names, rng)
	return {"name": str(rec["name"]), "size": int(rec["size"])}


## Whether the tourney day of `rec` has ended by `ordinal`/`hour`.
static func over(rec: Dictionary, ordinal: int, hour: int) -> bool:
	var day: int = int(rec.get("ordinal", 0))
	return ordinal > day or (ordinal == day and hour >= END_HOUR)


## `mSP_SelectFishginPresent`: lottery or event furniture, whichever list comes up first
## with something not owned, else anything from them.
static func present(owned: Array, rng: RandomNumberGenerator) -> StringName:
	var lists: Array = [FtrCatalog.list("lottery"), FtrCatalog.list("event")]
	if rng.randf() < 0.5:
		lists.reverse()
	for pool: Array in lists:
		var fresh: Array = pool.filter(func(id: StringName) -> bool: return not owned.has(id))
		if not fresh.is_empty():
			return fresh[rng.randi_range(0, fresh.size() - 1)]
	var all: Array = lists[0] + lists[1]
	return all[rng.randi_range(0, all.size() - 1)] if not all.is_empty() else &""


## `mFR_GetFishPresentMail`.
static func prize_mail(rec: Dictionary, prize: StringName, player: String) -> MailData:
	if not MailBank.has_bank():
		return null
	var date: Vector3i = EventDates.from_ordinal(int(rec["ordinal"]))
	var data: ItemData = ItemCatalog.get_item(prize)
	var text: Dictionary = MailBank.letter(MAIL_FIRST + (((date.z - 1) / 7) & 3), player,
		{0: data.display_name if data != null else ""})
	var mail := MailData.new()
	mail.header = text["header"]
	mail.body = str(text["body"]).replace("{cutart}", "")
	mail.footer = text["footer"]
	mail.sender_id = &"chip"
	mail.sender_name = "Chip"
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = player
	mail.paper_type = PAPER
	mail.present_item_id = prize if data != null else &""
	mail.font = MailData.LetterFont.RECV_PRESENT if data != null else MailData.LetterFont.RECV
	return mail


## `mFR_fishmail`: settles the finished days, mails the player's wins (kept until a letter
## gets through) and forgets the villagers'. Returns how many letters went.
static func send_mail(
	records: Array, ordinal: int, hour: int, names: Array, owned: Array, player: String,
	rng: RandomNumberGenerator, deliver: Callable
) -> int:
	var sent: int = 0
	for i: int in range(records.size() - 1, -1, -1):
		var rec: Dictionary = records[i]
		if int(rec["ordinal"]) > ordinal:
			records.remove_at(i)
			continue
		if not over(rec, ordinal, hour):
			continue
		settle(rec, names, rng)
		if not bool(rec["player"]):
			records.remove_at(i)
			continue
		var mail: MailData = prize_mail(rec, present(owned, rng), player)
		if mail != null and bool(deliver.call(mail)):
			records.remove_at(i)
			sent += 1
	return sent


## `mNtc_set_auto_nwrite_fishing_string` + handbill 0x242.
static func notice_text(year: int, month: int, day: int, winner: Dictionary) -> String:
	var text: String = MailBank.text("mail", NOTICE)
	var slots: Dictionary = {
		0: DialogueCatalog.rom_string(NoticeBoard.STRING_MONTH_START + month - 1),
		1: DialogueCatalog.rom_string(NoticeBoard.STRING_DAY_START + day - 1),
		2: str(winner.get("name", "")), 3: str(int(winner.get("size", 0))),
	}
	for key: Variant in slots:
		text = text.replace("{free%d}" % int(key), str(slots[key]))
	return text
