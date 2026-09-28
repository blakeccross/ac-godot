class_name VillagerTalkManager
extends RefCounted

## What a villager says after the greeting (`ac_quest_manager.c`, `ac_quest_talk_init.c`,
## `ac_quest_talk_normal_init.c`). `DialogueRunner` asks `next_step` when a message ends,
## `choose` when the player picks from a menu this class put up, and `order` for every quest
## demo order a message carries (`mDemo_ORDER_QUEST`, `aQMgr_talk_normal_demo_order`).
##
## Flow for a town villager (quests are not ported yet, so `aQMgr_actor_talk_select_talk`
## always lands on `aQMgr_TALK_STEP_NO_OR_NORMAL`):
##   greeting → "So, what's up?" (`0x2A6`) with "Need any help? / Let's talk! / Never mind"
##     0: "Nothing much going on" (`0x282`)
##     1: friendship +1, then a normal-talk topic (`aQMgr_talk_normal_select_talk`)
##     2: "Oh. All right." (`0x254A`)
## A step returns `{}` to end the talk, or `{"msg": msg_no, "choices": [labels]}`.

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

enum Step { SELECT, NO_OR_NORMAL, NORMAL, DONE }

## `manager->last_strings`: last picks of `aQMgr_order_set_string_1` / `_4` so a topic
## doesn't repeat its word twice running. Lives as long as the quest manager actor.
static var last_strings := PackedInt32Array([255, 255, 255, 255, 255, 255, 255])

var villager: VillagerData
var state: VillagerState
var context: DialogueContext
var inventory: Inventory
var looks: int = 0
var slot: int = -1
var step: Step = Step.SELECT
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


## The greeting (or the last message) ended.
func next_step() -> Dictionary:
	match step:
		Step.SELECT:
			return _select_talk()
		_:
			step = Step.DONE
			return {}


## The player picked `index` from the menu `next_step` put up.
func choose(index: int) -> Dictionary:
	match step:
		Step.NO_OR_NORMAL:
			return _no_or_normal(index)
		_:
			step = Step.DONE
			return {}


## `aQMgr_actor_talk_select_talk`, quest-less branch → `aQMgr_TALK_STEP_NO_OR_NORMAL`.
func _select_talk() -> Dictionary:
	step = Step.NO_OR_NORMAL
	return {"msg": _my_msg(SELECT_TALK_MSG), "choices": _select_choices()}


## `aQMgr_talk_quest_select_get_choice` (default arm).
func _select_choices() -> Array[String]:
	var out: Array[String] = []
	for group: Array in [[CHOICE_HELP, 10], [CHOICE_TALK, 10], [CHOICE_NEVERMIND, 5]]:
		out.append(DialogueCatalog.choice_label(int(group[0]) + _rand(int(group[1]))))
	return out


## `aQMgr_actor_talk_no_or_normal` / `aQMgr_talk_quest_change_normal_or_hint`.
func _no_or_normal(index: int) -> Dictionary:
	match index:
		0:
			step = Step.DONE
			return {"msg": _my_msg(NO_WORK_MSG)}
		2:
			step = Step.DONE
			return {"msg": _my_msg(CANCEL_MSG)}
		_:
			if state != null:
				state.add_friendship(1)
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
	## `aQMgr_decide_msg_ev`: special visitors and calendar rumours aren't tracked yet, so
	## both come back -1 and the hint line is left.
	decide_idx_prob_table(EV_PROB)
	return GAME_HINT[looks] + _rand(5)


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


## `aQMgr_order_set_calendar`: lunar-calendar dates (harvest moon 8/15, 9/13 and today's
## lunar date). `lbRk_ToSeiyouReki` isn't ported; the lunar dates stay as the raw month/day.
func _order_set_calendar(value: int) -> void:
	if value != 1:
		return
	_set_free(11, _month_name(8))
	_set_free(12, str(15))
	_set_free(13, _month_name(9))
	_set_free(14, str(13))
	if context != null:
		_set_free(15, _month_name(context.month))
		_set_free(16, str(context.day))


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
