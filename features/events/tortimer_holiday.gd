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
##
## His January / February vacation (`mSC_SPECIAL_EVENT_JAN/FEB_VACATION`) talks instead:
## the first talk hands out the lighthouse job (`mSC_LightHouse_Quest_Start`, the last
## night and his return day in FREE0 / FREE1); once it is out, one of three chat lines.

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
const NEW_YEARS_EVE_COUNTDOWN := 26
const HARVEST_FESTIVAL := 27
## `mSC_SPECIAL_EVENT_JAN_VACATION` / `_FEB_VACATION`.
const JAN_VACATION := 101
const FEB_VACATION := 102
const VACATIONS: Dictionary = {&"soncho_vacation_january": JAN_VACATION, &"soncho_vacation_february": FEB_VACATION}
const MSG_EVENTS := 0x3280
const MSG_EVENTS_COUNT := 10
const MSG_HARVEST_FESTIVAL := 0x3391
## `MSG_SONCHO_LIGHTHOUSE_1` / `_2`; +6..+8 once the job is out.
const MSG_LIGHTHOUSE_JAN := 0x33F4
const MSG_LIGHTHOUSE_FEB := 0x340B
## `soncho_item_table` as furniture numbers (-1: worked out in `trophy_item`).
const TROPHY_FTR: Array[int] = [
	-1, 1056, 1057, 1184, -1, 1041, 1042, 1055, 1194, 1054, 1058, 1064, 1245, -1, 1008,
	1148, 1166, 1063, 1081, 1035, 1195, 1043, 1156, 1060, 1048, -1, 1263, 1261,
]
## `mRmTp_FtrIdx2FtrItemNo(0x4DE + RANDOM(9))`: the flower models.
const GROUNDHOG_FIRST := 0x4DE
## `mSP_GetRandomStationToyItemNo`: `0x42A + RANDOM(15)`, the fifteen station models.
const STATION_TOY_FIRST := 0x42A
const STATION_TOY_COUNT := 15

var event: int = 0
## `mSC_trophy_get` / `mCD_calendar_event_check` store, `{"trophies": {event: true},
## "calendar": {event: year}}`.
var record: Dictionary = {}
var inventory: Inventory
var rng: RandomNumberGenerator
var female: bool = false
## The souvenir; set by his actor once a visit (`aES2_wait`: `soncho->item`), else picked
## in `prepare`.
var item: StringName = &""
## The vacation's lighthouse job (`Save_Get(LightHouse)`).
var lighthouse: LighthouseBook
## Today; `Vector3i.ZERO` reads the clock.
var today: Vector3i = Vector3i.ZERO
var _first_idx: int = -1


func _init(p_event: int, p_record: Dictionary, p_inventory: Inventory, p_rng: RandomNumberGenerator = null) -> void:
	event = p_event
	record = p_record
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()


static func event_index(id: StringName) -> int:
	if VACATIONS.has(id):
		return int(VACATIONS[id])
	return EVENTS.find(id)


static func is_vacation(p_event: int) -> bool:
	return p_event == JAN_VACATION or p_event == FEB_VACATION


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
			var diaries: Array[StringName] = FurnitureCatalog.list("ftr_diary")
			if diaries.size() > 1:
				return diaries[rng.randi_range(0, diaries.size() - 2)]
			return &"apple"
		TOY_DAY:
			return FurnitureCatalog.item_id(1065 if female else 1061)
		TOWN_DAY:
			return FurnitureCatalog.item_id(STATION_TOY_FIRST + rng.randi_range(0, STATION_TOY_COUNT - 1))
		GROUNDHOG_DAY:
			return FurnitureCatalog.item_id(GROUNDHOG_FIRST + rng.randi_range(0, 8))
	var n: int = TROPHY_FTR[event] if event >= 0 and event < TROPHY_FTR.size() else -1
	return FurnitureCatalog.item_id(n) if n >= 0 else &"apple"


func _date() -> Vector3i:
	return today if today != Vector3i.ZERO else Vector3i(Clock.year, Clock.month, Clock.day)


## The day the calendar marks (`soncho->year/month/day`): the countdown runs past midnight,
## and after it the day is still New Year's Eve (`aES2_wait`).
func event_date() -> Vector3i:
	var d: Vector3i = _date()
	if event == NEW_YEARS_EVE_COUNTDOWN and d.z != 31:
		return Vector3i(d.x - 1, 12, 31)
	return d


func _has_trophy() -> bool:
	return (record.get("trophies", {}) as Dictionary).has(str(event))


func _calendar_marked() -> bool:
	return int((record.get("calendar", {}) as Dictionary).get(str(event), -1)) == event_date().x


func prepare() -> void:
	if is_vacation(event):
		return
	if item == &"":
		item = trophy_item()
	var data: ItemData = ItemCatalog.get_item(item)
	context.set_item_str(0, PoliceTalk.with_article(data.display_name) if data != null else "")


## `aES2_set_norm_talk_info`, then `mCD_calendar_event_on`.
func start_msg() -> int:
	var day: Vector3i = event_date()
	if Game != null:
		CalendarBook.event_on(Game.resident.calendar, EventDates.ordinal(day.x, day.y, day.z))
	if is_vacation(event):
		return _vacation_msg()
	var marked: bool = _calendar_marked()
	var cal: Dictionary = record.get("calendar", {})
	cal[str(event)] = day.x
	record["calendar"] = cal
	if _has_trophy():
		_first_idx = 6 + rng.randi_range(0, 2) if marked else 5
	else:
		_first_idx = 1 if marked else 0
	return msg_for(_first_idx)


## `aES2_set_norm_talk_info` for the vacation, with `aES2_talk_init`'s quest start and
## `aES2_LightHouse_set_free_str` (the days a week and eight days on).
func _vacation_msg() -> int:
	var base: int = MSG_LIGHTHOUSE_JAN if event == JAN_VACATION else MSG_LIGHTHOUSE_FEB
	var d: Vector3i = _date()
	var now: int = EventDates.ordinal(d.x, d.y, d.z)
	if lighthouse == null or lighthouse.talk_after_check(now):
		return base + 6 + rng.randi_range(0, 2)
	lighthouse.start_quest(d.x, d.y, d.z)
	set_free(0, _day_string(now + 7))
	set_free(1, _day_string(now + 8))
	return base


## `mString_Load_DayStringFromRom`: "22nd".
static func _day_string(ordinal: int) -> String:
	var day: int = EventDates.from_ordinal(ordinal).z
	return DialogueCatalog.rom_string(NoticeBoard.STRING_DAY_START + clampi(day, 1, 31) - 1)


## `aES2_talk_before_give` → `aES2_talk_give`.
func next_step() -> Dictionary:
	if is_vacation(event) or current_msg != msg_for(_first_idx) or _first_idx > 1:
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
