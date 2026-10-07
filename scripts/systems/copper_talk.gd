class_name CopperTalk
extends RefCounted

## Copper's conversations (`ac_npc_police_move.c_inc`): the greeting as you walk out of
## the police box (0x0771), and the time-of-day greeting menu (0x0772–0x0775) whose three
## answers are the special-event hint (`aPOL_get_hint_msg_no`), the lost-and-found count
## (0x0782 / 0x0783) and "never mind" (0x0777). A visitor from another town gets the map
## option first (`aPOL_check_select2` → `mPr_SetNewMap`, 0x18CA).

const CONVERSATION_ID := &"copper_talk"
const MSG_EXIT_GREETING := 0x0771
const VAR_ENTRY := "copper_entry"
const VAR_TIME := "copper_time"
const VAR_HINT := "copper_hint"
const VAR_LOST := "copper_lost"

enum Special { UNSCHEDULED, LATER, TODAY, ACTIVE }

## `aPOL_set_norm_talk_info_talk_request`: before 05:00 / 10:00 / 17:00 / after.
const TIME_MSGS: Array[int] = [0x0772, 0x0773, 0x0774, 0x0775]
const TIME_KEYS: Array[String] = ["morning", "day", "evening", "night"]

## `aPOL_get_hint_msg_no` tables, indexed `event − mEv_EVENT_ARTIST`.
const HINT_ORDER: Array[StringName] = [
	&"artist", &"broker_sale", &"designer", &"gypsy", &"shop_sale", &"carpet_peddler"
]
const HINT_RUN: Array[int] = [0x2C24, 0x2C23, 0x2C22, 0x2C26, 0x2C21, 0x2C25]
const HINT_TODAY: Array[int] = [0x2C34, 0x2C33, 0x2C32, 0x2C36, 0x2C31, 0x2C35]
const HINT_LATER: Array[int] = [0x2C2A, 0x2C29, 0x2C28, 0x2C2C, 0x2C27, 0x2C2B]
const HINT_FIRST_JOB := 0x2C2D
const HINT_NONE := 0x2C37
const MSG_LOST_SOME := 0x0782
const MSG_LOST_NONE := 0x0783
const MSG_NEVER_MIND := 0x0777


static func time_index(hour: int) -> int:
	if hour < 5:
		return 3
	if hour < 10:
		return 0
	if hour < 17:
		return 1
	return 2


## `mEv_get_special_event_state`. A shop sale only reads as running during its start
## hour (the original compares month, day *and* hour); the others use the live flag.
static func special_state(events: EventCalendar, month: int, day: int, hour: int) -> Special:
	if events == null or events.special_type == &"":
		return Special.UNSCHEDULED
	var start_md: int = int(events.special_dates.get("special1", 0))
	var start_hour: int = int(events.special_dates.get("special3", 0))
	var today_md: int = EventDates.md(month, day)
	if events.special_type == &"shop_sale":
		if start_md == today_md and start_hour == hour:
			return Special.ACTIVE
	elif events.is_active(events.special_type):
		return Special.ACTIVE
	if start_md == today_md and hour <= start_hour:
		return Special.TODAY
	if start_md > today_md:
		return Special.LATER
	return Special.UNSCHEDULED


## Message number and graph key for the event hint.
static func hint(events: EventCalendar, first_job_active: bool, month: int, day: int, hour: int) -> Dictionary:
	if first_job_active:
		return {"msg": HINT_FIRST_JOB, "key": "first_job"}
	var state: Special = special_state(events, month, day, hour)
	var idx: int = HINT_ORDER.find(events.special_type) if events != null else -1
	if state == Special.UNSCHEDULED or idx < 0:
		return {"msg": HINT_NONE, "key": "none"}
	match state:
		Special.ACTIVE:
			## Anyone but the sale needs `mEv_get_event_place`; no visitor is placed in
			## town yet, so this takes the original's not-found answer.
			if events.special_type == &"shop_sale":
				return {"msg": HINT_RUN[idx], "key": "run_sale"}
			return {"msg": HINT_NONE, "key": "none"}
		Special.TODAY:
			return {"msg": HINT_TODAY[idx], "key": "today"}
		_:
			return {"msg": HINT_LATER[idx], "key": "later"}


## Fill the talk context: which greeting, which hint, the lost-and-found count.
## free0 = kept item count, free1 = visitor / event name, free4 = start day,
## free5 = start month (`aPOL_set_event_day_str`).
static func fill(ctx: DialogueContext, exit_greeting: bool) -> void:
	if ctx == null:
		return
	ctx.set_var(VAR_ENTRY, "exit" if exit_greeting else "menu")
	ctx.set_var("copper_foreign", "yes" if Game != null and Game.foreigner else "no")
	ctx.set_var(VAR_TIME, TIME_KEYS[time_index(ctx.hour)])
	var events: EventCalendar = Game.events if Game != null else null
	var first_job: bool = Game != null and Game.first_job != null and Game.first_job.is_active()
	var h: Dictionary = hint(events, first_job, ctx.month, ctx.day, ctx.hour)
	ctx.set_var(VAR_HINT, str(h["key"]))
	var sum: int = Game.police.keep_item_sum() if Game != null and Game.police != null else 0
	ctx.set_var(VAR_LOST, "some" if sum > 0 else "none")
	var frees := PackedStringArray(["", "", "", "", "", ""])
	frees[0] = str(sum)
	if events != null and events.special_type != &"":
		frees[1] = EventSchedule.label(events.special_type)
		var start_md: int = int(events.special_dates.get("special1", 0))
		frees[4] = str(EventDates.md_day(start_md))
		frees[5] = ShopMail.MONTHS[clampi(EventDates.md_month(start_md), 1, 12) - 1]
	ctx.frees = frees


## The exit greeting plays the imported line when present.
static func conversation(exit_greeting: bool) -> DialogueData:
	if exit_greeting:
		var imported: DialogueData = DialogueCatalog.conversation(
			StringName("msg_%d" % MSG_EXIT_GREETING)
		)
		if imported != null:
			return imported
	return DialogueCatalog.conversation(CONVERSATION_ID)
