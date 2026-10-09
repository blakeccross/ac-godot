class_name DialogueGreeting
extends RefCounted

## Looks + meet-time + weather pick of a starting `msg_no` (`aQMgr_get_hello_msg_no`).
## Jumps into the imported bank when present; otherwise `looks_greeting`.

const KIND := 3
## `MSG_11573`: new-arrival first greeting, 3 variants × 4 times × 6 looks.
const MOVED_IN_HELLO := 11573
## `MSG_11770`: "you gave me this shirt" (the giver is this player).
const THANKS_CLOTH := 11770
const FALLBACK_ID := &"looks_greeting"

const MEET_FIRST := 0
const MEET_AGAIN := 1
const MEET_TODAY := 2
const MEET_LONG := 3
const MEET_REALLY_LONG := 4

const TIME_MORNING := 0
const TIME_DAY := 1
const TIME_EVENING := 2
const TIME_NIGHT := 3

## `l_hello_fine_msg_tbl` / rain / snow (`ac_quest_talk_greeting.c`).
const FINE := [1213, 1357, 1285, 1501, 1645, 1429, 1573, 1717]
const RAIN := [1213, 3099, 3027, 1501, 1645, 1429, 1573, 1717]
const SNOW := [1213, 3243, 3171, 1501, 1645, 1429, 1573, 1717]
const GRAD := [4644, 4788, 4716, 4716, 4716, 4716, 4716, 4716]
const ISLAND_FINE := [13400, 13575, 13551, 13647, 13647, 13647, 13647, 13647]
const ISLAND_KIND := [1, 3, 1, 1, 1, 1, 1, 1]
const ANGRY := [3315, 3320, 3325, 3330, 3335, 3340]
const SAD := [3345, 3350, 3355, 3360, 3365, 3370]
const SLEEPY := [3375, 3380, 3385, 3390, 3395, 3400]
const PITFALL := 8327
## `MSG_10988`: "Bees!" while a swarm chases the player; `MSG_6987`: the swollen face.
const BEE_CHASE := 10988
const BEE_STUNG := 6987
## `aQMgr_get_hello_msg_no_kamakura` / `_summercamp` tables by looks, and the camper's
## first greeting (`MSG_15930`).
const KAMAKURA_HELLO := [6367, 6376, 6358, 6385, 6394, 6403]
const CAMPER_HELLO := [16002, 16032, 16063, 16093, 16123, 16153]
const CAMPER_FIRST := 15930
const GREETING_GAME_BELL_MIN := 3000
## The first hello of the day on Spring Cleaning / April Fools' Day (`MSG_15297` / `MSG_15236`;
## islanders `MSG_15315` / `MSG_15254`): 3 lines a looks.
const SPRING_CLEANING_HELLO := 15297
const APRIL_FOOLS_HELLO := 15236
const ISLAND_SPRING_CLEANING_HELLO := 15315
const ISLAND_APRIL_FOOLS_HELLO := 15254


static func conversation(villager: VillagerData, state: VillagerState, ctx: DialogueContext = null) -> DialogueData:
	var snap: DialogueContext = ctx if ctx != null else DialogueContext.from_game(villager, state)
	_ensure_rng(snap)
	var msg_no: int = hello_msg_no(villager, state, snap)
	if villager != null and Game != null:
		Game.note_bee_greeting(villager.id)
	## A finished fish / insect collection is worth a word — once per villager per collection.
	if snap.mood != VillagerState.Mood.PITFALL and not snap.bee_chase and meet_type(state, snap) != MEET_FIRST:
		var congrats: int = CompleteTalk.try_greeting(_looks(villager), state, snap.rng)
		if congrats >= 0:
			msg_no = congrats
	var imported: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % msg_no))
	if imported != null:
		return imported
	return fallback_conversation()


static func hello_msg_no(villager: VillagerData, state: VillagerState, ctx: DialogueContext) -> int:
	_ensure_rng(ctx)
	var looks: int = _looks(villager)
	var meet: int = meet_type(state, ctx)
	if ctx.guest != &"":
		var guest: int = guest_hello(ctx.guest, looks, meet, ctx)
		if guest >= 0:
			return guest
	if ctx.mood == VillagerState.Mood.PITFALL:
		return _random_looks(PITFALL, looks, KIND, ctx)
	if ctx.bee_chase:
		return _random_looks(BEE_CHASE, looks, KIND, ctx)
	if meet != MEET_FIRST and ctx.bee_stung:
		return msg_offset(BEE_STUNG, looks, ctx.hour, _roll(KIND, ctx), KIND)
	if meet != MEET_FIRST:
		if ctx.mood == VillagerState.Mood.ANGRY:
			return ANGRY[looks] + _roll(5, ctx)
		if ctx.mood == VillagerState.Mood.SAD:
			return SAD[looks] + _roll(5, ctx)
		if ctx.mood == VillagerState.Mood.SLEEPY:
			return SLEEPY[looks] + _roll(5, ctx)
	## `aQMgr_get_thanks_cloth_msg`: wearing the shirt the player mailed — thanks, once.
	if meet != MEET_FIRST and state != null and state.wearing_present_cloth:
		var cloth: ItemData = ItemCatalog.get_item(state.present_cloth)
		ctx.item0 = PoliceTalk.with_article(cloth.display_name) if cloth != null else ""
		state.wearing_present_cloth = false
		state.present_cloth = &""
		return THANKS_CLOTH + looks * 3 + _roll(3, ctx)
	## `aQMgr_get_hello_msg_how_do_you_do`: a villager who moved in (`Animal_c.moved_in`)
	## introduces themself as the new neighbour on first meeting.
	if meet == MEET_FIRST and villager != null and Game != null and Game.residents != null:
		if Game.residents.moved_in(villager.id):
			return msg_offset(MOVED_IN_HELLO, looks, ctx.hour, _roll(KIND, ctx), KIND)
	if meet == MEET_TODAY:
		var holiday: int = holiday_hello(villager != null and villager.islander)
		if holiday >= 0:
			return _random_looks(holiday, looks, KIND, ctx)
	if ctx.mood == VillagerState.Mood.HAPPY:
		return _hello_offset(GRAD[meet], looks, ctx.hour, KIND, ctx)
	if villager != null and villager.islander:
		var kind_count: int = ISLAND_KIND[meet] if meet >= 0 and meet < ISLAND_KIND.size() else 1
		return _hello_offset(ISLAND_FINE[meet], looks, ctx.hour, kind_count, ctx)
	var table: Array = FINE
	match ctx.weather_name():
		"rain":
			table = RAIN
		"snow":
			table = SNOW
	return _hello_offset(int(table[meet]), looks, ctx.hour, KIND, ctx)


## The holiday first-hello base for today, or -1 (`aQMgr_get_hello_msg_npc_feel_normal`).
static func holiday_hello(islander: bool) -> int:
	if Game == null or Game.events == null:
		return -1
	if Game.events.is_active(&"spring_cleaning"):
		return ISLAND_SPRING_CLEANING_HELLO if islander else SPRING_CLEANING_HELLO
	if Game.events.is_active(&"aprilfools_day"):
		return ISLAND_APRIL_FOOLS_HELLO if islander else APRIL_FOOLS_HELLO
	return -1


## `aQMgr_get_hello_msg_no_kamakura` / `_summercamp`: the guest's greeting game. Money (a
## free pocket and 3,000 Bells) and/or goods (furniture, carpet or wallpaper in the pockets)
## pick the line; both → either. First meetings use the usual introductions — the camper,
## a stranger, has its own (`MSG_15930`). -1 falls through to the usual table.
static func guest_hello(guest: StringName, looks: int, meet: int, ctx: DialogueContext) -> int:
	var table: Array = KAMAKURA_HELLO if guest == &"kamakura" else CAMPER_HELLO
	if meet == MEET_FIRST:
		if guest == &"camper":
			return msg_offset(CAMPER_FIRST, looks, ctx.hour, _roll(KIND, ctx), KIND)
		return -1
	var hello_type: int = 0
	var inv: Inventory = ctx.inventory
	if inv != null and inv.has_space(1) and inv.wallet >= GREETING_GAME_BELL_MIN:
		hello_type |= 1
	if inv != null and _has_goods(inv):
		hello_type |= 2
	if hello_type == 3:
		return 1 + int(table[looks]) + _roll(2, ctx)
	return int(table[looks]) + hello_type


## `aQMgr_check_possession_item`: furniture, a carpet or wallpaper (not wrapped / quest).
static func _has_goods(inv: Inventory) -> bool:
	for i: int in Inventory.POCKET_SLOTS:
		var s: InventorySlot = inv.slot_at(i)
		if s == null or s.is_empty() or s.item.condition != InventoryItem.Condition.NORMAL:
			continue
		var data: ItemData = ItemCatalog.get_item(s.item.item_id)
		if data != null and data.category in [ItemData.Category.FURNITURE, ItemData.Category.FLOOR, ItemData.Category.WALL]:
			return true
	return false


static func msg_offset(base_msg: int, looks: int, hour: int, variant: int, kind_count: int = KIND) -> int:
	return base_msg + looks * kind_count * 4 + time_kind(hour) * kind_count + variant


static func meet_type(state: VillagerState, ctx: DialogueContext) -> int:
	if state == null or state.last_spoke_day == "":
		return MEET_FIRST
	if ctx.already_talked:
		return MEET_AGAIN
	var days: int = ctx.days_since_talk
	if days >= 60:
		return MEET_REALLY_LONG
	if days >= 14:
		return MEET_LONG
	return MEET_TODAY


static func time_kind(hour: int) -> int:
	if hour >= 12 and hour < 17:
		return TIME_DAY
	if hour >= 17:
		return TIME_EVENING
	if hour >= 0 and hour < 5:
		return TIME_NIGHT
	return TIME_MORNING


static func fallback_conversation() -> DialogueData:
	var data: DialogueData = DialogueCatalog.conversation(FALLBACK_ID)
	if data != null:
		return data
	return DialogueData.from_dict(
		{
			"id": "looks_greeting",
			"start": "start",
			"nodes": {
				"start": {"type": "line", "text": "Hello!"},
			},
		}
	)


static func bank_available() -> bool:
	return FileAccess.file_exists("res://assets/generated/dialogue/index.json")


static func _hello_offset(base_msg: int, looks: int, hour: int, kind_count: int, ctx: DialogueContext) -> int:
	return msg_offset(base_msg, looks, hour, _roll(kind_count, ctx), kind_count)


static func _random_looks(base_msg: int, looks: int, kind_count: int, ctx: DialogueContext) -> int:
	return base_msg + looks * kind_count + _roll(kind_count, ctx)


static func _looks(villager: VillagerData) -> int:
	if villager != null and villager.personality != null:
		return clampi(int(villager.personality.looks), 0, 5)
	return int(VillagerPersonality.Looks.LAZY)


static func _roll(kind_count: int, ctx: DialogueContext) -> int:
	if kind_count <= 1:
		return 0
	return ctx.rng.randi_range(0, kind_count - 1)


static func _ensure_rng(ctx: DialogueContext) -> void:
	if ctx == null:
		return
	if ctx.rng == null:
		ctx.rng = RandomNumberGenerator.new()
		ctx.rng.randomize()
