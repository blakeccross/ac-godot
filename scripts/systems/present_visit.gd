class_name PresentVisit
extends RefCounted

## Someone waiting outside the house with a present when a game is continued from it
## (`ac_present_demo`, `ac_present_npc`, decided in `aNPS2_make_door_data`). In order:
##
## - **Birthday**: on the player's birthday, once a year, with a free pocket, the villager
##   who likes the player most (`aNPS2_decide_birthday_npc`) brings a wrapped Famicom
##   (`FTR_FAMICOM_COMMON02`, "Donkey Kong"). Message 0x319F + looks × 6 + rand(3).
## - otherwise Mr. Resetti, if the last session wasn't saved;
## - otherwise, with a free pocket, Tortimer brings the Golden Rod once every fish is caught
##   (0x31C3) or the Golden Net once every insect is (0x31C5). Each comes once
##   (`mSC_TROPHY_GOLDEN_ROD` / `_NET` in Tortimer's trophy record).
##
## The visitor stands a few steps in front of the door facing the player, speaks on its own,
## hands the present over when the message says so (`mDemo_ORDER_NPC0` slot 1 = 2), then
## turns and runs off.
##
## Birthday cards (`mNpc_SendEventBirthdayCard2`) go out once the birthday has passed since
## the last renewal: every villager who remembers the player (but the one bringing the
## present) mails 0xEA + looks × 3 + rand(3) with furniture, clothing (`RARE` list) or an
## umbrella (`mNpc_GetBirthdayPresent`).

enum Kind { NONE, BIRTHDAY, GOLDEN_ROD, GOLDEN_NET }

## `FTR_FAMICOM_COMMON02`.
const BIRTHDAY_FTR := 876
const GOLDEN_ROD := &"golden_fishing_rod"
const GOLDEN_NET := &"golden_net"
## `mSC_TROPHY_GOLDEN_NET` / `_ROD` in `soncho_record.trophies`.
const TROPHY_NET := 28
const TROPHY_ROD := 31
const MSG_BIRTHDAY := 0x319F
const MSG_ROD := 0x31C3
const MSG_NET := 0x31C5
const MAIL_BIRTHDAY := 0xEA
## `aPST_schedule_init_proc`: (2180, 1540) against the door at (2128, 1488), facing back.
const STAND_GX := 73.5
## `category_table`: furniture, furniture, clothing, clothing, umbrella.
const CARD_KINDS: Array[int] = [0, 0, 1, 1, 2]


## `aNPS2_make_door_data` (home exit) with `aPRD_setup_present`.
static func decide(
	month: int, day: int, year: int, birthday: Vector2i, celebrated_year: int, has_friend: bool,
	reset: bool, has_space: bool, all_fish: bool, rod_got: bool, all_insects: bool, net_got: bool
) -> int:
	if (birthday.x == month and birthday.y == day and celebrated_year != year
			and has_space and has_friend):
		return Kind.BIRTHDAY
	if reset or not has_space:
		return Kind.NONE
	if all_fish and not rod_got:
		return Kind.GOLDEN_ROD
	if all_insects and not net_got:
		return Kind.GOLDEN_NET
	return Kind.NONE


static func record() -> Dictionary:
	return Game.events.area(&"soncho_record") if Game != null and Game.events != null else {}


static func has_trophy(trophy: int) -> bool:
	return (record().get("trophies", {}) as Dictionary).has(str(trophy))


static func set_trophy(trophy: int) -> void:
	var rec: Dictionary = record()
	var trophies: Dictionary = rec.get("trophies", {})
	trophies[str(trophy)] = true
	rec["trophies"] = trophies


## The visit for the game being continued now. Sets the year it was celebrated.
static func decide_now() -> int:
	if Game == null or Game.inventory == null:
		return Kind.NONE
	var bd: Vector2i = VillagerTalkManager.birthday()
	var friend: StringName = birthday_npc(Game.residents, Game.relationships)
	var kind: int = decide(
		Clock.month, Clock.day, Clock.year, bd, Game.celebrated_birthday_year, friend != &"",
		Game.reset_flag, Game.inventory.has_space(1),
		CompleteTalk.collection_complete(CompleteTalk.FISH), has_trophy(TROPHY_ROD),
		CompleteTalk.collection_complete(CompleteTalk.INSECT), has_trophy(TROPHY_NET)
	)
	if kind == Kind.BIRTHDAY:
		Game.birthday_present_npc = friend
		Game.celebrated_birthday_year = Clock.year
	return kind


## `aNPS2_decide_birthday_npc`: the resident with the most friendship who remembers the
## player; `&""` when nobody does.
static func birthday_npc(residents: TownResidents, book: RelationshipBook) -> StringName:
	if residents == null or book == null:
		return &""
	var best: StringName = &""
	var best_friendship: int = -1
	for id: StringName in residents.resident_ids():
		if not book.has_id(id):
			continue
		var bond: Relationship = book.get_or_create(id)
		if bond.has_memory and bond.friendship > best_friendship:
			best_friendship = bond.friendship
			best = id
	return best


static func present_for(kind: int) -> StringName:
	match kind:
		Kind.BIRTHDAY:
			return FtrCatalog.item_id(BIRTHDAY_FTR)
		Kind.GOLDEN_ROD:
			return GOLDEN_ROD
		Kind.GOLDEN_NET:
			return GOLDEN_NET
	return &""


## Whether `birthday` (month, day) fell after day `last` and on or before `today` (both
## `EventDates.ordinal`), the way `check_past_day` compares the last play date.
static func birthday_passed(birthday: Vector2i, last: int, today: int) -> bool:
	if birthday.x < 1 or birthday.x > 12 or last <= 0 or today <= last:
		return false
	var now: Vector3i = EventDates.from_ordinal(today)
	for year: int in [now.x, now.x - 1]:
		var d: int = mini(birthday.y, EventDates.days_in_month(year, birthday.x))
		var n: int = EventDates.ordinal(year, birthday.x, d)
		if n > last and n <= today:
			return true
	return false


## `mNpc_GetBirthdayPresent`.
static func card_present(rng: RandomNumberGenerator) -> StringName:
	var picks: Array[StringName] = []
	match CARD_KINDS[rng.randi_range(0, CARD_KINDS.size() - 1)]:
		0:
			picks = ShopGoods.select("ftr", 1, ShopGoods.Tier.RARE, 0, rng)
		1:
			picks = ShopGoods.select("cloth", 1, ShopGoods.Tier.RARE, 0, rng)
		_:
			var umbrellas: Array[StringName] = ShopGoods.umbrella_pool()
			if not umbrellas.is_empty():
				picks.append(umbrellas[rng.randi_range(0, umbrellas.size() - 1)])
	return picks[0] if not picks.is_empty() else &""


## `mNpc_GetBirthdayCard`.
static func card(villager: VillagerData, player: String, rng: RandomNumberGenerator) -> MailData:
	if villager == null or villager.personality == null or not MailBank.has_bank():
		return null
	var looks: int = int(villager.personality.looks)
	var present: StringName = card_present(rng)
	var data: ItemData = ItemCatalog.get_item(present)
	var text: Dictionary = MailBank.letter(
		MAIL_BIRTHDAY + looks * 3 + rng.randi_range(0, 2), player,
		{0: player, 1: villager.display_name, 2: data.display_name if data != null else ""}
	)
	var mail := MailData.new()
	mail.header = text["header"]
	mail.body = str(text["body"]).replace("{cutart}", "")
	mail.footer = text["footer"]
	mail.sender_id = villager.id
	mail.sender_name = villager.display_name
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = player
	mail.paper_type = rng.randi_range(0, MailBank.PAPER_NUM - 1)
	mail.present_item_id = present
	mail.font = MailData.LetterFont.RECV_PRESENT if present != &"" else MailData.LetterFont.RECV
	return mail


## `mNpc_SendEventBirthdayCard2`: a card from everyone who remembers the player, but
## `skip`. `deliver` takes the letter and says whether it found room. Returns how many went.
static func send_cards(
	residents: TownResidents, book: RelationshipBook, skip: StringName, player: String,
	rng: RandomNumberGenerator, deliver: Callable
) -> int:
	var sent: int = 0
	for id: StringName in residents.resident_ids():
		if id == skip or not book.has_id(id) or not book.get_or_create(id).has_memory:
			continue
		var mail: MailData = card(VillagerCatalog.get_villager(id), player, rng)
		if mail != null and bool(deliver.call(mail)):
			sent += 1
	return sent


## The talk: speaks first, hands the present over on the order, then the rest of the message.
class Talk extends BankTalk:
	var kind: int = Kind.NONE
	var looks: int = 0
	var present: StringName = &""
	var given: bool = false
	var rng: RandomNumberGenerator
	var inventory: Inventory

	func _init(p_kind: int, p_looks: int, p_rng: RandomNumberGenerator) -> void:
		kind = p_kind
		looks = p_looks
		present = PresentVisit.present_for(kind)
		rng = p_rng
		inventory = Game.inventory if Game != null else null

	## `aPST_set_talk_info`.
	func start_msg() -> int:
		match kind:
			Kind.BIRTHDAY:
				return MSG_BIRTHDAY + looks * 6 + rng.randi_range(0, 2)
			Kind.GOLDEN_ROD:
				return MSG_ROD
			Kind.GOLDEN_NET:
				return MSG_NET
		return -1

	## `aPST_present_send_start_wait_talk_proc`: a birthday present comes wrapped.
	func lock_continue() -> Dictionary:
		if given or present == &"" or order_value("npc0", 1) != 2:
			return {}
		given = true
		var data: ItemData = ItemCatalog.get_item(present)
		if data != null and inventory != null:
			inventory.add(data, 1,
				InventoryItem.Condition.PRESENT if kind == Kind.BIRTHDAY else InventoryItem.Condition.NORMAL)
		match kind:
			Kind.GOLDEN_ROD:
				PresentVisit.set_trophy(TROPHY_ROD)
			Kind.GOLDEN_NET:
				PresentVisit.set_trophy(TROPHY_NET)
		return {"anim": {"give": present}}
