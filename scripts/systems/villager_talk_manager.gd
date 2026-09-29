class_name VillagerTalkManager
extends BankTalk

## What a villager says after the greeting (`ac_quest_manager.c`, `ac_quest_talk_init.c`,
## `ac_quest_talk_normal_init.c`). `DialogueRunner` asks `next_step` when a message ends on
## `MSGCONTINUE`, `choose` when the player picks from a menu this class put up, and `order`
## for every quest demo order a message carries during everyday chat.
##
## The quest talk (`aQMgr_actor_move_talk_init`) runs first: `_select_talk` looks at the
## player's deliveries / errands and this villager's contest (`VillagerQuests`) and picks the
## step — a reward still owed, a finished quest, a reminder, a give-up, a new request, or
## "Nothing much going on". Choosing "Let's talk!" switches to everyday chat
## (`aQMgr_talk_normal_select_talk`).
## A step returns `{}` to end the talk, or `{"msg": msg_no, "choices": [labels]}`, optionally
## with `"hand": {pocket, mode}` (open the pockets; answer with `hand_result`) or
## `"anim": {"give"|"take": item}` (the hand-over plays before the message).

const SELECT_TALK_MSG := 0x2A6
const NO_WORK_MSG := 0x282
const CANCEL_MSG := 0x254A
## `aQMgr_talk_quest_select_get_choice` default: random pick inside each select group.
const CHOICE_HELP := 0x7F
const CHOICE_TALK := 0x89
const CHOICE_NEVERMIND := 0x16A

## `l_*_prob` tables.
const KI_PROB: Array[int] = [40, 30, 10, 10, 10]
const NORMAL_1_PROB: Array[int] = [70, 30]
const GAME_PROB: Array[int] = [40, 60]
const EV_PROB: Array[int] = [50, 50]
const NORMAL_2_PROB: Array[int] = [15, 35, 35, 15]
const TRADE_PROB: Array[int] = [25, 25, 25, 25]
const NORMAL_3_PROB: Array[int] = [49, 17, 17, 17]

## Per-looks message bases (`l_ki_normal` … `l_normal3_season`).
const KI_NORMAL: Array[int] = [0x20C3, 0x2099, 0x25B0, 0x257E, 0x29F0, 0x0F8C]
const KI_WEATHER_TIME: Array[int] = [0x1FE8, 0x1DD0, 0x25DF, 0x2621, 0x2A6A, 0x0F60]
const KI_FREE_ITEM: Array[int] = [0x1396, 0x1CBE, 0x2020, 0x202D, 0x2947, 0x0B36]
const KI_FTR: Array[int] = [0x13C7, 0x1CC9, 0x2049, 0x205D, 0x2974, 0x0B49]
const KI_FREE_ITEM_MONEY: Array[int] = [0x13DE, 0x1CF9, 0x2134, 0x203A, 0x295A, 0x0B5D]
const EV_SPECIAL: Array[int] = [0x11D9, 0x14E2, 0x1885, 0x211C, 0x273A, 0x0D61]
const EV_CAL: Array[int] = [0x118E, 0x17ED, 0x27B2, 0x2806, 0x26EE, 0x0B87]
const GAME_HINT: Array[int] = [0x11F1, 0x14FA, 0x2005, 0x2014, 0x2858, 0x0FAB]
const REMOVE_YES: Array[int] = [0x11FB, 0x1504, 0x1CD5, 0x1CDF, 0x2862, 0x0FA5]
const NORMAL2_LETTER: Array[int] = [0x136C, 0x1BEB, 0x189D, 0x1C5F, 0x2919, 0x0A12]
const NORMAL2_MEMORY: Array[int] = [0x1386, 0x1C78, 0x18B6, 0x1CE9, 0x2933, 0x0D4D]
const TRADE_FREE_ITEM: Array[int] = [0x1205, 0x150C, 0x1772, 0x1C88, 0x2868, 0x0AD7]
const TRADE_FTR: Array[int] = [0x1311, 0x1839, 0x17CA, 0x1CA5, 0x28C9, 0x0ABC]
const TRADE_ITEM: Array[int] = [0x12FC, 0x1BA8, 0x1868, 0x2390, 0x2903, 0x0B03]
const TRADE_FREE_ITEM_MONEY: Array[int] = [0x134B, 0x1BBD, 0x184E, 0x236F, 0x28E4, 0x0B19]
const NORMAL3_NORMAL: Array[int] = [0x1526, 0x169A, 0x16BD, 0x16DF, 0x16F9, 0x0EE7]
const NORMAL3_WEATHER_TIME: Array[int] = [0x13A6, 0x1D08, 0x1F81, 0x1FA0, 0x2A9A, 0x0F00]
const NORMAL3_WEATHER: Array[int] = [0x1FC1, 0x1D29, 0x206C, 0x20AA, 0x2A38, 0x0F2C]
const NORMAL3_SEASON: Array[int] = [0x1FD7, 0x1D41, 0x1F55, 0x1F6B, 0x2A13, 0x0F4A]
const SEASON_ADD: Array[int] = [10, 11, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
## `event_rumor_table[]` order: the rumour's index is its message offset.
const RUMOR_TABLE: Array[StringName] = [
	&"rumor_new_years_day", &"rumor_kamakura", &"rumor_valentines_day", &"rumor_groundhog_day",
	&"rumor_aprilfools_day", &"rumor_cherry_blossom_festival", &"rumor_spring_sports_fair",
	&"rumor_harvest_festival", &"", &"rumor_fishing_tourney_1", &"talk_fishing_tourney_1",
	&"rumor_morning_aerobics", &"talk_morning_aerobics", &"rumor_fireworks_show", &"",
	&"rumor_meteor_shower", &"rumor_harvest_moon_day", &"rumor_fall_sports_fair",
	&"rumor_mushroom_season", &"talk_mushroom_season", &"rumor_halloween",
	&"rumor_fishing_tourney_2", &"talk_fishing_tourney_2", &"rumor_toy_day",
	&"rumor_new_years_eve_countdown",
]
## `mEv_RUMOR_*` values the calendar topic checks (the enum's names, the table's slots).
const RUMOR_KAMAKURA := 1
const RUMOR_CHERRY_BLOSSOM := 5
const RUMOR_SUNDAY: Array[int] = [9, 10, 21, 22]
const RUMOR_FIREWORKS := 13
## `mString_MONTH_START` / `mString_DAY_START`; `0x55D` "furniture" for the sale topic.
const MONTH_STR := 0x66D
const DAY_STR := 0x64E
const SALE_KIND_STR := 0x55D
## `aQMgr_change_NG_msg` (first-job hint phase only).
const HINT_NG_MSG: Array[int] = [0x0F12, 0x0F91, 0x152E, 0x2586, 0x262E, 0x29F0, 0x29F9, 0x2A76]
const HINT_NG_BASE: Array[int] = [0x0F12, 0x0F8C, 0x1526, 0x257E, 0x262D, 0x29F0, 0x29F0, 0x2A76]
const HINT_NG_RND_MAX: Array[int] = [2, 10, 10, 10, 2, 10, 10, 2]
## `aQMgr_get_fj_hint_msg`: `0x0841 + looks × 10 + hint`.
const FJ_HINT_BASE := 0x0841
## `mPr_AddFirstJobHint`: ten hints, then bit 7 marks them done.
const FJ_HINT_COUNT := 10
const FJ_HINT_DONE := 0x80
## `mSP_KIND_*` groups for trades (`l_quest_category_0` / `_1`).
const CATEGORY_0 := [&"furniture", &"carpet", &"wallpaper"]
const CATEGORY_1 := [&"cloth", &"paper", &"diary"]
const SEL_RANDOM := 0
const SEL_PITFALL := 1
const PITFALL_ITEM := &"pitfall"
const MONEY_30000 := &"money_30000"
## Weather index as `Common_Get(weather)` (sakura counts as clear).
const WEATHER_INDEX := {&"clear": 0, &"rain": 1, &"snow": 2, &"sakura": 0}

## `aQMgr_TALK_STEP_*` (plus `DONE` once the talk is over).
enum Step {
	SELECT,
	RECONF_OR_NORMAL,
	ROOT_RECONF_OR_NORMAL,
	NO_OR_NORMAL,
	FULL_ITEM_OR_NORMAL,
	RENEW_ERRAND_OR_NORMAL,
	NEW_QUEST_OR_NORMAL,
	NORMAL,
	OCCUR_QUEST,
	GIVEUP,
	GIVEUP_ITEM,
	FIN_QUEST_START,
	FIN_QUEST_START_NOT_HAND,
	FIN_QUEST_REWARD,
	FIN_QUEST_THANKS,
	AFTER_REWARD,
	AFTER_REWARD_THANKS,
	GET_ITEM,
	CHANGE_WAIT,
	RENEW_ERRAND_IRAI_END,
	RENEW_ERRAND_IRAI_END_GIVE_ITEM,
	CONTEST_HOKA_OR_NORMAL,
	FINISH_LETTER,
	FINISH,
	DONE,
}

## `manager->last_strings`: last picks of `aQMgr_order_set_string_1` / `_4` so a topic
## doesn't repeat its word twice running. Lives as long as the quest manager actor.
static var last_strings := PackedInt32Array([255, 255, 255, 255, 255, 255, 255])

var villager: VillagerData
var state: VillagerState
var inventory: Inventory
var looks: int = 0
var slot: int = -1
var step: Step = Step.SELECT
## Everyday chat has taken over (`aQMgr_TALK_KIND_NORMAL`).
var _normal: bool = false
## `manager->choice.talk_action`: the menu pick this step answers, -1 for none.
var _talk_action: int = -1
## `l_normal_info`.
var trade_items: Array[StringName] = [&"", &"", &"", &"", &""]
var pay: int = 0
var item_idx: int = -1
var free_idx: int = -1
var letter: Dictionary = {}
## `manager->give_item` — the item a trade must not pick back (none outside quests).
var give_item: StringName = &""
## Called with a letter dictionary for `aQMgr_order_show_letter` (UI hook).
var show_letter: Callable
## Called for `aQMgr_order_change_gobi` (catchphrase editor).
var edit_catchphrase: Callable
## First-job hint counter (`Private_c.hint_count`), read and written through these.
var hint_count_get: Callable
var hint_count_set: Callable

## ---- quest talk
var quests: VillagerQuests
var talk_info: NpcTalkInfo
var residents: TownResidents
var now_minute: int = 0
var month: int = 1
var day: int = 1
## Posts a `MailData` to the player's mailbox; false when it is full (`mMl_chk_mail_free_space`).
var send_mail: Callable
## Money power (`mPr_GetMoneyPower`) for quest pay.
var money_power: int = 0
## What the flower contest counts in the villager's home acre:
## `(block: Vector2i) -> {"seed": n, "flower": n, "null": n}` (`mQst_GetFlower*Num`).
var field_counts: Callable
var cloth_at_start: StringName = &""
var _regist: Array[Dictionary] = []
var _regist_idx: int = -1
var _msg_category: int = VillagerQuests.Msg.NONE
var _category_start: int = 0
## `manager->target`.
var _target: Dictionary = {}


func _init(p_villager: VillagerData, p_state: VillagerState, p_ctx: DialogueContext) -> void:
	villager = p_villager
	state = p_state
	context = p_ctx
	if context != null and context.rng == null:
		context.rng = RandomNumberGenerator.new()
		context.rng.randomize()
	inventory = context.inventory if context != null else null
	if villager != null and villager.personality != null:
		looks = clampi(int(villager.personality.looks), 0, 5)
	if Game != null:
		quests = Game.quests
		talk_info = Game.npc_talk_info
		residents = Game.residents
	if quests == null:
		quests = VillagerQuests.new()
	if talk_info == null:
		talk_info = NpcTalkInfo.new()
	now_minute = Clock.absolute_minute()
	month = Clock.month
	day = Clock.day
	## `aQMgr_set_talk_info`: `manager->cloth = animal->cloth` at the start of the talk.
	cloth_at_start = worn_cloth(villager, state)


## `aQMgr_talk_start_kamakura` / `_summercamp`: an event guest's talk skips the quest
## menu and runs straight on the greeting game's demo orders (`aQMgr_talk_normal_kamakura`).
func as_guest() -> void:
	_normal = true
	step = Step.NORMAL


## The greeting (or the last message) ended on a continue.
func next_step() -> Dictionary:
	if _normal:
		step = Step.DONE
		return {}
	return _quest_run(-1)


## The player picked `index` from the menu `next_step` put up.
func choose(index: int) -> Dictionary:
	if _normal:
		step = Step.DONE
		return {}
	return _quest_run(index)


## `aQMgr_talk_quest_select_get_choice` (default arm).
func _select_choices() -> Array[String]:
	return _labels([_choice_rand(CHOICE_HELP, 10), _choice_rand(CHOICE_TALK, 10), _choice_rand(CHOICE_NEVERMIND, 5)])


## `aQMgr_talk_quest_change_normal_or_hint`: "Never mind" cancels; anything else is a chat
## (+1 friendship) — `aQMgr_TALK_COMMON_CHANGE_TALK_NORMAL`.
func _change_normal_or_hint() -> Dictionary:
	if _talk_action == 2:
		return _cancel_msg(CANCEL_MSG)
	if state != null:
		state.add_friendship(1)
	_normal = true
	step = Step.NORMAL
	return {"msg": normal_select_talk()}


## `aQMgr_actor_get_my_msg`.
func _my_msg(base: int) -> int:
	return base + looks * 3 + _rand(3)


## `aQMgr_talk_normal_select_talk`.
func normal_select_talk() -> int:
	_clear_normal_info()
	_normal_set_free_str()
	var msg_no: int
	if not _hints_done() or _first_job_active():
		msg_no = FJ_HINT_BASE + looks * 10 + _hint_count()
		_add_hint()
	elif state != null and state.mood == VillagerState.Mood.HAPPY:
		msg_no = _decide_ki()
	else:
		msg_no = _decide_normal()
	return _change_ng_msg(msg_no)


func _clear_normal_info() -> void:
	trade_items = [&"", &"", &"", &"", &""]
	pay = 0
	item_idx = -1
	free_idx = -1
	letter = {}


## `aQMgr_normal_set_free_str`: town fruit, town, the resident who started the town and
## another villager (`mNpc_GetOtherAnimalPersonalID`).
func _normal_set_free_str() -> void:
	if context == null:
		return
	var fruit: ItemData = ItemCatalog.get_item(Game.town_fruit if Game != null else &"apple")
	_set_free(10, fruit.display_name if fruit != null else "")
	_set_free(11, context.town_name)
	_set_free(12, context.player_name)
	var other: String = _other_villager_name()
	if other != "":
		_set_free(13, other)


func _other_villager_name() -> String:
	if Game == null or Game.residents == null:
		return ""
	var others: Array[StringName] = []
	for id: StringName in Game.residents.resident_ids():
		if villager == null or id != villager.id:
			others.append(id)
	if others.is_empty():
		return ""
	var v: VillagerData = VillagerCatalog.get_villager(others[_rand(others.size())])
	return v.display_name if v != null else ""


## `aQMgr_decide_ki_msg_no` (happy villager).
func _decide_ki() -> int:
	var msg: int = -1
	match decide_idx_prob_table(KI_PROB):
		0:
			msg = KI_NORMAL[looks] + _rand(10)
		1:
			msg = _msg_weather_time(KI_WEATHER_TIME[looks], 6, 2, 2)
		2:
			msg = _check_possession(_free_pocket(), KI_FREE_ITEM[looks], 3, true)
		3:
			msg = _check_possession(_ftr_pocket(), KI_FTR[looks], 3, false)
		4:
			msg = _check_possession(_free_pocket_with_money(), KI_FREE_ITEM_MONEY[looks], 3, true)
	if msg == -1:
		msg = KI_NORMAL[looks] + _rand(10)
	return msg


## `aQMgr_decide_normal_msg_no`.
func _decide_normal() -> int:
	if decide_idx_prob_table(NORMAL_1_PROB) == 0:
		return _decide_normal_2()
	return _decide_game()


## `aQMgr_decide_normal_2_msg_no`.
func _decide_normal_2() -> int:
	var msg: int = -1
	match decide_idx_prob_table(NORMAL_2_PROB):
		0:
			msg = _decide_letter()
		1:
			msg = _decide_normal_3()
		2:
			msg = _decide_trade()
		3:
			msg = _decide_memory()
	if msg == -1:
		msg = _decide_normal_3()
	return msg


## `aQMgr_decide_msg_normal_3_msg_no`.
func _decide_normal_3() -> int:
	match decide_idx_prob_table(NORMAL_3_PROB):
		0:
			return NORMAL3_NORMAL[looks] + _rand(10)
		1:
			return _msg_weather_time(NORMAL3_WEATHER_TIME[looks], 6, 2, 2)
		2:
			## `mLd_PlayerManKindCheck()` (a visitor) drops the first line; never here.
			return NORMAL3_WEATHER[looks] + _weather() * 5 + _rand(5)
		_:
			var m: int = clampi((context.month if context != null else 1) - 1, 0, 11)
			return NORMAL3_SEASON[looks] + SEASON_ADD[m]


## `aQMgr_decide_msg_trade`.
func _decide_trade() -> int:
	match decide_idx_prob_table(TRADE_PROB):
		0:
			return _check_possession(_free_pocket(), TRADE_FREE_ITEM[looks], 5, true)
		1:
			return _check_possession(_ftr_pocket(), TRADE_FTR[looks], 5, false)
		2:
			return _check_possession(_bug_fish_pocket(), TRADE_ITEM[looks], 5, false)
		_:
			return _check_possession(_free_pocket_with_money(), TRADE_FREE_ITEM_MONEY[looks], 5, true)


## `aQMgr_decide_msg_memory`. The memories it recalls belong to *other* players; with one
## player only the "best friends" line (friendship > 80) is left, then a trade topic.
func _decide_memory() -> int:
	_rand(3)
	if state != null and state.relationship != null and state.relationship.friendship > 80:
		return NORMAL2_MEMORY[looks] + 3 * 2 + 2
	return _decide_trade()


## `aQMgr_decide_msg_letter`. Saved letters come from other players' memories; the one
## source a single player sees is the "secret" handbill (`aQMgr_get_memory_mail_secret`,
## mail `0x22 + rand 15`).
func _decide_letter() -> int:
	var idx: int = _rand(6)
	if idx == 5:
		var mail_no: int = 0x22 + _rand(15)
		letter = MailBank.letter(mail_no, context.player_name if context != null else "")
		letter["paper_type"] = _rand(MailBank.PAPER_NUM)
		return NORMAL2_LETTER[looks] + 5
	return -1


## `aQMgr_decide_game_msg_no`.
func _decide_game() -> int:
	if decide_idx_prob_table(GAME_PROB) == 0:
		return GAME_HINT[looks] + _rand(5)
	## `aQMgr_decide_msg_game_ev`: the animal picked to move talks about it.
	if Game != null and Game.residents != null and slot >= 0 and Game.residents.remove_idx == slot:
		return REMOVE_YES[looks] + _rand(3)
	return _decide_msg_ev()


## `aQMgr_decide_msg_ev`: a coming special visitor or a calendar rumour, else the hint.
func _decide_msg_ev() -> int:
	var msg: int = -1
	match decide_idx_prob_table(EV_PROB):
		0:
			msg = _decide_special_ev()
		1:
			msg = _decide_calendar_ev()
	if msg == -1:
		msg = _decide_special_ev()
	if msg == -1:
		msg = GAME_HINT[looks] + _rand(5)
	return msg


## `aQMgr_decide_msg_special_ev`: before the visitor's start (on its day too, or until the
## sale ends), `l_ev_special + subtype × 3`, with the start month / day in FREE12 / FREE13.
func _decide_special_ev() -> int:
	if Game == null or Game.events == null:
		return -1
	var cal: EventCalendar = Game.events
	var sub: int = EventCalendar.SPECIAL_POOL.find(cal.special_type)
	if sub < 0:
		return -1
	var start_md: int = int(cal.special_dates.get("special1", 0))
	var start_year: int = cal.special_year
	var start_ord: int = EventDates.ordinal(start_year, EventDates.md_month(start_md), EventDates.md_day(start_md))
	var start_at: int = start_ord * 24 + int(cal.special_dates.get("special3", 0))
	var today_ord: int = EventDates.ordinal(Clock.year, Clock.month, Clock.day)
	var now_at: int = today_ord * 24 + Clock.hour
	var talk: bool = now_at < start_at
	if cal.special_type == &"shop_sale":
		var end_md: int = int(cal.special_dates.get("special2", 0))
		var end_year: int = start_year + (1 if start_md > end_md else 0)
		var end_at: int = (
			EventDates.ordinal(end_year, EventDates.md_month(end_md), EventDates.md_day(end_md)) * 24
			+ int(EventCalendar.SPECIAL_END_HOUR.get(&"shop_sale", 23))
		)
		talk = talk or now_at < end_at
	else:
		talk = talk or today_ord == start_ord
	if not talk:
		return -1
	var msg: int = EV_SPECIAL[looks] + sub * 3 + _rand(3)
	if cal.special_type == &"shop_sale":
		## The first bargain's kind (`0x55D` furniture …); Nook's sale stock is furniture.
		_set_free(11, DialogueCatalog.rom_string(SALE_KIND_STR))
	_set_free(12, DialogueCatalog.rom_string(MONTH_STR + EventDates.md_month(start_md) - 1))
	_set_free(13, DialogueCatalog.rom_string(DAY_STR + EventDates.md_day(start_md) - 1))
	return msg


## `aQMgr_decide_msg_calendar_ev`: one of today's rumours (`mEv_get_rumor`),
## `l_ev_cal + rumour × 2 + rand 2`, with the tourney / fireworks day and the moon dates.
func _decide_calendar_ev() -> int:
	var rumor: int = -1
	if Game != null and Game.events != null:
		var live: Array[int] = []
		for id: StringName in Game.events.active_rumors():
			var idx: int = RUMOR_TABLE.find(id)
			if idx >= 0:
				live.append(idx)
		if not live.is_empty():
			rumor = live[_rand(live.size())]
	var msg: int = -1
	if rumor != -1:
		msg = EV_CAL[looks] + rumor * 2 + _rand(2)
	if (rumor == RUMOR_CHERRY_BLOSSOM and Clock.term_idx() != 4) or (
		rumor == RUMOR_KAMAKURA and Clock.season() != Clock.Season.WINTER
	):
		msg = -1
	elif rumor in RUMOR_SUNDAY:
		_set_free(14, DialogueCatalog.rom_string(DAY_STR + _next_weekday_day(0) - 1))
	elif rumor == RUMOR_FIREWORKS:
		_set_free(15, DialogueCatalog.rom_string(DAY_STR + _next_weekday_day(6) - 1))
	var moon: Vector2i = moon_dates(Clock.year)
	_set_free(16, DialogueCatalog.rom_string(MONTH_STR + moon.x / 100 - 1))
	_set_free(17, DialogueCatalog.rom_string(DAY_STR + moon.x % 100 - 1))
	_set_free(18, DialogueCatalog.rom_string(MONTH_STR + moon.y / 100 - 1))
	_set_free(19, DialogueCatalog.rom_string(DAY_STR + moon.y % 100 - 1))
	return msg


## `mEv_get_next_weekday`: day of the month of the next `weekday` (today counts), wrapped
## past the month's last day.
func _next_weekday_day(weekday: int) -> int:
	var today: int = Clock.weekday()
	var d: int = Clock.day + (weekday - today if weekday >= today else 7 - (today - weekday))
	var last: int = EventDates.days_in_month(Clock.year, Clock.month)
	if d > last:
		d -= last
	return d


## `lbRk_ToSeiyouReki` for lunar 8/15 and 9/13 as month×100+day. 8/15 is the harvest-moon
## table; 9/13 is approximated as 28 days later (one lunar month less two days).
static func moon_dates(year: int) -> Vector2i:
	var hm: Vector2i = EventDates.HARVEST_MOON.get(year, Vector2i(9, 21))
	var at: Vector3i = EventDates.from_ordinal(EventDates.ordinal(year, hm.x, hm.y) + 28)
	return Vector2i(hm.x * 100 + hm.y, at.y * 100 + at.z)


## `aQMgr_get_msg_weather_time`.
func _msg_weather_time(base: int, time_cnt: int, weather_cnt: int, msg_cnt: int) -> int:
	var hour: int = context.hour if context != null else 12
	return base + DialogueGreeting.time_kind(hour) * time_cnt + _weather() * weather_cnt + _rand(msg_cnt)


func _weather() -> int:
	var w: StringName = context.weather if context != null else &"clear"
	return int(WEATHER_INDEX.get(w, 0))


## `aQMgr_decide_msg_check_possession`.
func _check_possession(idx: int, base: int, count: int, is_free: bool) -> int:
	if idx == -1:
		return -1
	if is_free:
		free_idx = idx
	else:
		item_idx = idx
	return base + _rand(count)


## `aQMgr_change_NG_msg`: while hints are still owed, lines that point at the hint topic
## are re-rolled inside their block.
func _change_ng_msg(msg_no: int) -> int:
	if _hints_done():
		return msg_no
	for i: int in HINT_NG_MSG.size():
		if msg_no != HINT_NG_MSG[i]:
			continue
		var out: int = HINT_NG_BASE[i] + _rand(HINT_NG_RND_MAX[i] - 1)
		if out in HINT_NG_MSG:
			out += 1
		return out
	return msg_no


## ---------------------------------------------------------------- demo orders

## `aQMgr_talk_normal_demo_order`: `slot` is the order type, `value` its argument.
func order(order_type: int, value: int) -> void:
	## Only the everyday chat reads `mDemo_ORDER_QUEST` (`aQMgr_TALK_SUB_STATE_DEMO_ORDER_WAIT`).
	if not _normal:
		return
	match order_type:
		0:
			_order_roof_color(value)
		1:
			_order_control_animal(value)
		2:
			_order_decide_trade(value)
		3:
			_order_trade(value)
		4:
			if show_letter.is_valid() and not letter.is_empty():
				show_letter.call(letter)
		5:
			## `aQMgr_order_fluctuation_friendship`: values above 100 are losses.
			var amount: int = value
			if amount > 100:
				amount = 100 - amount
			if state != null:
				state.add_friendship(amount)
		7:
			_order_set_calendar(value)
		9:
			_order_set_string(value)
		_:
			## 6 plays a remembered town tune, 8 opens the birthday entry: not ported yet.
			pass


## `aQMgr_order_change_roof_color`.
func _order_roof_color(value: int) -> void:
	var color: int = value - 1 if value > 0 and value <= 16 else 0
	if Game == null or Game.interiors == null:
		return
	var house: House = Game.interiors.player_house()
	if house == null:
		return
	var pending: bool = house.next_outlook_pal != house.outlook_pal
	house.outlook_pal = color
	if not pending:
		house.next_outlook_pal = color


## `aQMgr_control_animal_info`: 1 opens the catchphrase editor, anything else re-picks who
## is thinking of moving (`aQMgr_order_cancel_remove`).
func _order_control_animal(value: int) -> void:
	if value == 1:
		if edit_catchphrase.is_valid():
			edit_catchphrase.call()
		return
	if Game == null or Game.residents == null:
		return
	var rng := context.rng if context != null else RandomNumberGenerator.new()
	Game.residents.cancel_moving({"rng": rng, "met": func(id: StringName) -> bool: return Game.player_met(id)})


## `aQMgr_order_decide_trade`: values 1–17 pick what the villager offers and for how much.
func _order_decide_trade(value: int) -> void:
	var wallet: int = inventory.wallet if inventory != null else 0
	match value:
		1:
			_decide_trade_common(false, CATEGORY_0, SEL_RANDOM, 100, 3000, true)
		2:
			_decide_trade_common(false, CATEGORY_0, SEL_RANDOM, 1000, 5000, true)
		3:
			_decide_trade_common(false, CATEGORY_0, SEL_RANDOM, wallet, wallet, false)
		4:
			_decide_trade_common(false, CATEGORY_0, SEL_RANDOM, wallet / 2, wallet / 2, false)
		5:
			_decide_trade_common(false, CATEGORY_0, SEL_RANDOM, 3000, 3000, false)
		6:
			_decide_trade_common(false, CATEGORY_0, SEL_RANDOM, 1000, 1000, false)
		7:
			_decide_trade_common(true, CATEGORY_1, SEL_RANDOM, 100, 3000, true)
		8:
			_decide_trade_common(false, CATEGORY_0, SEL_PITFALL, 100, 3000, true)
		9:
			_decide_trade_common(false, CATEGORY_0, SEL_PITFALL, wallet, wallet, true)
		10:
			_decide_trade_common(false, CATEGORY_0, SEL_PITFALL, wallet / 2, wallet / 2, true)
		11:
			_decide_trade_common(true, CATEGORY_1, SEL_PITFALL, 100, 3000, true)
		12:
			_decide_trade_common(false, CATEGORY_0, SEL_RANDOM, 100, 500, true)
		13:
			_decide_trade_common(false, CATEGORY_0, SEL_RANDOM, 1000, 2000, true)
		14:
			_decide_pay(3000, 5000, true)
		15:
			_decide_pay(2000, 2999, true)
		16:
			_decide_pay(1000, 1999, true)
		17:
			_decide_pay(100, 999, true)


## `aQMgr_order_decide_trade_common_item` + `_pay`.
func _decide_trade_common(
	bug_fish: bool, cats: Array, mode: int, pay_min: int, pay_max: int, round_tens: bool
) -> void:
	var picked: Dictionary = _random_bug_fish_pocket() if bug_fish else _random_ftr_pocket()
	item_idx = int(picked.get("idx", -1))
	if item_idx >= 0:
		trade_items[0] = picked["item"] as StringName
		_set_item(0, trade_items[0])
	for i: int in cats.size():
		var cat: StringName = cats[i]
		var goods: StringName = _goods(cat)
		trade_items[1 + i] = goods
		_set_item(1 + i, goods)
	var chosen: StringName = PITFALL_ITEM
	if mode == SEL_RANDOM:
		chosen = trade_items[1 + _rand(cats.size())]
	trade_items[4] = chosen
	_set_item(4, chosen)
	_decide_pay(pay_min, pay_max, round_tens)


## `aQMgr_order_decide_trade_common_pay` / `aQMgr_get_rnd_no_cut_10`.
func _decide_pay(pay_min: int, pay_max: int, round_tens: bool) -> void:
	var lo: int = pay_min
	var d: int = pay_max - pay_min
	if d < 0:
		lo = pay_max
		d = -d
	var add: int = _rand_f(d)
	if round_tens:
		add = (add / 10) * 10
	pay = add + lo
	_set_free(19, str(pay))


## `mQst_GetGoods_common` / `mFI_GetOtherFruit`. Goods come from the shop pools; the ROM's
## A/B/C priority lists (`mSP_LISTTYPE_ABC`) aren't modelled (see `ShopGoods`).
func _goods(cat: StringName) -> StringName:
	match cat:
		&"diary":
			var fruit_idx: int = _rand(4)
			var town: int = maxi(ShopBook.FRUITS.find(Game.town_fruit if Game != null else &"apple"), 0)
			if fruit_idx == town:
				fruit_idx += 1
			return ShopBook.FRUITS[fruit_idx]
		&"paper":
			return ShopGoods.PAPER
	var pool: Array[StringName] = []
	match cat:
		&"furniture":
			pool = ShopGoods.furniture_pool()
			## A guest's trades: 10% from the snow cabin's list, 20% from the tent's.
			var guest: StringName = context.guest if context != null else &""
			var roll: int = _rand(100)
			if guest == &"kamakura" and roll >= 90:
				pool = FtrCatalog.named_list("ftr", "Kamakura")
			elif guest == &"camper" and roll >= 80:
				pool = FtrCatalog.named_list("ftr", "Tent")
			if pool.is_empty():
				pool = ShopGoods.furniture_pool()
		&"carpet":
			pool = ShopGoods.category_pool(ItemData.Category.FLOOR)
		&"wallpaper":
			pool = ShopGoods.category_pool(ItemData.Category.WALL)
		&"cloth":
			pool = ShopGoods.category_pool(ItemData.Category.CLOTH)
	var skip: Array[StringName] = [trade_items[0], trade_items[1]]
	if cat == &"cloth" and Game != null:
		skip.append(Game.cloth_id)
	var live: Array[StringName] = []
	for id: StringName in pool:
		if id not in skip:
			live.append(id)
	if live.is_empty():
		return pool[0] if not pool.is_empty() else &""
	return live[_rand(live.size())]


## `aQMgr_order_trade`: values 1–23 move the goods and bells.
func _order_trade(value: int) -> void:
	match value:
		1, 2, 3, 4:
			## `aQMgr_order_move_trade_no_term`: a gift into the free pocket.
			_give_to_pocket(value, free_idx)
		5, 6, 7, 8:
			## Player hands over their item for goods 1–4 (`_mode_GIVE`).
			_take_player_item()
		9, 10, 11, 12:
			## Player pays (`aQMgr_trade_take_money`).
			if inventory != null:
				inventory.set_wallet(maxi(inventory.wallet - pay, 0))
		13, 23:
			## Player hands over their item for bells (`give_money_and_take_item_mode_GIVE`).
			_take_player_item()
		14, 15, 16, 17:
			_give_to_pocket(value - 13, item_idx)
		18, 19, 20, 21:
			_give_to_pocket(value - 17, free_idx)
		22:
			_give_money()


func _give_to_pocket(trade_idx: int, pocket: int) -> void:
	if inventory == null or pocket < 0 or trade_idx < 0 or trade_idx >= trade_items.size():
		return
	var item_id: StringName = trade_items[trade_idx]
	if item_id == &"":
		return
	var s: InventorySlot = inventory.slot_at(pocket)
	if s == null:
		return
	s.set_stack(item_id, 1)
	inventory.changed.emit()


## `aQMgr_trade_take_item`: only if that pocket still holds the offered item.
func _take_player_item() -> void:
	if inventory == null or item_idx < 0:
		return
	var s: InventorySlot = inventory.slot_at(item_idx)
	if s != null and not s.is_empty() and s.item.item_id == trade_items[0]:
		s.clear()
		inventory.changed.emit()


## `aQMgr_trade_give_money`: over the wallet cap, 30,000-bell bags go into pockets.
func _give_money() -> void:
	if inventory == null:
		return
	var money: int = inventory.wallet + pay
	if money > Inventory.WALLET_MAX:
		if item_idx != -1:
			var s: InventorySlot = inventory.slot_at(item_idx)
			if s != null:
				s.set_stack(MONEY_30000, 1)
				money -= 30000
		while money > Inventory.WALLET_MAX:
			var empty: int = _first_empty_pocket()
			if empty == -1:
				money = Inventory.WALLET_MAX
				break
			inventory.slot_at(empty).set_stack(MONEY_30000, 1)
			money -= 30000
	inventory.set_wallet(maxi(money, 0))
	inventory.changed.emit()


## `aQMgr_order_set_calendar`: the western dates of lunar 8/15 and 9/13 (FREE11–14) and
## today's lunar date (FREE15/16), as month and day strings. `lb_reki`'s tables aren't ported:
## the moon dates come from `moon_dates`, and today's lunar date counts 29.53-day months from
## the harvest moon's lunar 8/1.
func _order_set_calendar(value: int) -> void:
	if value != 1:
		return
	var moon: Vector2i = moon_dates(Clock.year)
	_set_md(11, 12, moon.x)
	_set_md(13, 14, moon.y)
	_set_md(15, 16, lunar_today(Clock.year, Clock.month, Clock.day))


func _set_md(month_free: int, day_free: int, md: int) -> void:
	_set_free(month_free, DialogueCatalog.rom_string(MONTH_STR + clampi(md / 100, 1, 12) - 1))
	_set_free(day_free, DialogueCatalog.rom_string(DAY_STR + clampi(md % 100, 1, 31) - 1))


## Approximate `lbRk_ToKyuuReki` (month×100+day).
static func lunar_today(year: int, month: int, day: int) -> int:
	var hm: Vector2i = EventDates.HARVEST_MOON.get(year, Vector2i(9, 21))
	var first: int = EventDates.ordinal(year, hm.x, hm.y) - 14
	var d: float = float(EventDates.ordinal(year, month, day) - first)
	var months: int = floori(d / 29.53)
	var lunar_month: int = posmod(8 - 1 + months, 12) + 1
	var lunar_day: int = int(d - float(months) * 29.53) + 1
	return lunar_month * 100 + clampi(lunar_day, 1, 30)


## `aQMgr_order_set_string`: 1–4 fill the item strings with random words from the string
## table (`mString_Load_StringFromRom`).
func _order_set_string(value: int) -> void:
	match value:
		2:
			_set_item_number(0, 1, 10)
			_set_item_number(1, 10, 99)
			_set_item_number(2, 0, 9)
			var level: int = clampi(Game.shops.nook_level() if Game != null and Game.shops != null else 0, 0, 3)
			_set_item_text(3, DialogueCatalog.rom_string(0x454 + level))
			_random_string(4, 0x434, 32, -1)
		3:
			for i: int in 3:
				_random_string(i, [0x464, 0x2F4, 0x4A0][i], 32, -1)
		4:
			for i: int in 2:
				var last: int = last_strings[i]
				if last < 12:
					last_strings[i] = _random_string(i, [0x458, 0x494][i], 11, last)
				else:
					last_strings[i] = _random_string(i, [0x458, 0x494][i], 12, -1)
			## Unset birthday reads as January 1st (`mPr_birthday_c` zeroed → month clamps to 1).
			_set_item_text(2, DialogueCatalog.rom_string(0x494 + posmod(-3, 12)))
			_set_item_text(3, _month_name(1))
			_set_item_text(4, str(1))
		_:
			var bases: Array[int] = [0x6A1, 0x679, 0x334, 0x314, 0x414]
			var maxes: Array[int] = [40, 40, 32, 32, 32]
			for i: int in 5:
				var last: int = last_strings[2 + i]
				if last < maxes[i]:
					last_strings[2 + i] = _random_string(i, bases[i], maxes[i] - 1, last)
				else:
					last_strings[2 + i] = _random_string(i, bases[i], maxes[i], -1)


## `aQMgr_set_random_string`.
func _random_string(item_no: int, base: int, count: int, skip_idx: int) -> int:
	var idx: int = _rand_f(count)
	if skip_idx >= 0 and skip_idx == idx:
		idx += 1
	_set_item_text(item_no, DialogueCatalog.rom_string(base + idx))
	return idx


func _set_item_number(item_no: int, lo: int, hi: int) -> void:
	_set_item_text(item_no, str(lo + _rand_f(hi - lo)))


## ---------------------------------------------------------------- pockets

## `aQMgr_get_free_possession_idx`.
func _free_pocket() -> int:
	return _first_empty_pocket()


## `aQMgr_get_free_possession_idx_check_money`.
func _free_pocket_with_money() -> int:
	var idx: int = _first_empty_pocket()
	if idx != -1 and inventory != null and inventory.wallet < 3000:
		return -1
	return idx


## `aQMgr_get_possession_ftr_cpt_wl`: first furniture, else carpet, else wallpaper.
func _ftr_pocket() -> int:
	for want: Array in [[ItemData.Category.FURNITURE], [ItemData.Category.FLOOR], [ItemData.Category.WALL]]:
		for i: int in Inventory.POCKET_SLOTS:
			var data: ItemData = _normal_pocket_item(i)
			if data != null and data.id != give_item and data.category == int(want[0]):
				return i
	return -1


## `aQMgr_get_possession_item`: first insect, else fish.
func _bug_fish_pocket() -> int:
	for want: int in [ItemData.Category.BUG, ItemData.Category.FISH]:
		for i: int in Inventory.POCKET_SLOTS:
			var data: ItemData = _normal_pocket_item(i)
			if data != null and data.category == want:
				return i
	return -1


## `aQMgr_get_possession_ftr_cpt_wl_rnd`.
func _random_ftr_pocket() -> Dictionary:
	return _random_pocket(
		func(d: ItemData) -> bool:
			return d.id != give_item and (
				d.category == ItemData.Category.FURNITURE
				or d.category == ItemData.Category.FLOOR
				or d.category == ItemData.Category.WALL
			)
	)


## `aQMgr_get_possession_item_rnd`.
func _random_bug_fish_pocket() -> Dictionary:
	return _random_pocket(
		func(d: ItemData) -> bool: return d.category == ItemData.Category.BUG or d.category == ItemData.Category.FISH
	)


func _random_pocket(match_fn: Callable) -> Dictionary:
	var hits: Array[int] = []
	for i: int in Inventory.POCKET_SLOTS:
		var data: ItemData = _normal_pocket_item(i)
		if data != null and bool(match_fn.call(data)):
			hits.append(i)
	if hits.is_empty():
		return {}
	var idx: int = hits[_rand(hits.size())]
	return {"idx": idx, "item": _normal_pocket_item(idx).id}


func _normal_pocket_item(i: int) -> ItemData:
	if inventory == null:
		return null
	var s: InventorySlot = inventory.slot_at(i)
	if s == null or s.is_empty() or s.item.condition != InventoryItem.Condition.NORMAL:
		return null
	return ItemCatalog.get_item(s.item.item_id)


func _first_empty_pocket() -> int:
	if inventory == null:
		return -1
	for i: int in Inventory.POCKET_SLOTS:
		var s: InventorySlot = inventory.slot_at(i)
		if s != null and s.is_empty():
			return i
	return -1


## ---------------------------------------------------------------- helpers

## `aQMgr_decide_idx_prob_table`: a 100-entry table, 30 random swaps, one random draw.
func decide_idx_prob_table(probs: Array[int]) -> int:
	var table := PackedInt32Array()
	table.resize(100)
	table.fill(0)
	var j: int = 0
	for i: int in probs.size():
		for _p: int in probs[i]:
			if j >= 100:
				break
			table[j] = i
			j += 1
	for _k: int in 30:
		var a: int = _rand(100)
		var b: int = _rand(100)
		var tmp: int = table[a]
		table[a] = table[b]
		table[b] = tmp
	return table[_rand(100)]


func _hint_count() -> int:
	return int(hint_count_get.call()) & 0x7F if hint_count_get.is_valid() else FJ_HINT_DONE


func _hints_done() -> bool:
	var raw: int = int(hint_count_get.call()) if hint_count_get.is_valid() else FJ_HINT_DONE
	return (raw & FJ_HINT_DONE) != 0


## `mPr_AddFirstJobHint`.
func _add_hint() -> void:
	if not hint_count_get.is_valid() or not hint_count_set.is_valid():
		return
	var hints: int = int(hint_count_get.call()) + 1
	if (hints & 0x7F) >= FJ_HINT_COUNT:
		hints = FJ_HINT_DONE
	hint_count_set.call(hints)


func _first_job_active() -> bool:
	return Game != null and Game.first_job != null and Game.first_job.is_active()


func _set_free(n: int, text: String) -> void:
	if context == null:
		return
	if context.frees.size() < 20:
		context.frees.resize(20)
	context.frees[n] = text


func _set_item(n: int, item_id: StringName) -> void:
	var data: ItemData = ItemCatalog.get_item(item_id)
	_set_item_text(n, data.display_name if data != null else String(item_id))


func _set_item_text(n: int, text: String) -> void:
	if context != null:
		context.set_item_str(n, text)


func _month_name(month: int) -> String:
	return ShopMail.MONTHS[clampi(month, 1, 12) - 1]


func _rand(n: int) -> int:
	if n <= 1:
		return 0
	return context.rng.randi_range(0, n - 1)


## `RANDOM_F(x)`: truncated float draw in [0, x).
func _rand_f(n: int) -> int:
	if n <= 0:
		return 0
	return int(context.rng.randf() * float(n))


## ================================================================ quest talk

## `aQMgr_talk_quest_select_get_choice` labels.
const CHOICE_DELIVERY := 0x94
const CHOICE_FORGOT := 0x95
const CHOICE_FRUIT := 0x96
const CHOICE_PICKUP := 0x97
const CHOICE_BALL := 0x98
const CHOICE_SNOWMAN := 0x99
const CHOICE_FLOWERS := 0x9A
const CHOICE_UM := 0x9B
const CHOICE_FISH := 0xEA
const CHOICE_BUG := 0xEB
## `aQMgr_talk_quest_start_choice`: accept / turn down.
const CHOICE_ACCEPT := 0x43
const CHOICE_REJECT := 0x4D
const FULL_POCKETS_MSG := 0x440
const ROOT_RECONF_MSG := 0x3D4
const ERRAND_FORGET_MSG := 0x2B73
const THIEF_MSG := 0x499
const NO_REWARD_MSG := 0x4AB
const LETTER_THANKS_MSG := 0x1B17
const LETTER_OTHER_MSG := 0x1B29
const LETTER_FULL_MSG := 0x1B05
const FLOWER_SHORT_MSG := 0x1069
## `l_*reward_msg`, by `Reward` kind.
const REWARD_MSG: Array[int] = [0x011B, 0x00D3, 0x00E5, 0x00F7, 0x0109, 0x013F, 0x012D, 0x081D]
const CONTEST_REWARD_MSG: Array = [
	[0x011B, 0x00D3, 0x00E5, 0x1146, 0x1158, 0x116A, 0x00E5, 0x081D],
	[0x0DA3, 0x00D3, 0x00E5, 0x0DB5, 0x0DC7, 0x013F, 0x00E5, 0x081D],
	[0x0E57, 0x00D3, 0x00E5, 0x0E69, 0x0E7B, 0x013F, 0x00E5, 0x081D],
	[0x0FD9, 0x00D3, 0x00E5, 0x0FEB, 0x0FFD, 0x013F, 0x00E5, 0x081D],
	[0x157A, 0x00D3, 0x00E5, 0x1556, 0x1568, 0x013F, 0x00E5, 0x081D],
	[0x15F8, 0x00D3, 0x00E5, 0x15D4, 0x15E6, 0x013F, 0x00E5, 0x081D],
	[0x011B, 0x00D3, 0x00E5, 0x00F7, 0x0109, 0x013F, 0x012D, 0x081D],
]
const AFTER_REWARD_MSG: Array[int] = [0x0304, 0x0000, 0x0000, 0x0316, 0x0328, 0x0000, 0x0000, 0x0000]
## `aQMgr_actor_talk_after_reward` swaps in the soccer / snowman / flower tables.
const AFTER_CONTEST_SWAP := [CONTEST_REWARD_MSG[1], CONTEST_REWARD_MSG[2], CONTEST_REWARD_MSG[3]]
## `l_contest_hoka_msg_no`: "someone else already did it".
const CONTEST_HOKA_MSG: Array[int] = [0x1134, 0x0E21, 0x0ED5, 0x1057, 0x1544, 0x15C2, 0x1AF3]
## `l_quest_type_table_fj` / `_qst` and their kind tables.
const FJ_KINDS: Array = [[VillagerQuests.DELIVERY_NORMAL, VillagerQuests.DELIVERY_LOST], [VillagerQuests.ERRAND_REQUEST]]
const QST_KINDS: Array = [
	[VillagerQuests.DELIVERY_NORMAL, VillagerQuests.DELIVERY_FOREIGN, VillagerQuests.DELIVERY_REMOVE, VillagerQuests.DELIVERY_LOST],
	[VillagerQuests.ERRAND_REQUEST],
	[0, 1, 2, 3, 4, 5, 6],
]
## `aQMgr_actor_set_quest_data` results.
enum NewQuest { ERROR, SUCCESS, NO_SPACE, NO_FOREIGN_ID, NO_REMOVE_ANIMAL_ID }

## `manager->errand_next[mPr_ERRAND_QUEST_NUM]`: per errand, whether the next villager hands
## the item back (1) or passes it on (2); 0 = not decided. Lives with the quest manager.
static var errand_next := PackedByteArray([0, 0, 0, 0, 0])


## `aQMgr_actor_move_talk_init`: run the step the last message was waiting for.
func _quest_run(action: int) -> Dictionary:
	_talk_action = action
	match step:
		Step.SELECT:
			return _select_talk()
		Step.RECONF_OR_NORMAL:
			if _talk_action == 0:
				_msg_category = VillagerQuests.Msg.REQUEST_RECONF
				return _msg()
			return _change_normal_or_hint()
		Step.ROOT_RECONF_OR_NORMAL:
			if _talk_action == 0:
				_category_start = ROOT_RECONF_MSG
				return _msg()
			return _change_normal_or_hint()
		Step.NO_OR_NORMAL:
			if _talk_action == 0:
				_finish_first_job_open_quest()
				_target["free"] = {}
				_category_start = NO_WORK_MSG
				return _msg()
			return _change_normal_or_hint()
		Step.FULL_ITEM_OR_NORMAL:
			if _talk_action == 0:
				if (_target.get("set_data", []) as Array).is_empty():
					_category_start = FULL_POCKETS_MSG
				else:
					_msg_category = VillagerQuests.Msg.FULL_ITEM
				return _msg()
			return _change_normal_or_hint()
		Step.RENEW_ERRAND_OR_NORMAL:
			return _renew_errand_or_normal()
		Step.NEW_QUEST_OR_NORMAL:
			return _new_quest_or_normal()
		Step.OCCUR_QUEST:
			return _occur_quest()
		Step.GIVEUP:
			return _giveup()
		Step.FIN_QUEST_START:
			if _talk_action == 0:
				return _open_menu()
			return _change_normal_or_hint()
		Step.FIN_QUEST_START_NOT_HAND:
			if _talk_action == 2:
				return _cancel_msg(CANCEL_MSG)
			step = Step.FIN_QUEST_REWARD
			_msg_category = VillagerQuests.Msg.COMPLETE_INIT
			return _msg()
		Step.FIN_QUEST_REWARD:
			return _fin_quest_reward()
		Step.FIN_QUEST_THANKS:
			_msg_category = VillagerQuests.Msg.COMPLETE_END
			step = Step.CHANGE_WAIT
			return _with_anim(_msg(), "give", _target.get("reward_item", &""))
		Step.AFTER_REWARD:
			return _after_reward()
		Step.AFTER_REWARD_THANKS:
			_msg_category = VillagerQuests.Msg.AFTER_REWARD_THANKS
			_talk_finish()
			step = Step.CHANGE_WAIT
			return _with_anim(_msg(), "give", _target.get("reward_item", &""))
		Step.RENEW_ERRAND_IRAI_END_GIVE_ITEM:
			step = Step.CHANGE_WAIT
			_msg_category = VillagerQuests.Msg.REQUEST_END
			_talk_finish()
			return _with_anim(_msg(), "give", _target.get("quest_item", &""))
		Step.RENEW_ERRAND_IRAI_END:
			_msg_category = VillagerQuests.Msg.REQUEST_END
			_talk_finish()
			return _msg()
		Step.CONTEST_HOKA_OR_NORMAL:
			return _contest_hoka_or_normal()
		Step.FINISH_LETTER:
			return _finish_letter()
		Step.FINISH:
			_talk_finish()
			step = Step.DONE
			return {}
		Step.CHANGE_WAIT:
			## `aQMgr_talk_quest_change_wait`: message 0 — only reached after a message that
			## already closed the window.
			step = Step.DONE
			return {}
	step = Step.DONE
	return {}


## ---------------------------------------------------------------- select talk

## `aQMgr_actor_talk_select_talk` (a town villager; islanders aren't ported).
func _select_talk() -> Dictionary:
	_init_quest()
	_clear_target()
	var sel_regist: int = -1
	var target_flag: bool = true
	var r: int = _check_still_reward()
	if r != -1:
		_msg_category = VillagerQuests.Msg.AFTER_REWARD
		step = Step.AFTER_REWARD
	else:
		r = _check_own(true)
		if r != -1:
			var q: Dictionary = _regist[r]["quest"]
			var type: int = int(q["type"])
			var kind: int = int(q["kind"])
			if _check_finish(_regist[r]):
				_category_start = SELECT_TALK_MSG
				if type == VillagerQuests.Type.CONTEST and kind == VillagerQuests.CONTEST_LETTER:
					if _send_remail(q):
						step = Step.FINISH_LETTER
					else:
						step = Step.CONTEST_HOKA_OR_NORMAL
				elif type == VillagerQuests.Type.CONTEST and kind in [
					VillagerQuests.CONTEST_SOCCER, VillagerQuests.CONTEST_SNOWMAN, VillagerQuests.CONTEST_FLOWER
				]:
					_set_free(12, str(q.get("player_name", "")))
					step = Step.FIN_QUEST_START_NOT_HAND
				else:
					step = Step.FIN_QUEST_START
			else:
				if type == VillagerQuests.Type.ERRAND:
					step = Step.RENEW_ERRAND_OR_NORMAL
					sel_regist = r
					r = -1
				elif type == VillagerQuests.Type.CONTEST:
					if not VillagerQuests.limit_over(q, now_minute):
						if int(q["progress"]) == 0:
							if bool(q["player"]):
								step = Step.NO_OR_NORMAL
								_clear_target()
								target_flag = false
							else:
								step = Step.RECONF_OR_NORMAL
						else:
							step = Step.RECONF_OR_NORMAL
					else:
						step = Step.NO_OR_NORMAL
						_clear_target()
						target_flag = false
						_regist_idx = r
						_talk_finish()
				_category_start = SELECT_TALK_MSG
		else:
			r = _check_own(false)
			if r != -1:
				var q: Dictionary = _regist[r]["quest"]
				if not VillagerQuests.limit_over(q, now_minute):
					step = Step.RECONF_OR_NORMAL
					_category_start = SELECT_TALK_MSG
				else:
					if _is_open_errand(q):
						_expire_errand(r)
						target_flag = false
					step = Step.GIVEUP
					_msg_category = VillagerQuests.Msg.FAILURE_INIT
			else:
				r = _check_errand_from()
				if r != -1:
					var q: Dictionary = _regist[r]["quest"]
					if not VillagerQuests.limit_over(q, now_minute):
						step = Step.ROOT_RECONF_OR_NORMAL
						_category_start = SELECT_TALK_MSG
					else:
						step = Step.GIVEUP
						_msg_category = VillagerQuests.Msg.FAILURE_INIT
						if _is_open_errand(q):
							_expire_errand(r)
							if int(q["kind"]) == VillagerQuests.ERRAND_REQUEST:
								_msg_category = VillagerQuests.Msg.NONE
								_category_start = ERRAND_FORGET_MSG
							target_flag = false
				elif talk_info.quest_request(slot):
					step = Step.NEW_QUEST_OR_NORMAL
					_category_start = SELECT_TALK_MSG
				else:
					step = Step.NO_OR_NORMAL
					_category_start = SELECT_TALK_MSG
					_clear_target()
					target_flag = false
	if target_flag:
		if r != -1:
			_regist_idx = r
			_set_target_from_regist()
			if step != Step.AFTER_REWARD:
				_target["inv_idx"] = _get_item_idx()
		else:
			r = _new_quest(sel_regist)
		if int(_target["info"]["type"]) != VillagerQuests.Type.NONE:
			_set_free_str(r)
		_regist_idx = r
	return _msg(_quest_choices())


## A timed-out errand whose item hasn't been picked up: forget it right away.
func _is_open_errand(q: Dictionary) -> bool:
	return int(q["type"]) == VillagerQuests.Type.ERRAND and int(q["kind"]) in [
		VillagerQuests.ERRAND_REQUEST, VillagerQuests.ERRAND_REQUEST_CONTINUE
	]


func _expire_errand(r: int) -> void:
	_regist_idx = r
	_set_target_from_regist()
	_target["inv_idx"] = _get_item_idx()
	_set_free_str(r)
	_target["free"] = {}
	_target["free_idx"] = -1
	_talk_finish()


## `aQMgr_actor_init_quest` + `aQMgr_actor_regist_quest_move`.
func _init_quest() -> void:
	quests.sync_residents(residents)
	quests.move(now_minute, month, day)
	_regist = quests.registry(inventory, residents)
	_regist_idx = -1


## `aQMgr_talk_common_clear_talk_info` (target part).
func _clear_target() -> void:
	_target = {
		"info": VillagerQuests.new_base(),
		"from": &"",
		"to": &"",
		"inv_idx": -1,
		"quest_item": &"",
		"reward_kind": -1,
		"reward_item": &"",
		"pay": 0,
		"limit": 0,
		"set_data": [],
		"free_idx": -1,
		"free": {},
		"errand_type": VillagerQuests.ERRAND_TYPE_NONE,
		"flower_goal": 0,
	}


## `aQMgr_actor_check_still_reward`: a reward the player's pockets couldn't take last time.
func _check_still_reward() -> int:
	for i: int in _regist.size():
		var q: Dictionary = _regist[i]["quest"]
		if bool(q.get("give_reward", false)) and _regist[i]["to"] == _client() and _regist_player(i):
			return i
	return -1


func _regist_player(i: int) -> bool:
	var q: Dictionary = _regist[i]["quest"]
	if int(q["type"]) == VillagerQuests.Type.CONTEST:
		return bool(q.get("player", false))
	return true


## `aQMgr_actor_check_own_quest`.
func _check_own(to: bool) -> int:
	for i: int in _regist.size():
		if _regist[i]["to" if to else "from"] == _client():
			return i
	return -1


## `aQMgr_actor_check_errand_from`: a chain that started with this villager.
func _check_errand_from() -> int:
	for i: int in _regist.size():
		var q: Dictionary = _regist[i]["quest"]
		if int(q["type"]) == VillagerQuests.Type.ERRAND and int(q["kind"]) == VillagerQuests.ERRAND_REQUEST_CONTINUE:
			if (q["used_ids"] as Array)[0] == _client():
				return i
	return -1


## `aQMgr_actor_check_finish` with the contest `l_contest_check` procs.
func _check_finish(entry: Dictionary) -> bool:
	var q: Dictionary = entry["quest"]
	if int(q["type"]) != VillagerQuests.Type.CONTEST:
		return int(q["progress"]) == 0
	var progress: int = int(q["progress"])
	match int(q["kind"]):
		VillagerQuests.CONTEST_FRUIT:
			return progress == 1 and _pocket_of(q["requested"]) != -1
		VillagerQuests.CONTEST_SOCCER:
			return progress == 1
		VillagerQuests.CONTEST_SNOWMAN:
			return progress == 1 and bool(q["player"])
		VillagerQuests.CONTEST_FLOWER:
			return _check_flower(q)
		VillagerQuests.CONTEST_FISH:
			return progress == 1 and not bool(q["player"]) and _pocket_of_category(ItemData.Category.FISH) != -1
		VillagerQuests.CONTEST_INSECT:
			return progress == 1 and not bool(q["player"]) and _pocket_of_category(ItemData.Category.BUG) != -1
		VillagerQuests.CONTEST_LETTER:
			return progress == 1
	return false


## `aQMgr_actor_check_flower`: enough flowers by the house; a shortfall forgets who planted.
func _check_flower(q: Dictionary) -> bool:
	if int(q["progress"]) != 1:
		return false
	var seed_num: int = int(_home_counts().get("seed", -1))
	if seed_num < 0:
		return false
	if int(q["flowers_requested"]) <= seed_num:
		return true
	q["player"] = false
	q["player_name"] = ""
	return false


## `aQMgr_talk_common_regist_set_target`.
func _set_target_from_regist() -> void:
	var e: Dictionary = _regist[_regist_idx]
	var q: Dictionary = e["quest"]
	_target["info"]["type"] = int(q["type"])
	_target["info"]["kind"] = int(q["kind"])
	_target["set_data"] = VillagerQuests.set_data(int(q["type"]), int(q["kind"]))
	_target["quest_item"] = e["item"]
	_target["to"] = e["to"]
	_target["from"] = e["from"]


## `aQMgr_talk_common_get_item_idx`.
func _get_item_idx() -> int:
	if _regist_idx < 0 or _regist_idx >= _regist.size():
		return -1
	var e: Dictionary = _regist[_regist_idx]
	var q: Dictionary = e["quest"]
	match int(q["type"]):
		VillagerQuests.Type.DELIVERY:
			return int(e["idx"])
		VillagerQuests.Type.ERRAND:
			return int(q["pocket"])
		VillagerQuests.Type.CONTEST:
			match int(q["kind"]):
				VillagerQuests.CONTEST_FISH:
					return _pocket_of_category(ItemData.Category.FISH)
				VillagerQuests.CONTEST_INSECT:
					return _pocket_of_category(ItemData.Category.BUG)
				_:
					return _pocket_of(q["requested"])
	return -1


## ---------------------------------------------------------------- new quests

## `aQMgr_actor_new_quest`. Returns the regist index the quest came from (errand renewals).
func _new_quest(regist_idx: int) -> int:
	var quest: Dictionary = {}
	var stage: int = 0
	var exist: bool
	var sel: int = -1
	if regist_idx != -1:
		var e: Dictionary = _regist[regist_idx]
		quest = e["quest"]
		_target["info"]["type"] = int(quest["type"])
		var slot_idx: int = int(e["idx"])
		var next: int = errand_next[slot_idx] if slot_idx >= 0 and slot_idx < errand_next.size() else 0
		var next_type: int = 0
		if next == 0:
			next_type = _rand(2)
		elif next <= 2:
			next_type = next - 1
		_set_errand_next(slot_idx, next_type + 1)
		stage = 0 if next_type == 0 else int(quest["progress"]) - 1
		_target["info"]["kind"] = (
			VillagerQuests.ERRAND_REQUEST_FINAL if stage == 0 else VillagerQuests.ERRAND_REQUEST_CONTINUE
		)
		_target["free"] = quest
		_target["free_idx"] = slot_idx
		sel = regist_idx
		exist = true
	else:
		exist = _decide_quest()
	var result: int = NewQuest.ERROR
	if exist:
		_target["set_data"] = VillagerQuests.set_data(int(_target["info"]["type"]), int(_target["info"]["kind"]))
		result = _set_quest_data(quest)
		if result == NewQuest.SUCCESS:
			if regist_idx != -1:
				_target["from"] = _client()
				if stage != 0:
					_target["info"]["progress"] = stage
				_set_errand_next(int(_regist[regist_idx]["idx"]), 0)
		elif result == NewQuest.NO_SPACE:
			if int(_target["info"]["type"]) == VillagerQuests.Type.DELIVERY:
				talk_info.set_client_quest(slot, _target["info"])
			step = Step.FULL_ITEM_OR_NORMAL
		else:
			exist = false
	if not exist:
		if int(talk_info.client_quest(slot).get("type", VillagerQuests.Type.NONE)) != VillagerQuests.Type.NONE:
			step = Step.FULL_ITEM_OR_NORMAL
		elif int(_target["info"]["type"]) == VillagerQuests.Type.DELIVERY and (_target["set_data"] as Array).is_empty():
			step = Step.FULL_ITEM_OR_NORMAL
			_target["set_data"] = VillagerQuests.set_data(int(_target["info"]["type"]), int(_target["info"]["kind"]))
		else:
			step = Step.NO_OR_NORMAL
			talk_info.set_quest_request_off(slot, looks)
		_target["info"] = VillagerQuests.new_base()
		_target["free"] = {}
		_target["free_idx"] = -1
	return sel


func _set_errand_next(idx: int, value: int) -> void:
	if idx >= 0 and idx < errand_next.size():
		errand_next[idx] = value


## `aQMgr_actor_decide_quest`: re-offer what was turned down, else a 3-in-4 chance of a new
## request that can happen right now.
func _decide_quest() -> bool:
	var client_info: Dictionary = talk_info.client_quest(slot)
	if int(client_info.get("type", VillagerQuests.Type.NONE)) != VillagerQuests.Type.NONE:
		VillagerQuests.copy_base(_target["info"], client_info)
		_get_free_quest(int(_target["info"]["type"]))
		if not (_target["free"] as Dictionary).is_empty():
			return true
		if int(_target["info"]["type"]) == VillagerQuests.Type.DELIVERY:
			talk_info.set_client_quest(slot, _target["info"])
		return false
	if _rand(4) == 0:
		return false
	var fj: bool = _first_job_active()
	var types: Array = FJ_KINDS if fj else QST_KINDS
	var type: int = _rand(types.size())
	var kinds: Array = types[type]
	var kind: int = int(kinds[_rand(kinds.size())])
	if not _check_occur(type, kind):
		return false
	_target["info"]["type"] = type
	_target["info"]["kind"] = kind
	_get_free_quest(type)
	if not (_target["free"] as Dictionary).is_empty():
		return true
	if type == VillagerQuests.Type.DELIVERY:
		talk_info.set_client_quest(slot, _target["info"])
	return false


## `aQMgr_actor_check_occur`: contests one at a time per town and by season; deliveries to
## other towns need a remembered foreigner / departed villager, which a single-town save
## never has (`stored_anm_id` / `last_removed_animal_id` stay empty).
func _check_occur(type: int, kind: int) -> bool:
	if type == VillagerQuests.Type.CONTEST:
		if quests.occured_contest_idx(kind) != -1:
			return false
		match kind:
			VillagerQuests.CONTEST_SNOWMAN:
				return (
					(month == 1 or (month == 2 and day <= 17) or (month == 12 and day >= 25))
					and Clock.hour >= 8 and Clock.hour <= 16
				)
			VillagerQuests.CONTEST_FLOWER:
				if not ((month == 2 and day >= 25) or (month >= 3 and month <= 8)):
					return false
				var counts: Dictionary = _home_counts()
				return int(counts.get("null", -1)) >= 4 and int(counts.get("flower", -1)) <= 20
			VillagerQuests.CONTEST_INSECT:
				return (month >= 3 and month <= 10) or (month == 11 and day <= 28)
		return true
	if type == VillagerQuests.Type.DELIVERY:
		return kind != VillagerQuests.DELIVERY_FOREIGN and kind != VillagerQuests.DELIVERY_REMOVE
	return true


## `aQMgr_actor_get_free_quest_p`.
func _get_free_quest(type: int) -> void:
	_target["free"] = {}
	_target["free_idx"] = -1
	match type:
		VillagerQuests.Type.DELIVERY:
			for i: int in quests.deliveries.size():
				if VillagerQuests.is_free(quests.deliveries[i]) and _pocket_empty(i):
					_target["inv_idx"] = i
					_target["free"] = quests.deliveries[i]
					_target["free_idx"] = i
					return
		VillagerQuests.Type.ERRAND:
			for i: int in quests.errands.size():
				if VillagerQuests.is_free(quests.errands[i]):
					_target["free"] = quests.errands[i]
					_target["free_idx"] = i
					return
		VillagerQuests.Type.CONTEST:
			if slot >= 0 and slot < quests.contests.size() and VillagerQuests.is_free(quests.contests[slot]):
				_target["free"] = quests.contests[slot]
				_target["free_idx"] = slot


## `aQMgr_actor_set_quest_data`: who it's for, what item, the pocket for it, the deadline.
func _set_quest_data(quest: Dictionary) -> int:
	var data: Array = _target["set_data"]
	if data.is_empty():
		return NewQuest.ERROR
	_target["from"] = _client()
	match int(data[0]):
		VillagerQuests.Target.RANDOM:
			var to: StringName = other_resident([_client()], _home_block(), true)
			if to == &"":
				return NewQuest.ERROR
			_target["to"] = to
		VillagerQuests.Target.RANDOM_EXCLUDED:
			var exclude: Array[StringName] = [&"", &"", &"", &""]
			if not quest.is_empty():
				for i: int in VillagerQuests.CHAIN_ANIMAL_NUM:
					exclude[i] = (quest["used_ids"] as Array)[i]
			exclude[VillagerQuests.CHAIN_ANIMAL_NUM] = _client()
			var to: StringName = other_resident(exclude, _home_block(), true)
			if to == &"":
				return NewQuest.ERROR
			_target["to"] = to
			_target["errand_type"] = VillagerQuests.ERRAND_TYPE_CHAIN
		VillagerQuests.Target.ORIGINAL_TARGET:
			_target["to"] = (quest["used_ids"] as Array)[0] if not quest.is_empty() else _client()
		VillagerQuests.Target.FOREIGN:
			return NewQuest.NO_FOREIGN_ID
		VillagerQuests.Target.LAST_REMOVE:
			return NewQuest.NO_REMOVE_ANIMAL_ID
		VillagerQuests.Target.CLIENT:
			_target["to"] = _client()
	match int(data[4]):
		VillagerQuests.ItemSrc.RANDOM:
			_target["quest_item"] = VillagerQuests.QUEST_ITEMS[_rand(VillagerQuests.QUEST_ITEMS.size())]
		VillagerQuests.ItemSrc.FRUIT:
			_target["quest_item"] = VillagerQuests.other_fruit(context.rng)
		VillagerQuests.ItemSrc.CLOTH:
			_target["quest_item"] = _decide_cloth(cloth_at_start)
		VillagerQuests.ItemSrc.CURRENT_ITEM:
			_target["quest_item"] = quest["item"] if not quest.is_empty() else FirstJob.DEFAULT_CLOTH_ID
		VillagerQuests.ItemSrc.NONE:
			_target["quest_item"] = &""
		_:
			return NewQuest.ERROR
	if bool(data[3]):
		var idx: int = _first_empty_pocket()
		if idx == -1:
			_target["inv_idx"] = -1
			return NewQuest.NO_SPACE
		_target["inv_idx"] = idx
	else:
		_target["inv_idx"] = -1
	var days: int = int(data[1])
	if days != 0:
		_target["limit"] = now_minute + days * 1440
		_target["info"]["limit_on"] = true
	else:
		_target["info"]["limit_on"] = false
	_target["info"]["progress"] = int(data[2])
	if int(_target["info"]["type"]) == VillagerQuests.Type.CONTEST and int(_target["info"]["kind"]) == VillagerQuests.CONTEST_FLOWER:
		## `aQMgr_actor_set_contest_work_data`: three more than grow there now.
		_target["flower_goal"] = int(_home_counts().get("seed", -1)) + VillagerQuests.FLOWER_GOAL_NUM
	return NewQuest.SUCCESS


## `aQMgr_actor_decide_cloth`: shop clothing other than `exclude`.
func _decide_cloth(exclude: StringName) -> StringName:
	var pool: Array[StringName] = []
	for id: StringName in ShopGoods.category_pool(ItemData.Category.CLOTH):
		if id != exclude:
			pool.append(id)
	if pool.is_empty():
		return FirstJob.DEFAULT_CLOTH_ID
	return pool[_rand(pool.size())]


## `aQMgr_actor_set_quest_info`: write the quest into its save slot, and the parcel into the
## pocket (flagged as a quest item).
func _set_quest_info() -> void:
	var free: Dictionary = _target["free"]
	if free.is_empty():
		return
	var info: Dictionary = _target["info"]
	var type: int = int(info["type"])
	VillagerQuests.copy_base(free, info)
	free["limit"] = int(_target["limit"])
	match type:
		VillagerQuests.Type.DELIVERY:
			free["from"] = _client()
			free["to"] = _target["to"]
		VillagerQuests.Type.ERRAND:
			free["from"] = _client()
			free["to"] = _target["to"]
			free["item"] = _target["quest_item"]
			free["pocket"] = int(_target["inv_idx"])
			free["errand_type"] = int(_target["errand_type"])
			if int(_target["errand_type"]) == VillagerQuests.ERRAND_TYPE_CHAIN:
				var used: Array = free["used_ids"]
				if int(info["kind"]) == VillagerQuests.ERRAND_REQUEST:
					free["used_ids"] = [&"", &"", &""]
					free["used_num"] = 0
					used = free["used_ids"]
				for i: int in used.size():
					if used[i] == &"":
						used[i] = _client()
						break
				free["used_num"] = int(free["used_num"]) + 1
		VillagerQuests.Type.CONTEST:
			free["owner"] = _client()
			free["requested"] = _target["quest_item"]
			if int(info["kind"]) == VillagerQuests.CONTEST_FLOWER:
				free["flowers_requested"] = int(_target["flower_goal"])
			elif int(info["kind"]) == VillagerQuests.CONTEST_LETTER:
				free["letter_score"] = 0
				free["letter_present"] = &""
	var idx: int = int(_target["inv_idx"])
	if idx != -1 and inventory != null and _target["quest_item"] != &"":
		var s: InventorySlot = inventory.slot_at(idx)
		if s != null:
			s.set_stack(_target["quest_item"], 1)
			s.item.condition = InventoryItem.Condition.QUEST
			inventory.changed.emit()


## `aQMgr_actor_talk_finish`: a finished quest clears; a new one registers.
func _talk_finish() -> void:
	if _regist_idx >= 0 and _regist_idx < _regist.size():
		var q: Dictionary = _regist[_regist_idx]["quest"]
		match int(q["type"]):
			VillagerQuests.Type.DELIVERY:
				VillagerQuests.clear_delivery(q)
			VillagerQuests.Type.ERRAND:
				VillagerQuests.clear_errand(q)
			VillagerQuests.Type.CONTEST:
				VillagerQuests.clear_contest(q)
		_regist.clear()
		_regist_idx = -1


## ---------------------------------------------------------------- talk steps

## `aQMgr_actor_talk_new_quest_or_normal`: "Need any help?" → the request.
func _new_quest_or_normal() -> Dictionary:
	if _talk_action != 0:
		return _change_normal_or_hint()
	_finish_first_job_open_quest()
	step = Step.OCCUR_QUEST
	_msg_category = VillagerQuests.Msg.REQUEST_INIT
	if int(_target["info"]["type"]) == VillagerQuests.Type.CONTEST:
		## Contests start as soon as they're asked for — even if turned down.
		_set_quest_info()
		talk_info.clear_client_quest(slot)
	return _msg(_start_choices())


## `aQMgr_actor_talk_occur_quest`: accept (−), decline (−3 friendship), or cancel.
func _occur_quest() -> Dictionary:
	if _talk_action == 1:
		talk_info.set_client_quest(slot, _target["info"])
		_msg_category = VillagerQuests.Msg.REQUEST_REJECT
		if state != null:
			state.add_friendship(-3)
		return _msg()
	if _talk_action == 2:
		return _cancel_msg(CANCEL_MSG)
	_msg_category = VillagerQuests.Msg.REQUEST_END
	_set_quest_info()
	talk_info.clear_client_quest(slot)
	var free: Dictionary = _target["free"]
	var type: int = int(free.get("type", VillagerQuests.Type.NONE))
	if _talk_action == 0 and (type != VillagerQuests.Type.ERRAND or int(free.get("progress", 0)) == 0):
		## `aQMgr_talk_quest_wait_talk`: hand the parcel over, then "please do your best".
		_msg()
		_msg_category = VillagerQuests.Msg.REQUEST_END
		_talk_finish()
		step = Step.CHANGE_WAIT
		var out: Dictionary = _msg()
		if int(_target["inv_idx"]) != -1:
			out = _with_anim(out, "give", _target["quest_item"])
		return out
	if _talk_action == 0:
		step = Step.FINISH
	return _msg()


## `aQMgr_actor_talk_renew_errand_or_normal`: "I'm picking up!" → the chain moves on.
func _renew_errand_or_normal() -> Dictionary:
	if _talk_action != 0:
		return _change_normal_or_hint()
	_msg_category = VillagerQuests.Msg.REQUEST_INIT
	_set_quest_info()
	talk_info.clear_client_quest(slot)
	_regist.clear()
	_regist_idx = -1
	var free: Dictionary = _target["free"]
	if int(free.get("type", VillagerQuests.Type.NONE)) == VillagerQuests.Type.ERRAND and int(free.get("progress", 0)) == 0:
		step = Step.RENEW_ERRAND_IRAI_END_GIVE_ITEM
	else:
		step = Step.RENEW_ERRAND_IRAI_END
	return _msg(_start_choices())


## `aQMgr_actor_talk_giveup`: after "give it back", open the pockets on the parcel.
func _giveup() -> Dictionary:
	var idx: int = int(_target.get("inv_idx", -1))
	if idx == -1:
		step = Step.DONE
		return {}
	step = Step.GIVEUP_ITEM
	return {"hand": {"pocket": idx, "mode": "quest"}}


## `aQMgr_talk_quest_open_menu`: fish / bug contests take any fish / bug; the rest only the
## quest item.
func _open_menu() -> Dictionary:
	step = Step.GET_ITEM
	var info: Dictionary = _target["info"]
	var mode: String = "quest"
	if int(info["type"]) == VillagerQuests.Type.CONTEST:
		if int(info["kind"]) == VillagerQuests.CONTEST_FISH:
			mode = "fish"
		elif int(info["kind"]) == VillagerQuests.CONTEST_INSECT:
			mode = "insect"
	return {"hand": {"pocket": int(_target["inv_idx"]), "mode": mode}}


## The pockets closed on a quest hand-over (`aQMgr_talk_quest_get_item` /
## `aQMgr_talk_quest_giveup_item`). `item` is what was handed over, or `&""`.
func hand_result(item: StringName, pocket: int = -1) -> Dictionary:
	var handed: bool = item != &""
	if handed:
		_take_from_pocket(item, pocket if pocket >= 0 else int(_target.get("inv_idx", -1)))
	if step == Step.GIVEUP_ITEM:
		if not handed:
			_category_start = THIEF_MSG
			step = Step.GIVEUP
			return _msg()
		_msg_category = VillagerQuests.Msg.FAILURE_END
		var data: Array = _target["set_data"]
		if not data.is_empty() and state != null:
			match VillagerQuests.set_msg(data, VillagerQuests.Msg.FAILURE_END):
				0x2B8:
					state.add_friendship(-5)
				0x452:
					state.add_friendship(-2)
				0x2CA:
					state.add_friendship(-1)
		var out: Dictionary = _msg()
		## `aQMgr_talk_quest_giveup_npc_item`.
		_talk_finish()
		step = Step.CHANGE_WAIT
		return _with_anim(out, "take", item)
	## GET_ITEM.
	if not handed:
		_category_start = NO_REWARD_MSG
		step = Step.CHANGE_WAIT
		if state != null:
			state.add_friendship(-1)
		return _msg()
	_msg_category = VillagerQuests.Msg.COMPLETE_INIT
	step = Step.FIN_QUEST_REWARD
	var data_item: ItemData = ItemCatalog.get_item(item)
	_set_free(2, _article_name(item))
	if data_item != null and data_item.category == ItemData.Category.CLOTH and state != null:
		## `Common_Set(npc_chg_cloth, …)`: the villager changes into what they were given.
		state.cloth_id = item
	return _with_anim(_msg(), "take", item)


## `aQMgr_actor_talk_fin_quest_reward`.
func _fin_quest_reward() -> Dictionary:
	var q: Dictionary = _regist[_regist_idx]["quest"] if _regist_idx >= 0 and _regist_idx < _regist.size() else {}
	_set_reward()
	if _hand_reward():
		_set_free_str_reward()
		if not q.is_empty() and int(q["type"]) == VillagerQuests.Type.CONTEST:
			var kind: int = mini(int(q["kind"]), VillagerQuests.CONTEST_LETTER)
			_category_start = int((CONTEST_REWARD_MSG[kind] as Array)[int(_target["reward_kind"])])
		else:
			_category_start = REWARD_MSG[int(_target["reward_kind"])]
		step = Step.FIN_QUEST_THANKS
		if state != null:
			state.add_friendship(3)
	else:
		_msg_category = VillagerQuests.Msg.REWARD_FULL_ITEM
		if not q.is_empty():
			q["give_reward"] = true
		_regist_idx = -1
		step = Step.CHANGE_WAIT
	if not q.is_empty() and int(q["type"]) == VillagerQuests.Type.CONTEST:
		if int(q["progress"]) != 0:
			q["progress"] = int(q["progress"]) - 1
			q["limit"] = int(q["limit"]) + 3 * 1440
			q["player"] = true
			q["player_name"] = context.player_name if context != null else ""
		_regist_idx = -1
	_talk_finish()
	return _msg()


## `aQMgr_actor_talk_after_reward`: the reward that didn't fit last time.
func _after_reward() -> Dictionary:
	var q: Dictionary = _regist[_regist_idx]["quest"] if _regist_idx >= 0 and _regist_idx < _regist.size() else {}
	_set_reward()
	if _hand_reward():
		_set_free_str_reward()
		var kind: int = int(_target["reward_kind"])
		_category_start = AFTER_REWARD_MSG[kind]
		if not q.is_empty() and int(q["type"]) == VillagerQuests.Type.CONTEST:
			var ck: int = int(q["kind"])
			if ck >= VillagerQuests.CONTEST_SOCCER and ck <= VillagerQuests.CONTEST_FLOWER:
				_category_start = int((AFTER_CONTEST_SWAP[ck - 1] as Array)[kind])
		step = Step.AFTER_REWARD_THANKS
	else:
		_msg_category = VillagerQuests.Msg.REWARD_FULL_ITEM2
		step = Step.CHANGE_WAIT
	return _msg()


## `aQMgr_talk_quest_contest_hoka_or_normal`.
func _contest_hoka_or_normal() -> Dictionary:
	if _talk_action != 0:
		return _change_normal_or_hint()
	var q: Dictionary = _regist[_regist_idx]["quest"]
	_finish_first_job_open_quest()
	_target["free"] = {}
	_set_free(12, str(q.get("player_name", "")))
	if int(q["kind"]) == VillagerQuests.CONTEST_LETTER and bool(q["player"]):
		_category_start = LETTER_FULL_MSG
	else:
		_category_start = _contest_hoka_msg(q)
		if int(q["kind"]) != VillagerQuests.CONTEST_LETTER:
			_talk_finish()
	step = Step.CHANGE_WAIT
	return _msg()


func _contest_hoka_msg(q: Dictionary) -> int:
	var kind: int = int(q["kind"])
	if kind == VillagerQuests.CONTEST_FLOWER and int(q["flowers_requested"]) > int(_home_counts().get("seed", -1)):
		return FLOWER_SHORT_MSG
	return CONTEST_HOKA_MSG[clampi(kind, 0, CONTEST_HOKA_MSG.size() - 1)]


## `aQMgr_actor_talk_finish_letter`: the reply is in the mailbox.
func _finish_letter() -> Dictionary:
	var q: Dictionary = _regist[_regist_idx]["quest"]
	_set_free(12, str(q.get("player_name", "")))
	_category_start = LETTER_THANKS_MSG if bool(q["player"]) else LETTER_OTHER_MSG
	var out: Dictionary = _msg()
	step = Step.CHANGE_WAIT
	_target["free"] = {}
	_talk_finish()
	return out


## `mQst_SendRemail`.
func _send_remail(q: Dictionary) -> bool:
	if not bool(q.get("player", false)) or not send_mail.is_valid():
		return false
	var mail: MailData = VillagerQuests.letter_reply(
		villager, int(q["letter_score"]), q["letter_present"] as StringName,
		context.player_name if context != null else ""
	)
	if mail == null:
		return false
	return bool(send_mail.call(mail))


## `aQMgr_talk_quest_finish_firstjob_open_quest`: during the job's "go ask for work" chore,
## asking a villager for work finishes it.
func _finish_first_job_open_quest() -> void:
	if Game == null or Game.first_job == null:
		return
	var job: FirstJob = Game.first_job
	if job.kind == FirstJob.Kind.OPEN and job.progress == FirstJob.PROGRESS_ACTIVE:
		job.mark_open_finished()


## ---------------------------------------------------------------- rewards

## `aQMgr_actor_set_reward`.
func _set_reward() -> void:
	var percents: Array
	var base_pay: int
	if int(_target["info"]["type"]) == VillagerQuests.Type.ERRAND and _regist_idx >= 0 and _regist_idx < _regist.size():
		var r: Dictionary = VillagerQuests.errand_reward(int(_regist[_regist_idx]["quest"].get("used_num", 0)))
		percents = r["percents"]
		base_pay = int(r["pay"])
	else:
		var data: Array = _target["set_data"]
		percents = data[5] if not data.is_empty() else [0, 0, 0, 0, 0, 0, 0, 0]
		base_pay = int(data[6]) if not data.is_empty() else 0
	var table := PackedInt32Array()
	table.resize(100)
	table.fill(0)
	var j: int = 0
	for i: int in percents.size():
		for _p: int in int(percents[i]):
			if j >= 100:
				break
			table[j] = i
			j += 1
	var kind: int = table[_rand(100)]
	_target["reward_kind"] = kind
	match kind:
		VillagerQuests.Reward.MONEY:
			_target["pay"] = VillagerQuests.pay(base_pay, money_power, context.rng)
			_target["reward_item"] = &"money_1000"
		VillagerQuests.Reward.WORN_CLOTH:
			if state != null and state.cloth_design >= 0:
				## `RSV_CLOTH` (an Able design): some other shirt instead.
				_target["reward_item"] = _decide_cloth(Game.cloth_id if Game != null else &"")
				_target["reward_kind"] = VillagerQuests.Reward.CLOTH
			else:
				_target["reward_item"] = cloth_at_start
		_:
			_target["reward_item"] = _goods_for_reward(kind)


## `mQst_GetGoods_common`: furniture is 1-in-10 something from the villager's own room.
func _goods_for_reward(kind: int) -> StringName:
	match kind:
		VillagerQuests.Reward.FTR:
			if _rand(10) == 0:
				var own: StringName = npc_furniture(villager.id if villager != null else &"", context.rng)
				if own != &"":
					return own
			return _pick_pool(ShopGoods.furniture_pool())
		VillagerQuests.Reward.STATIONERY:
			return ShopGoods.PAPER
		VillagerQuests.Reward.CLOTH:
			return _pick_pool(ShopGoods.category_pool(ItemData.Category.CLOTH))
		VillagerQuests.Reward.CARPET:
			return _pick_pool(ShopGoods.category_pool(ItemData.Category.FLOOR))
		VillagerQuests.Reward.WALLPAPER:
			return _pick_pool(ShopGoods.category_pool(ItemData.Category.WALL))
	return &""


func _pick_pool(pool: Array[StringName]) -> StringName:
	return pool[_rand(pool.size())] if not pool.is_empty() else &""


## `mNpc_GetNpcFurniture`: a random piece from the villager's room.
static func npc_furniture(villager_id: StringName, rng: RandomNumberGenerator) -> StringName:
	var placements: Array = InteriorCatalogNpc._layout(villager_id).get("placements", []) as Array
	var ids: Array[StringName] = []
	for raw: Variant in placements:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var visual := StringName(str((raw as Dictionary).get("visual_id", "")))
		var data: FurnitureData = ItemCatalog.furniture_for_visual(visual) if visual != &"" else null
		if data != null:
			ids.append(data.id)
	if ids.is_empty():
		return &""
	return ids[rng.randi_range(0, ids.size() - 1)]


## `aQMgr_actor_hand_reward`: bells into the wallet (30,000-bell bags past the cap), goods
## into the parcel's pocket or the first free one.
func _hand_reward() -> bool:
	if inventory == null:
		return false
	var kind: int = int(_target["reward_kind"])
	var idx: int = int(_target.get("inv_idx", -1))
	if kind == VillagerQuests.Reward.MONEY:
		var money: int = inventory.wallet + int(_target["pay"])
		if money <= Inventory.WALLET_MAX:
			inventory.set_wallet(money)
			inventory.changed.emit()
			return true
		if money > Inventory.WALLET_MAX + _empty_pockets() * 30000:
			return false
		if idx != -1 and _pocket_empty(idx):
			inventory.slot_at(idx).set_stack(MONEY_30000, 1)
			money -= 30000
		while money > Inventory.WALLET_MAX:
			var empty: int = _first_empty_pocket()
			if empty == -1:
				money = Inventory.WALLET_MAX
				break
			inventory.slot_at(empty).set_stack(MONEY_30000, 1)
			money -= 30000
		inventory.set_wallet(money)
		inventory.changed.emit()
		return true
	if kind == -1 or _target["reward_item"] == &"":
		return false
	if idx == -1 or not _pocket_empty(idx):
		idx = _first_empty_pocket()
	if idx == -1:
		return false
	inventory.slot_at(idx).set_stack(_target["reward_item"], 1)
	inventory.changed.emit()
	return true


## `aQMgr_actor_set_free_str_reward`.
func _set_free_str_reward() -> void:
	if int(_target["reward_kind"]) == VillagerQuests.Reward.MONEY:
		_set_free(9, str(int(_target["pay"])))
	else:
		_set_item_text(0, _article_name(_target["reward_item"]))


## ---------------------------------------------------------------- strings & choices

## `aQMgr_actor_set_free_str`: FREE0 who asked, FREE1 who it's for, FREE2 the item,
## FREE3/4 their towns, FREE5 who started the errand chain.
func _set_free_str(regist_idx: int) -> void:
	_set_free(0, _name_of(_target["from"]))
	if _target["to"] != &"":
		_set_free(1, _name_of(_target["to"]))
		_set_free(3, context.town_name if context != null else "")
	if _target["quest_item"] != &"":
		_set_free(2, _article_name(_target["quest_item"]))
	_set_free(4, context.town_name if context != null else "")
	if regist_idx >= 0 and regist_idx < _regist.size():
		var q: Dictionary = _regist[regist_idx]["quest"]
		if int(q["type"]) == VillagerQuests.Type.ERRAND:
			var first: StringName = (q["used_ids"] as Array)[0]
			if first != &"":
				_set_free(5, _name_of(first))


func _name_of(id: StringName) -> String:
	var v: VillagerData = VillagerCatalog.get_villager(id)
	return v.display_name if v != null else ""


## Item strings carry their article (`mIN_get_item_article`).
func _article_name(item_id: StringName) -> String:
	var data: ItemData = ItemCatalog.get_item(item_id)
	var name: String = data.display_name if data != null else String(item_id)
	if data is FurnitureData or name == "":
		return name
	return PoliceTalk.with_article(name)


## `aQMgr_talk_quest_select_get_choice` for the step `_select_talk` landed on.
func _quest_choices() -> Array[String]:
	var info: Dictionary = _target.get("info", {})
	var type: int = int(info.get("type", VillagerQuests.Type.NONE))
	var kind: int = int(info.get("kind", 0))
	var first: int
	var second: int
	match step:
		Step.RENEW_ERRAND_OR_NORMAL:
			first = CHOICE_PICKUP
			second = CHOICE_TALK
		Step.FIN_QUEST_START:
			first = CHOICE_DELIVERY
			if type == VillagerQuests.Type.DELIVERY and kind in [VillagerQuests.DELIVERY_FOREIGN, VillagerQuests.DELIVERY_REMOVE]:
				first = CHOICE_FORGOT
			elif type == VillagerQuests.Type.ERRAND and kind != VillagerQuests.ERRAND_REQUEST_FINAL:
				first = CHOICE_PICKUP
			elif type == VillagerQuests.Type.CONTEST:
				match kind:
					VillagerQuests.CONTEST_FRUIT:
						first = CHOICE_FRUIT
					VillagerQuests.CONTEST_FISH:
						first = CHOICE_FISH
					VillagerQuests.CONTEST_INSECT:
						first = CHOICE_BUG
			second = _choice_rand(CHOICE_TALK, 10)
		Step.FIN_QUEST_START_NOT_HAND:
			first = CHOICE_BALL
			if kind == VillagerQuests.CONTEST_SNOWMAN:
				first = CHOICE_SNOWMAN
			elif kind == VillagerQuests.CONTEST_FLOWER:
				first = CHOICE_FLOWERS
			second = CHOICE_UM
		Step.FULL_ITEM_OR_NORMAL:
			first = CHOICE_PICKUP if type == VillagerQuests.Type.ERRAND else _choice_rand(CHOICE_HELP, 10)
			second = _choice_rand(CHOICE_TALK, 10)
		_:
			first = _choice_rand(CHOICE_HELP, 10)
			second = _choice_rand(CHOICE_TALK, 10)
	return _labels([first, second, _choice_rand(CHOICE_NEVERMIND, 5)])


## `aQMgr_talk_quest_start_choice`.
func _start_choices() -> Array[String]:
	return _labels([_choice_rand(CHOICE_ACCEPT, 10), _choice_rand(CHOICE_REJECT, 10)])


func _choice_rand(start: int, count: int) -> int:
	return start + _rand(count)


func _labels(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in ids:
		out.append(DialogueCatalog.choice_label(int(id)))
	return out


## `aQMgr_talk_quest_set_cancel_msg_com`.
func _cancel_msg(base: int) -> Dictionary:
	_msg_category = VillagerQuests.Msg.NONE
	_category_start = base
	step = Step.CHANGE_WAIT
	return _msg()


## `aQMgr_talk_common_set_msg_no`: a set data message or a fixed start, plus looks × 3 and
## 0–2 (except 0 and 15).
func _msg(choices: Array[String] = []) -> Dictionary:
	if _msg_category != VillagerQuests.Msg.NONE:
		_category_start = VillagerQuests.set_msg(_target.get("set_data", []), _msg_category)
	var base: int = _category_start
	var msg_no: int = base
	if base != 15 and base != 0:
		msg_no = _my_msg(base)
	_msg_category = VillagerQuests.Msg.NONE
	_category_start = 0
	var out: Dictionary = {"msg": msg_no}
	if not choices.is_empty():
		out["choices"] = choices
	return out


func _with_anim(out: Dictionary, kind: String, item: Variant) -> Dictionary:
	var id := StringName(str(item))
	if id != &"":
		out["anim"] = {kind: id}
	return out


## ---------------------------------------------------------------- helpers (quests)

func _client() -> StringName:
	return villager.id if villager != null else &""


func _home_block() -> Vector2i:
	if residents == null or slot < 0:
		return Vector2i(-1, -1)
	var home: Vector2i = residents.home_of(slot)
	if home == TownResidents.NO_HOME:
		return Vector2i(-1, -1)
	return VillagerWalk.block_from_cell(home)


func _home_counts() -> Dictionary:
	if field_counts.is_valid():
		return field_counts.call(_home_block()) as Dictionary
	return {}


## `mNpc_GetOtherAnimalPersonalIDOtherBlock`: a random resident not in `exclude` and (with
## `check_block`) not living in `block`. Kept as the decomp walks it, including neighbours in
## the block eating into the random index.
func other_resident(exclude: Array[StringName], block: Vector2i, check_block: bool) -> StringName:
	if residents == null:
		return &""
	if block.x < 0:
		check_block = false
	var count: int = exclude.size()
	var ids: int = count
	var live: Array[bool] = []
	for i: int in count:
		live.append(exclude[i] != &"")
		if not live[i]:
			ids -= 1
	var in_block: int = 0
	var blocks: Array[Vector2i] = []
	for j: int in TownResidents.ANIMAL_NUM_MAX:
		var b := Vector2i(-2, -2)
		if not residents.is_free(j) and residents.home_of(j) != TownResidents.NO_HOME:
			b = VillagerWalk.block_from_cell(residents.home_of(j))
		blocks.append(b)
	if check_block:
		for j: int in TownResidents.ANIMAL_NUM_MAX:
			if blocks[j] != block:
				continue
			in_block += 1
			var id: StringName = residents.slots[j].get("id", &"") as StringName
			for i: int in count:
				if live[i] and exclude[i] == id:
					ids -= 1
					live[i] = false
					break
	var npc_max: int = residents.animal_num()
	if npc_max <= ids + in_block or count >= TownResidents.ANIMAL_NUM_MAX:
		return &""
	var pick: int = _rand(npc_max - ids - in_block)
	for j: int in TownResidents.ANIMAL_NUM_MAX:
		if residents.is_free(j):
			continue
		var id: StringName = residents.slots[j]["id"] as StringName
		var other: int = 0
		for i: int in count:
			if live[i] and exclude[i] != id:
				other += 1
		var valid: bool = true
		if other != ids:
			valid = false
		elif check_block and blocks[j] == block:
			if pick > 0:
				pick -= 1
			valid = false
		if valid:
			if pick == 0:
				return id
			pick -= 1
	return &""


## `mNpc_GetNpcCloth`-ish: what the villager has on — a shirt they were given, else their own.
static func worn_cloth(v: VillagerData, s: VillagerState) -> StringName:
	if s != null and s.cloth_id != &"":
		return s.cloth_id
	if v != null and v.default_cloth >= 0:
		return StringName("shirt_%03d" % v.default_cloth)
	return FirstJob.DEFAULT_CLOTH_ID


func _pocket_empty(i: int) -> bool:
	if inventory == null:
		return false
	var s: InventorySlot = inventory.slot_at(i)
	return s != null and s.is_empty()


func _empty_pockets() -> int:
	var n: int = 0
	for i: int in Inventory.POCKET_SLOTS:
		if _pocket_empty(i):
			n += 1
	return n


## `mPr_GetPossessionItemIdx`.
func _pocket_of(item_id: StringName) -> int:
	if inventory == null or item_id == &"":
		return -1
	for i: int in Inventory.POCKET_SLOTS:
		var s: InventorySlot = inventory.slot_at(i)
		if s != null and not s.is_empty() and s.item.item_id == item_id:
			return i
	return -1


## `mPr_GetPossessionItemIdxItem1Category`.
func _pocket_of_category(category: int) -> int:
	if inventory == null:
		return -1
	for i: int in Inventory.POCKET_SLOTS:
		var s: InventorySlot = inventory.slot_at(i)
		if s == null or s.is_empty():
			continue
		var data: ItemData = ItemCatalog.get_item(s.item.item_id)
		if data != null and data.category == category:
			return i
	return -1


## The hand-over puts the item away (`mSM_IV_ITEM_PUT_AWAY`).
func _take_from_pocket(item: StringName, pocket: int) -> void:
	if inventory == null:
		return
	var idx: int = pocket
	var s: InventorySlot = inventory.slot_at(idx) if idx >= 0 else null
	if s == null or s.is_empty() or s.item.item_id != item:
		idx = _pocket_of(item)
		s = inventory.slot_at(idx) if idx >= 0 else null
	if s == null or s.is_empty():
		return
	if s.item.count > 1:
		s.item.count -= 1
	else:
		s.clear()
	inventory.changed.emit()
