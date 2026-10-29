class_name PresentVisit
extends RefCounted

## Someone waiting outside the house with a present when a game is continued from it
## (`ac_present_demo`, `ac_present_npc`, decided in `aNPS2_make_door_data`). In order:
##
## - **Birthday**: on the player's birthday, once a year, with a free pocket, the villager
##   who likes the player most (`aNPS2_decide_birthday_npc`) brings a wrapped Famicom
##   (`FTR_FAMICOM_COMMON02`, "Donkey Kong"). Message 0x319F + looks × 6 + rand(3).
## - otherwise Mr. Resetti, if the last session wasn't saved;
## - otherwise nobody while Tortimer is away on vacation (`mSC_LightHouse_travel_check`);
## - otherwise, once he is back from it (`mSC_LightHouse_Event_Check`), Tortimer about the
##   lighthouse job: every night lit, a souvenir from the trip (wrapped; the lighthouse model
##   in January, the flag in February) with 0x33FD / 0x3414, or "come back when you've
##   room" (0x33FF / 0x3416, and he comes again); a night missed, a scolding and no present
##   (0x3400 / 0x3417). Either way the job is closed (`mSC_LightHouse_Event_Clear`);
## - otherwise, with a free pocket, Tortimer brings the Golden Rod once every fish is caught
##   or the Golden Net once every insect is. The first in town of each gets 0x31C3 / 0x31C5;
##   after that (`Save_Get(first_present)`, town-wide) it's 0x31C7 / 0x31C9, "someone else in
##   town already has one". Each comes once (`mSC_TROPHY_GOLDEN_ROD` / `_NET` in Tortimer's
##   trophy record), set only once Tortimer has gone (`aPRD_retire_npc_wait`).
##
## The visitor stands a few steps in front of the door facing the player, speaks on its own,
## hands the present over when the message says so (`mDemo_ORDER_NPC0` slot 1 = 2), then
## turns and runs off while the player waits.
##
## Birthday cards (`mNpc_SendEventBirthdayCard2`) go out once the birthday has passed since
## the last renewal: every villager who remembers the player (but the one bringing the
## present) mails 0xEA + looks × 3 + rand(3) with furniture, clothing (`RARE` list) or an
## umbrella (`mNpc_GetBirthdayPresent`).

enum Kind { NONE, BIRTHDAY, GOLDEN_ROD, GOLDEN_NET, LIGHTHOUSE_CONTRIBUTED, LIGHTHOUSE_STARTED }

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
const MSG_ROD_AGAIN := 0x31C7
const MSG_NET_AGAIN := 0x31C9
## `aPRD_TYPE_SONCHO_VACATION0/1_*` (January / February): given, no room, a night missed.
const MSG_LIGHTHOUSE_JAN := 0x33FD
const MSG_LIGHTHOUSE_JAN_FULL := 0x33FF
const MSG_LIGHTHOUSE_JAN_MISSED := 0x3400
const MSG_LIGHTHOUSE_FEB := 0x3414
const MSG_LIGHTHOUSE_FEB_FULL := 0x3416
const MSG_LIGHTHOUSE_FEB_MISSED := 0x3417
## `aPST_PRESENT_TYPE_GOLDEN_ROD` / `_NET` bits of `first_present`.
const FIRST_ROD := 1 << 0
const FIRST_NET := 1 << 1
const MAIL_BIRTHDAY := 0xEA
## `aPST_schedule_init_proc`: (2180, 1540) against the door at (2128, 1488), facing back.
const STAND := 73.5 * FieldCatalog.GX_TO_METERS
## `category_table`: furniture, furniture, clothing, clothing, umbrella.
const CARD_KINDS: Array[int] = [0, 0, 1, 1, 2]


## `aNPS2_make_door_data` (home exit) with `aPRD_setup_present`. `away` is
## `mSC_LightHouse_travel_check`, `lighthouse` a `LighthouseBook.Outcome`.
static func decide(
	month: int, day: int, year: int, birthday: Vector2i, celebrated_year: int, has_friend: bool,
	reset: bool, has_space: bool, all_fish: bool, rod_got: bool, all_insects: bool, net_got: bool,
	away: bool = false, lighthouse: int = LighthouseBook.Outcome.NONE
) -> int:
	if (birthday.x == month and birthday.y == day and celebrated_year != year
			and has_space and has_friend):
		return Kind.BIRTHDAY
	if reset or away:
		return Kind.NONE
	match lighthouse:
		LighthouseBook.Outcome.CONTRIBUTED:
			return Kind.LIGHTHOUSE_CONTRIBUTED
		LighthouseBook.Outcome.STARTED:
			return Kind.LIGHTHOUSE_STARTED
	if not has_space:
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


## `aPST_check_first_present`: true the first time anyone in town is given `bit`, which it
## then marks.
static func check_first_present(bit: int) -> bool:
	if Game == null or Game.events == null:
		return true
	var area: Dictionary = Game.events.area(&"present_npc")
	var bits: int = int(area.get("first_present", 0))
	if bits & bit != 0:
		return false
	area["first_present"] = bits | bit
	return true


## `aPRD_retire_npc_wait`: the golden rod / net trophy, once Tortimer has gone.
static func retire(kind: int) -> void:
	match kind:
		Kind.GOLDEN_ROD:
			set_trophy(TROPHY_ROD)
		Kind.GOLDEN_NET:
			set_trophy(TROPHY_NET)


## The visit for the game being continued now. Sets the year it was celebrated.
static func decide_now() -> int:
	if Game == null or Game.inventory == null:
		return Kind.NONE
	var bd: Vector2i = VillagerTalkManager.birthday()
	var friend: StringName = birthday_npc(Game.residents, Game.relationships)
	var today: int = EventDates.ordinal(Clock.year, Clock.month, Clock.day)
	var kind: int = decide(
		Clock.month, Clock.day, Clock.year, bd, Game.resident.celebrated_birthday_year, friend != &"",
		Game.reset_flag, Game.inventory.has_space(1),
		CompleteTalk.collection_complete(CompleteTalk.FISH), has_trophy(TROPHY_ROD),
		CompleteTalk.collection_complete(CompleteTalk.INSECT), has_trophy(TROPHY_NET),
		Game.lighthouse.in_nights(Clock.year, Clock.month, Clock.day),
		LighthouseBook.Outcome.NONE if Game.foreigner else Game.lighthouse.event_check(today)
	)
	if kind == Kind.BIRTHDAY:
		Game.resident.birthday_present_npc = friend
		Game.resident.celebrated_birthday_year = Clock.year
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
			return FurnitureCatalog.item_id(BIRTHDAY_FTR)
		Kind.GOLDEN_ROD:
			return GOLDEN_ROD
		Kind.GOLDEN_NET:
			return GOLDEN_NET
		Kind.LIGHTHOUSE_CONTRIBUTED:
			return Game.lighthouse.present_item() if Game != null else &""
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
				return MSG_ROD if PresentVisit.check_first_present(FIRST_ROD) else MSG_ROD_AGAIN
			Kind.GOLDEN_NET:
				return MSG_NET if PresentVisit.check_first_present(FIRST_NET) else MSG_NET_AGAIN
			Kind.LIGHTHOUSE_CONTRIBUTED:
				var jan: bool = Game == null or Game.lighthouse.start_month == 1
				if inventory == null or not inventory.has_space(1):
					present = &""
					return MSG_LIGHTHOUSE_JAN_FULL if jan else MSG_LIGHTHOUSE_FEB_FULL
				Game.lighthouse.event_clear()
				return MSG_LIGHTHOUSE_JAN if jan else MSG_LIGHTHOUSE_FEB
			Kind.LIGHTHOUSE_STARTED:
				var started_jan: bool = Game == null or Game.lighthouse.start_month == 1
				if Game != null:
					Game.lighthouse.event_clear()
				return MSG_LIGHTHOUSE_JAN_MISSED if started_jan else MSG_LIGHTHOUSE_FEB_MISSED
		return -1

	## The souvenir's name for "It's {item0}" (`aPST_present_send_start_wait_talk_proc`).
	func prepare() -> void:
		if kind == Kind.LIGHTHOUSE_CONTRIBUTED and present != &"":
			var data: ItemData = ItemCatalog.get_item(present)
			context.set_item_str(0, PoliceTalk.with_article(data.display_name) if data != null else "")

	## `aPST_present_send_start_wait_talk_proc`: all but the golden tools come wrapped.
	func lock_continue() -> Dictionary:
		if given or present == &"" or order_value("npc0", 1) != 2:
			return {}
		given = true
		var data: ItemData = ItemCatalog.get_item(present)
		var golden: bool = kind == Kind.GOLDEN_ROD or kind == Kind.GOLDEN_NET
		if data != null and inventory != null:
			inventory.add(data, 1, InventoryItem.Condition.NORMAL if golden else InventoryItem.Condition.PRESENT)
		return {"anim": {"give": present}}
