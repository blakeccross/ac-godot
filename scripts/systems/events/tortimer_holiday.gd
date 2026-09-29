class_name TortimerHoliday
extends BankTalk

## Tortimer on a holiday (`ac_ev_soncho2`, `m_soncho.c`). Each holiday (`mSC_EVENT_*`) has
## ten messages from 0x3280 (`event * 10`; the Harvest Festival's start at 0x3391):
##
## 0/1 the day's greeting (1 if this year's calendar already has the day), then a
##     souvenir: 2 "pockets full" or 3 and the item (`mSC_trophy_item`), named in 4;
## 5 / 6–8 once the souvenir is yours (6–8 when talking again the same day);
## 9 for a visitor from another town.
## The souvenir comes once per holiday, ever (`soncho_trophy_field`).

## `mSC_EVENT_*` order → the calendar row that runs Tortimer for it.
const EVENTS: Array[StringName] = [
	&"soncho_new_years_day", &"soncho_founders_day", &"soncho_graduation_day",
	&"soncho_aprilfools_day", &"soncho_town_day", &"soncho_mothers_day", &"soncho_sale_day",
	&"soncho_cherry_blossom_festival", &"soncho_spring_sports_fair", &"soncho_nature_day",
	&"soncho_spring_cleaning", &"soncho_fathers_day", &"soncho_fishing_tourney_1",
	&"soncho_groundhog_day", &"soncho_explorers_day", &"soncho_fireworks_show", &"meteor_shower",
	&"harvest_moon_festival", &"soncho_mayors_day", &"soncho_officers_day",
	&"soncho_fall_sports_fair", &"soncho_halloween", &"soncho_fishing_tourney_2",
	&"soncho_snow_day", &"soncho_labor_day", &"soncho_toy_day", &"new_years_eve_countdown",
	&"soncho_harvest_festival",
]
const NEW_YEARS_DAY := 0
const TOWN_DAY := 4
const GROUNDHOG_DAY := 13
const TOY_DAY := 25
const NEW_YEARS_EVE := 26
const HARVEST_FESTIVAL := 27
const MSG_EVENTS := 0x3280
const MSG_EVENTS_COUNT := 10
const MSG_HARVEST_FESTIVAL := 0x3391
## `soncho_item_table` as furniture numbers (-1: worked out in `trophy_item`).
const TROPHY_FTR: Array[int] = [
	-1, 1056, 1057, 1184, -1, 1041, 1042, 1055, 1194, 1054, 1058, 1064, 1245, -1, 1008,
	1148, 1166, 1063, 1081, 1035, 1195, 1043, 1156, 1060, 1048, -1, 1263, 1261,
]
## `mRmTp_FtrIdx2FtrItemNo(0x4DE + RANDOM(9))`: the flower models.
const GROUNDHOG_FIRST := 0x4DE

var event: int = 0
## `mSC_trophy_get` / `mCD_calendar_event_check` store, `{"trophies": {event: true},
## "calendar": {event: year}}`.
var record: Dictionary = {}
var inventory: Inventory
var rng: RandomNumberGenerator
var female: bool = false
var item: StringName = &""
var _first_idx: int = -1


func _init(p_event: int, p_record: Dictionary, p_inventory: Inventory, p_rng: RandomNumberGenerator = null) -> void:
	event = p_event
	record = p_record
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()


static func event_index(id: StringName) -> int:
	return EVENTS.find(id)


## `aES2_kinenhin_msg`.
func msg_for(idx: int) -> int:
	if event == HARVEST_FESTIVAL:
		return MSG_HARVEST_FESTIVAL + idx
	return MSG_EVENTS + event * MSG_EVENTS_COUNT + idx


## `mSC_trophy_item`.
func trophy_item() -> StringName:
	match event:
		NEW_YEARS_DAY:
			## The off-by-one keeps the 16th diary out (`RANDOM(DIARY_NUM - 1)`).
			var diaries: Array[StringName] = FtrCatalog.list("ftr_diary")
			if diaries.size() > 1:
				return diaries[rng.randi_range(0, diaries.size() - 2)]
			return &"apple"
		TOY_DAY:
			return FtrCatalog.item_id(1065 if female else 1061)
		TOWN_DAY:
			return FtrCatalog.pick_named("ftr", "Train", rng)
		GROUNDHOG_DAY:
			return FtrCatalog.item_id(GROUNDHOG_FIRST + rng.randi_range(0, 8))
	var n: int = TROPHY_FTR[event] if event >= 0 and event < TROPHY_FTR.size() else -1
	return FtrCatalog.item_id(n) if n >= 0 else &"apple"


func _has_trophy() -> bool:
	return (record.get("trophies", {}) as Dictionary).has(str(event))


func _calendar_marked() -> bool:
	return int((record.get("calendar", {}) as Dictionary).get(str(event), -1)) == Clock.year


func prepare() -> void:
	item = trophy_item()
	var data: ItemData = ItemCatalog.get_item(item)
	context.set_item_str(0, PoliceTalk.with_article(data.display_name) if data != null else "")


## `aES2_set_norm_talk_info`, then `mCD_calendar_event_on`.
func start_msg() -> int:
	var marked: bool = _calendar_marked()
	var cal: Dictionary = record.get("calendar", {})
	cal[str(event)] = Clock.year
	record["calendar"] = cal
	if _has_trophy():
		_first_idx = 6 + rng.randi_range(0, 2) if marked else 5
	else:
		_first_idx = 1 if marked else 0
	return msg_for(_first_idx)


## `aES2_talk_before_give` → `aES2_talk_give`.
func next_step() -> Dictionary:
	if current_msg != msg_for(_first_idx) or _first_idx > 1:
		return {}
	if inventory == null or not inventory.has_space(1):
		return msg(msg_for(2))
	var data: ItemData = ItemCatalog.get_item(item)
	if data != null:
		inventory.add(data, 1)
	var trophies: Dictionary = record.get("trophies", {})
	trophies[str(event)] = true
	record["trophies"] = trophies
	return {"anim": {"give": item}, "msg": msg_for(3)}
