class_name PlayerState
extends Resource

## The playing resident's own saved state (`Private_c`): who they are and what they wear,
## where they stand, their sunburn, diary and calendar, the fortune of the day, and the
## letters and visits that come once a year. Held by `Game.resident`; the other residents'
## copies live in `PlayerRoster` slots. Saved under the same keys as before (`write_save` /
## `read_save`), so the JSON save format is unchanged.

const DEFAULT_SPAWN := Vector3(0.0, 0.1, 6.0)
const DEFAULT_PLAYER_NAME := "Player"
const DEFAULT_PLAYER_GENDER := &"male"

## `mPr_DESTINY_*`.
enum Destiny { NORMAL, POPULAR, UNPOPULAR, BAD_LUCK, MONEY_LUCK, GOODS_LUCK }

var player_position: Vector3 = DEFAULT_SPAWN
var player_yaw: float = 0.0
## `Private.sunburn`: {rank 0–8, changed (day number of the last change), hold (days)}.
var sunburn: Dictionary = {"rank": 0, "changed": -1, "hold": 0}
## The diary (`mCD_keep_diary_c`): month 1–12 → that month's page. Saved.
var diary: Dictionary = {}
## Worn original design display slot (`cloth.idx >= CLOTH_NUM+1`). -1 = normal shirt.
var worn_design_slot: int = -1
var player_name: String = DEFAULT_PLAYER_NAME
var player_gender: StringName = DEFAULT_PLAYER_GENDER
var player_face: int = 0
## Worn shirt (`Private_c.cloth.item`). Default `ITM_CLOTH001`.
var cloth_id: StringName = FirstJob.DEFAULT_CLOTH_ID
var destiny_type: int = Destiny.NORMAL
var destiny_date: Vector3i = Vector3i.ZERO
## Town map unlocked after first-job furniture delivery (`Common.map_flag`).
var has_map: bool = false
## `Private_c.reset_count`: sessions ended without saving (saved).
var reset_count: int = 0
## `Private_c.complete_fish_insect_flags` — see `CompleteTalk`.
var complete_flags: int = 0
## `Private_c.hint_count`: first-job hints villagers still owe (bit 7 = all given).
var first_job_hint_count: int = 0
## Year the Valentine's letters went out (`event_save_common.valentines_day_date`).
var valentine_year: int = 0
## `Private_c.celebrated_birthday_year` / `birthday_present_npc`: the year the birthday
## visit came, and who brought it (left out of that year's cards).
var celebrated_birthday_year: int = 0
var birthday_present_npc: StringName = &""
## `EventDates.ordinal` of the last birthday-card check (the last play date).
var birthday_card_day: int = 0
## Mom's letters (`mPr_mother_mail_info_c`): the last day checked and which went out. Saved.
var mother_mail: Dictionary = MotherMail.new_state()
## Tortimer's exercise card (`mPr_day_day_c radiocard`): last stamp date and stamps. Saved.
var radio_card: Dictionary = RadioCard.new_state()
## The calendar's played days and Tortimer days (`mCD_player_calendar_c`). Saved.
var calendar: Dictionary = CalendarBook.new_state()
## `mPr_FLAG_POSTOFFICE_GIFT0..3`: balance milestones already rewarded (`BankTerminal.GIFTS`).
var bank_gift_flags: int = 0
## The resident has met Blanca on a train before (`mPr_FLAG_1`: 0x33F3, not 0x33F2).
var met_blanca: bool = false
## `mPr_FLAG_MASK_CAT_SCHEDULED`: she rode the last trip home, so not this one.
var mask_cat_scheduled: bool = false
## `mPlib_Check_golden_item_get_demo_end(SHOVEL)`: the golden shovel's fanfare has played.
var golden_shovel_shown: bool = false
## `mPr_FLAG_MUSEUM_COMP_HANDBILL_*`: the museum-complete letter (`MuseumCompMail`). Saved.
var museum_comp_mail: int = 0


## Its keys of `Game.to_save()`, written into `out`.
func write_save(out: Dictionary) -> void:
	out["player"] = {
		"x": player_position.x,
		"y": player_position.y,
		"z": player_position.z,
		"yaw": player_yaw,
	}
	out["golden_shovel_shown"] = golden_shovel_shown
	out["museum_comp_mail"] = museum_comp_mail
	out["sunburn"] = sunburn.duplicate()
	out["diary"] = diary.duplicate()
	out["worn_design_slot"] = worn_design_slot
	out["player_name"] = player_name
	out["player_gender"] = String(player_gender)
	out["player_face"] = player_face
	out["cloth_id"] = String(cloth_id)
	out["destiny"] = {"type": int(destiny_type), "y": destiny_date.x, "m": destiny_date.y, "d": destiny_date.z}
	out["has_map"] = has_map
	out["reset_count"] = reset_count
	out["bank_gift_flags"] = bank_gift_flags
	out["complete_flags"] = complete_flags
	out["first_job_hint_count"] = first_job_hint_count
	out["valentine_year"] = valentine_year
	out["celebrated_birthday_year"] = celebrated_birthday_year
	out["birthday_present_npc"] = String(birthday_present_npc)
	out["birthday_card_day"] = birthday_card_day
	out["mother_mail"] = mother_mail.duplicate()
	out["radio_card"] = radio_card.duplicate()
	out["calendar"] = calendar.duplicate(true)
	out["met_blanca"] = met_blanca
	out["mask_cat_scheduled"] = mask_cat_scheduled


## Its part of a `Game.apply_snapshot` dictionary (missing keys take the defaults).
func read_save(data: Dictionary) -> void:
	var pose: Variant = data.get("player", {})
	if typeof(pose) == TYPE_DICTIONARY:
		var p: Dictionary = pose
		player_position = Vector3(
			float(p.get("x", DEFAULT_SPAWN.x)),
			float(p.get("y", DEFAULT_SPAWN.y)),
			float(p.get("z", DEFAULT_SPAWN.z))
		)
		player_yaw = float(p.get("yaw", 0.0))
	else:
		player_position = DEFAULT_SPAWN
		player_yaw = 0.0
	golden_shovel_shown = bool(data.get("golden_shovel_shown", false))
	museum_comp_mail = int(data.get("museum_comp_mail", 0))
	sunburn = {"rank": 0, "changed": -1, "hold": 0}
	var saved_tan: Variant = data.get("sunburn", {})
	if typeof(saved_tan) == TYPE_DICTIONARY:
		sunburn["rank"] = clampi(int((saved_tan as Dictionary).get("rank", 0)), 0, Sunburn.MAX_RANK)
		sunburn["changed"] = int((saved_tan as Dictionary).get("changed", -1))
		sunburn["hold"] = clampi(int((saved_tan as Dictionary).get("hold", 0)), 0, Sunburn.HOLD_DAYS)
	diary.clear()
	var saved_diary: Variant = data.get("diary", {})
	if typeof(saved_diary) == TYPE_DICTIONARY:
		for key: Variant in saved_diary:
			var m: int = int(key)
			if m >= 1 and m <= 12:
				diary[m] = DiaryOverlay.clip(str(saved_diary[key]))
	worn_design_slot = int(data.get("worn_design_slot", -1))
	first_job_hint_count = clampi(int(data.get("first_job_hint_count", 0)), 0, 0xFF)
	valentine_year = int(data.get("valentine_year", 0))
	celebrated_birthday_year = int(data.get("celebrated_birthday_year", 0))
	birthday_present_npc = StringName(str(data.get("birthday_present_npc", "")))
	birthday_card_day = int(data.get("birthday_card_day", 0))
	met_blanca = bool(data.get("met_blanca", false))
	mask_cat_scheduled = bool(data.get("mask_cat_scheduled", false))
	calendar = CalendarBook.new_state()
	var saved_cal: Variant = data.get("calendar", {})
	if typeof(saved_cal) == TYPE_DICTIONARY:
		for key: String in ["played", "events"]:
			var days: Array = []
			for n: Variant in (saved_cal as Dictionary).get(key, []):
				days.append(int(n))
			calendar[key] = days
	radio_card = RadioCard.from_save(data.get("radio_card", {}))
	mother_mail = MotherMail.new_state()
	var saved_mom: Variant = data.get("mother_mail", {})
	if typeof(saved_mom) == TYPE_DICTIONARY:
		for key: String in ["date", "normal", "monthly"]:
			mother_mail[key] = int((saved_mom as Dictionary).get(key, 0))
	player_name = str(data.get("player_name", DEFAULT_PLAYER_NAME))
	player_gender = IntroSequence.normalize_gender(data.get("player_gender", DEFAULT_PLAYER_GENDER))
	player_face = clampi(int(data.get("player_face", 0)), 0, IntroSequence.FACE_TYPE_NUM - 1)
	cloth_id = StringName(str(data.get("cloth_id", FirstJob.DEFAULT_CLOTH_ID)))
	var fortune: Dictionary = data.get("destiny", {})
	destiny_type = clampi(int(fortune.get("type", 0)), 0, Destiny.GOODS_LUCK)
	destiny_date = Vector3i(int(fortune.get("y", 0)), int(fortune.get("m", 0)), int(fortune.get("d", 0)))
	if cloth_id == &"":
		cloth_id = FirstJob.DEFAULT_CLOTH_ID
	has_map = bool(data.get("has_map", false))
	reset_count = maxi(int(data.get("reset_count", 0)), 0)
	bank_gift_flags = int(data.get("bank_gift_flags", 0)) & 0xF
	complete_flags = int(data.get("complete_flags", 0)) & 0xF


## A new town's values (`Game.reset_session`).
func reset() -> void:
	met_blanca = false
	mask_cat_scheduled = false
	destiny_type = Destiny.NORMAL
	destiny_date = Vector3i.ZERO
	first_job_hint_count = 0
	valentine_year = 0
	celebrated_birthday_year = 0
	birthday_present_npc = &""
	birthday_card_day = 0
	mother_mail = MotherMail.new_state()
	radio_card = RadioCard.new_state()
	calendar = CalendarBook.new_state()
	player_position = DEFAULT_SPAWN
	player_yaw = 0.0
	golden_shovel_shown = false
	museum_comp_mail = 0
	sunburn = {"rank": 0, "changed": -1, "hold": 0}
	diary.clear()
	player_name = DEFAULT_PLAYER_NAME
	player_gender = DEFAULT_PLAYER_GENDER
	player_face = 0
	cloth_id = FirstJob.DEFAULT_CLOTH_ID
	has_map = false
	reset_count = 0
	bank_gift_flags = 0
	complete_flags = 0
	worn_design_slot = -1
