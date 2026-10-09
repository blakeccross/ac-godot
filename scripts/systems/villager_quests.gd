class_name VillagerQuests
extends RefCounted

## Villager quests (`m_quest.c`, `ac_quest_manager.c`, the data half of
## `ac_quest_talk_init.c`). Saved with the player.
##
## - Deliveries (`Private_c.deliveries[15]`): one per pocket, the pocket holding the parcel.
## - Errands (`Private_c.errands[5]`): "go pick up what I lent to X", which may chain through up
##   to three villagers before the item goes back to the first one.
## - Contests (`Animal_c.contest_quest`, one per resident slot): bring fruit, a fish, a bug,
##   plant flowers, kick a ball, build a snowman, write a letter.
## A quest is a Dictionary so the talk code can edit it in place:
##   {type, kind, limit_on, progress, give_reward, limit (absolute minute)} plus per-type fields.
## The first job keeps its own errand model (`FirstJob`); its errand kinds aren't stored here.

enum Type { DELIVERY, ERRAND, CONTEST, NONE }

const DELIVERY_NORMAL := 0
const DELIVERY_FOREIGN := 1
const DELIVERY_REMOVE := 2
const DELIVERY_LOST := 3

const ERRAND_REQUEST := 0
const ERRAND_REQUEST_CONTINUE := 1
const ERRAND_REQUEST_FINAL := 2

const ERRAND_TYPE_NONE := 0
const ERRAND_TYPE_CHAIN := 1

const CONTEST_FRUIT := 0
const CONTEST_SOCCER := 1
const CONTEST_SNOWMAN := 2
const CONTEST_FLOWER := 3
const CONTEST_FISH := 4
const CONTEST_INSECT := 5
const CONTEST_LETTER := 6
const CONTEST_KIND_NUM := 7

const DELIVERY_NUM := Inventory.POCKET_SLOTS
const ERRAND_NUM := 5
const CHAIN_ANIMAL_NUM := 3
## `mQst_MAX_TIME_LIMIT_DAYS`.
const MAX_TIME_LIMIT_DAYS := 28
## `aQMgr_FLOWER_GOAL_NUM`.
const FLOWER_GOAL_NUM := 3

## `aQMgr_QUEST_TARGET_*`.
enum Target { RANDOM, RANDOM_EXCLUDED, ORIGINAL_TARGET, FOREIGN, LAST_REMOVE, CLIENT }
## `aQMgr_QUEST_ITEM_*`.
enum ItemSrc { RANDOM, FRUIT, CLOTH, FROM_DATA, CURRENT_ITEM, NONE }
## `aQMgr_QUEST_REWARD_*`.
enum Reward { FTR, STATIONERY, CLOTH, CARPET, WALLPAPER, MONEY, WORN_CLOTH, SEVEN }
## `aQMgr_MSG_KIND_*`: index into a set data's `msgs`.
enum Msg {
	REQUEST_INIT,
	REQUEST_END,
	REQUEST_RECONF,
	REQUEST_REJECT,
	COMPLETE_INIT,
	COMPLETE_END,
	FAILURE_INIT,
	FAILURE_END,
	FULL_ITEM,
	AFTER_REWARD,
	AFTER_REWARD_THANKS,
	REWARD_FULL_ITEM,
	REWARD_FULL_ITEM2,
	NONE,
}

## `l_quest_item_list` (`ITM_QST_*`). Placeholder names until item names come off the disc.
const QUEST_ITEMS: Array[StringName] = [
	&"qst_videotape",
	&"qst_organizer",
	&"qst_virtual_pet",
	&"qst_comic_book",
	&"qst_picture_book",
	&"qst_handheld_game",
	&"qst_camera",
	&"qst_watch",
	&"qst_handkerchief",
	&"qst_glasses_case",
]
const QUEST_ITEM_NAMES: Array[String] = [
	"videotape",
	"organizer",
	"virtual pet",
	"comic book",
	"picture book",
	"handheld game",
	"camera",
	"watch",
	"handkerchief",
	"glasses case",
]

## `l_delivery_limit`, `l_errand_limit`, `l_contest_limit`, `l_contest_fin_limit`.
const DELIVERY_LIMIT: Array[int] = [2, 2, 2, 2]
const ERRAND_LIMIT: Array[int] = [2, 2, 2]
const CONTEST_LIMIT: Array[int] = [1, 1, 1, 3, 3, 3, 2]
const CONTEST_FIN_LIMIT: Array[int] = [3, 3, 3, 3, 3, 3, 2]

## `mQst_LETTER_*` (contest letter rank → reply).
const LETTER_SCORE_BONUS := 3
const LETTER_PRESENT_BONUS := 6
const LETTER_OKAY_LENGTH := 17
const LETTER_GOOD_LENGTH := 49
## `mQst_GetRemailData`: handbill `0x75 + rank × 6 + looks`, festive paper (`ITM_PAPER22`).
const LETTER_REPLY_BASE := 0x75
const LETTER_REPLY_PAPER := 22

## `l_set_delivery_data` / `l_set_errand_data` / `l_set_contest_data` (`aQMgr_set_data_c`):
## [to, day_limit, last_step, handover, item source, reward % ×8, max pay, msg starts ×13].
const SET_DATA: Array = [
	[
		[Target.RANDOM, 2, 0, true, ItemSrc.CLOTH, [40, 0, 0, 0, 0, 30, 30, 0], 200,
			[0x0151, 0x024C, 0x0163, 0x025E, 0x0175, 0x0294, 0x0187, 0x02B8, 0x0440, 0x035E, 0x034C, 0x0370, 0x033A]],
		[Target.FOREIGN, 2, 0, true, ItemSrc.RANDOM, [40, 0, 0, 10, 10, 40, 0, 0], 1000,
			[0x0199, 0x024C, 0x01AB, 0x025E, 0x01BD, 0x0294, 0x01CF, 0x02CA, 0x0440, 0x035E, 0x034C, 0x0370, 0x033A]],
		[Target.LAST_REMOVE, 2, 0, true, ItemSrc.RANDOM, [20, 0, 0, 20, 20, 40, 0, 0], 1000,
			[0x0205, 0x024C, 0x0217, 0x025E, 0x10BF, 0x0294, 0x023A, 0x02CA, 0x0440, 0x035E, 0x034C, 0x0370, 0x033A]],
		[Target.RANDOM, 2, 0, true, ItemSrc.RANDOM, [40, 0, 40, 10, 10, 0, 0, 0], 0,
			[0x0A74, 0x024C, 0x0A86, 0x025E, 0x0A98, 0x0294, 0x0AAA, 0x02B8, 0x0440, 0x035E, 0x034C, 0x0370, 0x033A]],
	],
	[
		[Target.RANDOM_EXCLUDED, 2, 4, false, ItemSrc.RANDOM, [50, 0, 0, 0, 0, 0, 0, 0], 500,
			[0x038C, 0x024C, 0x03D4, 0x025E, 0x03F8, 0x0294, 0x2B73, 0x02CA, 0x0440, 0x035E, 0x034C, 0x0370, 0x033A]],
		[Target.RANDOM_EXCLUDED, 2, 1, false, ItemSrc.CURRENT_ITEM, [50, 0, 0, 0, 0, 0, 0, 0], 500,
			[0x03B0, 0x024C, 0x03E6, 0x025E, 0x03F8, 0x0294, 0x041C, 0x02CA, 0x0440, 0x035E, 0x034C, 0x0370, 0x033A]],
		[Target.ORIGINAL_TARGET, 2, 0, true, ItemSrc.CURRENT_ITEM, [50, 0, 0, 0, 0, 0, 0, 0], 500,
			[0x039E, 0x024C, 0x03C2, 0x025E, 0x03F8, 0x0294, 0x040A, 0x0452, 0x17B8, 0x035E, 0x034C, 0x0370, 0x033A]],
	],
	[
		[Target.CLIENT, 1, 1, false, ItemSrc.FRUIT, [0, 0, 0, 30, 30, 40, 0, 0], 500,
			[0x01E1, 0x0000, 0x01E1, 0x025E, 0x01F3, 0x117C, 0x0000, 0x02CA, 0x0440, 0x035E, 0x034C, 0x0370, 0x033A]],
		[Target.CLIENT, 1, 2, false, ItemSrc.NONE, [40, 0, 0, 30, 30, 0, 0, 0], 0,
			[0x0D79, 0x0000, 0x0D79, 0x025E, 0x0D91, 0x0DD9, 0x0000, 0x02CA, 0x0440, 0x0DFD, 0x0DD9, 0x0DEB, 0x0E0F]],
		[Target.CLIENT, 1, 1, false, ItemSrc.NONE, [60, 0, 0, 20, 20, 0, 0, 0], 0,
			[0x0E33, 0x0000, 0x0E33, 0x025E, 0x0E45, 0x0E8D, 0x0000, 0x02CA, 0x0440, 0x0EB1, 0x0E8D, 0x0E9F, 0x0EC3]],
		[Target.CLIENT, 3, 1, false, ItemSrc.NONE, [60, 0, 0, 20, 20, 0, 0, 0], 0,
			[0x0FB5, 0x0000, 0x0FB5, 0x025E, 0x0FC7, 0x100F, 0x0000, 0x02CA, 0x0440, 0x1033, 0x100F, 0x1021, 0x1045]],
		[Target.CLIENT, 3, 1, false, ItemSrc.NONE, [80, 0, 0, 10, 10, 0, 0, 0], 0,
			[0x158C, 0x0000, 0x158C, 0x025E, 0x159E, 0x15B0, 0x0000, 0x02CA, 0x0440, 0x035E, 0x034C, 0x0370, 0x033A]],
		[Target.CLIENT, 3, 1, false, ItemSrc.NONE, [80, 0, 0, 10, 10, 0, 0, 0], 0,
			[0x160A, 0x0000, 0x160A, 0x025E, 0x161C, 0x162E, 0x0000, 0x02CA, 0x0440, 0x035E, 0x034C, 0x0370, 0x033A]],
		[Target.CLIENT, 2, 2, false, ItemSrc.NONE, [80, 0, 0, 10, 10, 0, 0, 0], 0,
			[0x1AE1, 0x0000, 0x1AE1, 0x025E, 0x1B17, 0x0294, 0x0000, 0x02CA, 0x0440, 0x035E, 0x034C, 0x0370, 0x033A]],
	],
]

## `aQMgr_actor_get_errand_reward`: reward % by how many villagers the chain went through,
## and the pay for each.
const ERRAND_REWARD: Array = [
	[0, 75, 25, 0, 0, 0, 0, 0],
	[25, 25, 25, 0, 0, 25, 0, 0],
	[50, 0, 25, 0, 0, 25, 0, 0],
	[65, 0, 0, 5, 5, 25, 0, 0],
]
const ERRAND_PAY: Array[int] = [0, 500, 750, 1000]
## `aQMgr_actor_get_rate`: {spread, base} per 100 of money power.
const RATE_TABLE: Array = [
	[0.3, 0.0], [0.7, -40.0], [2.7, -440.0], [1.3, -20.0], [1.0, 100.0], [0.6, 300.0], [0.0012, 660.0],
]
const RATE_CAP := 700

var deliveries: Array[Dictionary] = []
var errands: Array[Dictionary] = []
## Resident slot → contest (`Animal_c.contest_quest`); `owner` ties it to who lived there.
var contests: Array[Dictionary] = []


func _init() -> void:
	clear()


func clear() -> void:
	deliveries.clear()
	errands.clear()
	contests.clear()
	for i: int in DELIVERY_NUM:
		var d: Dictionary = {}
		clear_delivery(d)
		deliveries.append(d)
	for i: int in ERRAND_NUM:
		var e: Dictionary = {}
		clear_errand(e)
		errands.append(e)
	for i: int in TownResidents.ANIMAL_NUM_MAX:
		var c: Dictionary = {}
		clear_contest(c)
		contests.append(c)


## `ITM_QST_*`: parcels only ever carried for a villager (`ItemCatalog.ensure_loaded`).
static func register_items() -> void:
	for i: int in QUEST_ITEMS.size():
		var data := ItemData.new()
		data.id = QUEST_ITEMS[i]
		data.display_name = QUEST_ITEM_NAMES[i]
		data.category = ItemData.Category.OTHER
		data.max_stack = 1
		data.droppable = false
		data.usable = false
		data.sell_price = 0
		data.icon_color = Color(0.85, 0.7, 0.45)
		ItemCatalog.remember(data)


## ---------------------------------------------------------------- clear / copy

## `mQst_ClearQuestInfo`.
static func clear_base(q: Dictionary) -> void:
	q["type"] = Type.NONE
	q["kind"] = 0
	q["limit_on"] = false
	q["progress"] = 0
	q["give_reward"] = false
	q["limit"] = 0


static func new_base() -> Dictionary:
	var q: Dictionary = {}
	clear_base(q)
	return q


## `mQst_CopyQuestInfo`.
static func copy_base(dst: Dictionary, src: Dictionary) -> void:
	for key: String in ["type", "kind", "limit_on", "progress", "give_reward", "limit"]:
		dst[key] = src.get(key, 0)


## `mQst_ClearDelivery`.
static func clear_delivery(d: Dictionary) -> void:
	clear_base(d)
	d["to"] = &""
	d["from"] = &""


## `mQst_ClearErrand`.
static func clear_errand(e: Dictionary) -> void:
	clear_base(e)
	e["to"] = &""
	e["from"] = &""
	e["item"] = &""
	e["pocket"] = -1
	e["errand_type"] = ERRAND_TYPE_NONE
	e["used_ids"] = [&"", &"", &""]
	e["used_num"] = 0


## `mQst_ClearContest`.
static func clear_contest(c: Dictionary) -> void:
	clear_base(c)
	c["owner"] = &""
	c["requested"] = &""
	## `player_id`: set once the player took part (one save = one player).
	c["player"] = false
	c["player_name"] = ""
	c["flowers_requested"] = 0
	c["letter_score"] = 0
	c["letter_present"] = &""


static func is_free(q: Dictionary) -> bool:
	return q.is_empty() or int(q.get("type", Type.NONE)) == Type.NONE


## `aQMgr_talk_common_get_set_data_p`.
static func set_data(type: int, kind: int) -> Array:
	if type < 0 or type >= SET_DATA.size():
		return []
	var table: Array = SET_DATA[type]
	if kind < 0 or kind >= table.size():
		return []
	return table[kind]


static func set_msg(data: Array, msg_kind: int) -> int:
	if data.is_empty() or msg_kind < 0 or msg_kind >= Msg.NONE:
		return 0
	return int((data[7] as Array)[msg_kind])


## ---------------------------------------------------------------- limits

## `mQst_CheckLimitOver`: past the deadline, or the clock went back before the quest began.
## (The 28-day check only runs when the deadline is still ahead, where the interval is 0.)
static func limit_over(q: Dictionary, now: int) -> bool:
	if not bool(q.get("limit_on", false)):
		return false
	var limit: int = int(q.get("limit", 0))
	if now >= limit:
		return true
	var type: int = int(q.get("type", Type.NONE))
	var kind: int = int(q.get("kind", 0))
	var days: int = -1
	match type:
		Type.DELIVERY:
			if kind < DELIVERY_LIMIT.size():
				days = DELIVERY_LIMIT[kind]
		Type.ERRAND:
			days = ERRAND_LIMIT[kind] if kind < ERRAND_LIMIT.size() else 0
		Type.CONTEST:
			if kind < CONTEST_LIMIT.size():
				days = CONTEST_LIMIT[kind]
				if int(q.get("progress", 0)) == 0:
					days += CONTEST_FIN_LIMIT[kind]
	if days < 0:
		return false
	return now < limit - days * 1440


## `aQMgr_actor_regist_quest_move` → the contest limit procs (`ac_quest_contest.c_inc`):
## spent or out-of-season contests clear. Run whenever the quest manager would.
func move(now: int, month: int, day: int) -> void:
	for c: Dictionary in contests:
		if is_free(c):
			continue
		var kind: int = int(c["kind"])
		var clear: bool = limit_over(c, now)
		match kind:
			CONTEST_SNOWMAN:
				clear = clear or (month == 2 and day > 17) or (month >= 3 and month <= 11) or (month == 12 and day < 25)
			CONTEST_FLOWER:
				clear = clear or month == 1 or (month == 2 and day < 25) or month >= 9
			CONTEST_INSECT:
				clear = clear or month <= 2 or (month == 11 and day >= 29) or month == 12
		if clear:
			clear_contest(c)


## A slot's resident changed (moved out / in): their contest goes with them.
func sync_residents(residents: TownResidents) -> void:
	if residents == null:
		return
	for i: int in contests.size():
		var c: Dictionary = contests[i]
		if is_free(c):
			continue
		var id: StringName = residents.slots[i].get("id", &"") as StringName if i < residents.slots.size() else &""
		if id == &"" or id != (c.get("owner", &"") as StringName):
			clear_contest(c)


## ---------------------------------------------------------------- lookups

## `mQst_GetOccuredContestIdx`.
func occured_contest_idx(kind: int) -> int:
	for i: int in contests.size():
		var c: Dictionary = contests[i]
		if int(c.get("type", Type.NONE)) == Type.CONTEST and int(c.get("kind", -1)) == kind:
			return i
	return -1


## `mQst_GetOccuredDeliveryIdx`.
func occured_delivery_idx(kind: int) -> int:
	for i: int in deliveries.size():
		var d: Dictionary = deliveries[i]
		if int(d.get("type", Type.NONE)) == Type.DELIVERY and int(d.get("kind", -1)) == kind:
			return i
	return -1


## `aQMgr_actor_init_quest`: every live quest, deliveries then errands then contests, with
## who asked (`from`), who it's for (`to`) and the item. `idx` is the pocket (deliveries),
## errand slot or resident slot.
func registry(inventory: Inventory, residents: TownResidents) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in deliveries.size():
		var d: Dictionary = deliveries[i]
		if int(d.get("type", Type.NONE)) != Type.DELIVERY:
			continue
		var item: StringName = &""
		if inventory != null:
			var s: InventorySlot = inventory.slot_at(i)
			if s != null and not s.is_empty():
				item = s.item.item_id
		out.append({"quest": d, "idx": i, "from": d["from"], "to": d["to"], "item": item})
	for i: int in errands.size():
		var e: Dictionary = errands[i]
		if int(e.get("type", Type.NONE)) != Type.ERRAND or int(e.get("kind", 0)) > ERRAND_REQUEST_FINAL:
			continue
		out.append({"quest": e, "idx": i, "from": e["from"], "to": e["to"], "item": e["item"]})
	for i: int in contests.size():
		var c: Dictionary = contests[i]
		if int(c.get("type", Type.NONE)) != Type.CONTEST or int(c.get("kind", -1)) >= CONTEST_KIND_NUM:
			continue
		var id: StringName = &""
		if residents != null and i < residents.slots.size():
			id = residents.slots[i].get("id", &"") as StringName
		out.append({"quest": c, "idx": i, "from": id, "to": id, "item": c["requested"]})
	return out


## ---------------------------------------------------------------- pockets

## `mQst_GetDeliveryIdxbyItemIdx` / `mQst_GetErrandIdxbyItemIdx`: the quest a pocket's
## QUEST-flagged item belongs to, as {"type", "idx"}, or {}.
func quest_for_pocket(inventory: Inventory, pocket: int) -> Dictionary:
	if pocket < 0 or pocket >= DELIVERY_NUM:
		return {}
	if not is_free(deliveries[pocket]):
		return {"type": Type.DELIVERY, "idx": pocket}
	if inventory == null:
		return {}
	var s: InventorySlot = inventory.slot_at(pocket)
	if s == null or s.is_empty() or s.item.condition != InventoryItem.Condition.QUEST:
		return {}
	for i: int in errands.size():
		var e: Dictionary = errands[i]
		if not is_free(e) and int(e["pocket"]) == pocket and e["item"] == s.item.item_id:
			return {"type": Type.ERRAND, "idx": i}
	return {}


## `mQst_ClearQuestbyPossessionIdx`.
func clear_by_pocket(inventory: Inventory, pocket: int) -> bool:
	var q: Dictionary = quest_for_pocket(inventory, pocket)
	if q.is_empty():
		return false
	if int(q["type"]) == Type.DELIVERY:
		clear_delivery(deliveries[int(q["idx"])])
	else:
		clear_errand(errands[int(q["idx"])])
	return true


## `mQst_CheckLimitbyPossessionIdx`.
func limit_by_pocket(inventory: Inventory, pocket: int, now: int) -> bool:
	if inventory == null or pocket < 0 or pocket >= DELIVERY_NUM:
		return false
	var s: InventorySlot = inventory.slot_at(pocket)
	if s == null or s.is_empty():
		return false
	var d: Dictionary = deliveries[pocket]
	if not is_free(d) and limit_over(d, now):
		return true
	for e: Dictionary in errands:
		if not is_free(e) and int(e["pocket"]) == pocket and e["item"] == s.item.item_id and limit_over(e, now):
			return true
	return false


## `mQst_GetToFromName`: {to, from} villager ids for a quest item's tag.
func to_from_for_pocket(inventory: Inventory, pocket: int) -> Dictionary:
	var q: Dictionary = quest_for_pocket(inventory, pocket)
	if q.is_empty():
		return {}
	var src: Dictionary = deliveries[int(q["idx"])] if int(q["type"]) == Type.DELIVERY else errands[int(q["idx"])]
	return {"to": src["to"], "from": src["from"]}


## ---------------------------------------------------------------- contests

## `mQst_NextSnowman` / `mQst_BackSnowman`: a snowman built (or broken) in the acre of the
## resident who asked for one counts for (or against) the player. `block` is the field acre.
func note_snowman(block: Vector2i, residents: TownResidents, built: bool) -> bool:
	var i: int = occured_contest_idx(CONTEST_SNOWMAN)
	if i < 0 or residents == null:
		return false
	var c: Dictionary = contests[i]
	if int(c.get("progress", 0)) != 1:
		return false
	var home: Vector2i = residents.home_of(i)
	if home == TownResidents.NO_HOME or home / 16 != block:
		return false
	c["player"] = built
	return true


## `mQst_CheckSoccerTarget`: the resident in `slot` asked for the ball and is waiting for it.
func soccer_target(slot: int) -> bool:
	var i: int = occured_contest_idx(CONTEST_SOCCER)
	return i >= 0 and i == slot and int(contests[i].get("progress", 0)) == 2


## `mQst_NextSoccer`: the ball reached them; the reward talk is next.
func next_soccer(slot: int, player_name: String) -> bool:
	if not soccer_target(slot):
		return false
	var c: Dictionary = contests[slot]
	c["progress"] = 1
	c["player"] = true
	c["player_name"] = player_name
	return true


## `mQst_GetMailRank`: longer letters, a good letter and a present all rank higher.
static func letter_rank(body: String, present: StringName) -> int:
	var length: int = LetterCheck._strlen_new(LetterCheck.encode(body), LetterCheck.BODY_LEN)
	var rank: int = 0
	if length >= LETTER_GOOD_LENGTH:
		rank = 2
	elif length >= LETTER_OKAY_LENGTH:
		rank = 1
	if LetterCheck.rank(body) == LetterCheck.Rank.OK:
		rank += LETTER_SCORE_BONUS
	if present != &"":
		rank += LETTER_PRESENT_BONUS
	return rank


## `mQst_SetReceiveLetter`: the letter the villager was waiting for.
func receive_letter(slot: int, body: String, present: StringName, player_name: String, rng: RandomNumberGenerator) -> bool:
	if slot < 0 or slot >= contests.size():
		return false
	var c: Dictionary = contests[slot]
	if int(c.get("type", Type.NONE)) != Type.CONTEST or int(c["kind"]) != CONTEST_LETTER:
		return false
	if bool(c["player"]) or int(c["progress"]) != 2:
		return false
	c["player"] = true
	c["player_name"] = player_name
	c["progress"] = 1
	c["letter_score"] = letter_rank(body, present)
	c["letter_present"] = letter_present(int(c["letter_score"]), rng)
	return true


## `mQst_GetPresent`.
static func letter_present(rank: int, rng: RandomNumberGenerator) -> StringName:
	match rank:
		3, 7:
			return _pick(ShopGoods.category_pool(ItemData.Category.CLOTH), rng)
		4:
			return _pick(ShopGoods.furniture_pool(), rng)
		5:
			return _pick(_carpet_or_wall(rng), rng)
		6:
			return Game.town_fruit if Game != null else &"apple"
		8:
			return _pick(_rare(ItemData.Category.CLOTH), rng)
		9:
			return other_fruit(rng)
		10:
			return _pick(ShopGoods._rare_pool(), rng)
		11:
			var cat: int = ItemData.Category.FLOOR if (rng.randi_range(0, 3) & 1) == 0 else ItemData.Category.WALL
			return _pick(_rare(cat), rng)
	return &""


static func _carpet_or_wall(rng: RandomNumberGenerator) -> Array[StringName]:
	if (rng.randi_range(0, 3) & 1) == 0:
		return ShopGoods.category_pool(ItemData.Category.FLOOR)
	return ShopGoods.category_pool(ItemData.Category.WALL)


static func _rare(category: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for item: ItemData in ItemCatalog.all_items():
		if item is FurnitureData or item.category != category or not item.shop_rare or item.from_disc:
			continue
		out.append(item.id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## `mQst_GetRemailData`: the reply to a contest letter.
static func letter_reply(villager: VillagerData, rank: int, present: StringName, player: String) -> MailData:
	if villager == null or not MailBank.has_bank():
		return null
	var looks: int = int(villager.personality.looks) if villager.personality != null else 0
	var free := {6: villager.display_name}
	var item: ItemData = ItemCatalog.get_item(present)
	if item != null:
		free[0] = item.display_name
	var text: Dictionary = MailBank.letter(LETTER_REPLY_BASE + rank * TownResidents.LOOKS_NUM + looks, player, free)
	var mail := MailData.new()
	mail.header = text["header"]
	mail.body = text["body"]
	mail.footer = text["footer"]
	mail.sender_id = villager.id
	mail.sender_name = villager.display_name
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = player
	mail.paper_type = LETTER_REPLY_PAPER
	mail.present_item_id = present
	mail.font = MailData.LetterFont.RECV
	return mail


## ---------------------------------------------------------------- rewards

## `aQMgr_actor_get_rate` (money power → percent).
static func pay_rate(money_power: int) -> int:
	if money_power <= 0:
		return 0
	var idx: int = mini(money_power / 100, RATE_TABLE.size() - 1)
	var row: Array = RATE_TABLE[idx]
	return int(float(row[1]) + float(row[0]) * float(money_power))


## `aQMgr_actor_get_pay`: the base pay scaled by how rich the player is, ±10 %.
static func pay(base_pay: int, money_power: int, rng: RandomNumberGenerator) -> int:
	var dir: float = [1.0, -1.0][rng.randi_range(0, 1)]
	var scale: float = 100.0 + dir * 10.0 * rng.randf()
	var rate: int = mini(pay_rate(money_power), RATE_CAP)
	var factor: float = (scale * (100.0 + float(rate))) / 10000.0
	return int(float(base_pay) * factor)


## `aQMgr_actor_get_errand_reward`.
static func errand_reward(used_num: int) -> Dictionary:
	var n: int = clampi(used_num - 1, 0, ERRAND_PAY.size() - 1)
	if used_num - 1 < 0:
		## The u8 wraps to 255 and clamps to the last row.
		n = ERRAND_PAY.size() - 1
	return {"percents": ERRAND_REWARD[n], "pay": ERRAND_PAY[n]}


## ---------------------------------------------------------------- goods

## `mFI_GetOtherFruit` (retail build): `RANDOM(4)`, bumped past the town fruit on a hit —
## so the fruit after the town's comes up twice as often, and the fifth only then.
static func other_fruit(rng: RandomNumberGenerator) -> StringName:
	var fruit_idx: int = rng.randi_range(0, 3)
	var town: int = maxi(ShopBook.FRUITS.find(Game.town_fruit if Game != null else &"apple"), 0)
	if fruit_idx == town:
		fruit_idx += 1
	return ShopBook.FRUITS[mini(fruit_idx, ShopBook.FRUITS.size() - 1)]


static func _pick(pool: Array[StringName], rng: RandomNumberGenerator) -> StringName:
	if pool.is_empty():
		return &""
	return pool[rng.randi_range(0, pool.size() - 1)]


## ---------------------------------------------------------------- save

func to_save() -> Dictionary:
	return {
		"deliveries": _rows(deliveries),
		"errands": _rows(errands),
		"contests": _rows(contests),
	}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var bag: Dictionary = data
	_load_rows(bag.get("deliveries", []), deliveries)
	_load_rows(bag.get("errands", []), errands)
	_load_rows(bag.get("contests", []), contests)


static func _rows(list: Array[Dictionary]) -> Array:
	var out: Array = []
	for q: Dictionary in list:
		var row: Dictionary = {}
		for key: Variant in q.keys():
			var v: Variant = q[key]
			if typeof(v) == TYPE_STRING_NAME:
				row[key] = String(v)
			elif typeof(v) == TYPE_ARRAY:
				var arr: Array = []
				for x: Variant in v as Array:
					arr.append(String(x) if typeof(x) == TYPE_STRING_NAME else x)
				row[key] = arr
			else:
				row[key] = v
		out.append(row)
	return out


static func _load_rows(raw: Variant, into: Array[Dictionary]) -> void:
	if typeof(raw) != TYPE_ARRAY:
		return
	var rows: Array = raw
	for i: int in mini(rows.size(), into.size()):
		if typeof(rows[i]) != TYPE_DICTIONARY:
			continue
		var dst: Dictionary = into[i]
		var src: Dictionary = rows[i]
		for key: Variant in dst.keys():
			if not src.has(key):
				continue
			var cur: Variant = dst[key]
			var v: Variant = src[key]
			match typeof(cur):
				TYPE_STRING_NAME:
					dst[key] = StringName(str(v))
				TYPE_BOOL:
					dst[key] = bool(v)
				TYPE_INT:
					dst[key] = int(v)
				TYPE_STRING:
					dst[key] = str(v)
				TYPE_ARRAY:
					var arr: Array = []
					for x: Variant in (v as Array if typeof(v) == TYPE_ARRAY else []):
						arr.append(StringName(str(x)))
					while arr.size() < CHAIN_ANIMAL_NUM:
						arr.append(&"")
					dst[key] = arr
				_:
					dst[key] = v
