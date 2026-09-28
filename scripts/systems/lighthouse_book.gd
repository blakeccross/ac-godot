class_name LighthouseBook
extends RefCounted

## The lighthouse's saved state (`Save_Get(LightHouse)`, `m_soncho.c` `mSC_LightHouse_*`).
## Owned by `Game`. Everything the tower, its door and the switch room do is decided here.
##
## Normally there is no quest: the lamp lights itself 18:00–05:00 and the door stays shut.
## Tortimer's January / February vacation (`ac_ev_soncho2`) starts a quest instead: the day
## it is given is period 0, the next 7 days are period 1 — the lamp stays dark each night
## until the player walks in (18:00–21:59) and throws the switch — and the 10 days after
## that are period 2, when the reward is handed over.

enum Period { NONE, GIVEN, NIGHTS, REWARD }
## `aLS_GetNiceStatus` for the switch room.
enum SwitchMode { OFF, AUTO_ON, MANUAL }

## `lbRTC_WEEK`: the nights the player has to keep the lamp lit.
const NIGHT_COUNT := 7
## `mSC_LIGHTHOUSE_DAYS`: the quest's full length after the day it was given.
const QUEST_DAYS := 17
## `aTOU_wait` / `aTOU_lighting`: the lamp turns at `now_sec >= 64800 || now_sec < 18000`.
const LAMP_ON_HOUR := 18
const LAMP_OFF_HOUR := 5
## `mSC_LightHouse_In_Check`: the door opens 18:00–21:59.
const DOOR_OPEN_HOUR := 18
const DOOR_CLOSE_HOUR := 22
## `mSC_LightHouse_Switch_Check` looks at the night that started up to 6 hours ago, so a
## switch thrown at 21:00 keeps the lamp lit until 05:00 the next morning.
const NIGHT_ROLLOVER_HOURS := 6

## Day the quest was given (`renew_time`), `EventDates.ordinal`. 0 = no quest.
var start_ordinal: int = 0
## Month the quest was given: January rewards the lighthouse model, February the flag.
var start_month: int = 0
## `days_switched_on`: bit n = the lamp was switched on the night of quest day n.
var nights_lit: int = 0
## `players_quest_started` low nibble: the player took the quest from Tortimer.
var quest_taken: bool = false
## `players_quest_started` high nibble: the player threw the switch at least once.
var contributed: bool = false
## `players_completed`: the reward has been handed over.
var completed: bool = false


func clear() -> void:
	start_ordinal = 0
	start_month = 0
	nights_lit = 0
	quest_taken = false
	contributed = false
	completed = false


## `mSC_LightHouse_Quest_Start`: Tortimer hands out the quest today.
func start_quest(year: int, month: int, day: int) -> void:
	clear()
	start_ordinal = EventDates.ordinal(year, month, day)
	start_month = month
	quest_taken = true


func has_quest() -> bool:
	return start_ordinal > 0


## `mSC_LightHouse_get_period` for a calendar day.
func period_on(ordinal: int) -> Period:
	if start_ordinal <= 0 or ordinal < start_ordinal:
		return Period.NONE
	if ordinal == start_ordinal:
		return Period.GIVEN
	if ordinal <= start_ordinal + NIGHT_COUNT:
		return Period.NIGHTS
	if ordinal <= start_ordinal + QUEST_DAYS:
		return Period.REWARD
	return Period.NONE


## `mSC_LightHouse_day`: which of the 7 nights `ordinal` is (0 = the day after the quest
## was given), clamped to 0–6.
func night_index(ordinal: int) -> int:
	if start_ordinal <= 0:
		return 0
	return clampi(ordinal - start_ordinal - 1, 0, NIGHT_COUNT - 1)


func is_night_lit(ordinal: int) -> bool:
	return nights_lit & (1 << night_index(ordinal)) != 0


## `mSC_LightHouse_Switch_Check`: may the lamp turn tonight? Always, unless the quest is in
## its nights and tonight's switch has not been thrown yet.
func lamp_allowed(year: int, month: int, day: int, hour: int) -> bool:
	var ordinal: int = _night_ordinal(year, month, day, hour)
	if period_on(ordinal) != Period.NIGHTS:
		return true
	return is_night_lit(ordinal)


## `aTOU_wait` / `aTOU_lighting`: the tower lamp turns now.
func lamp_on(year: int, month: int, day: int, hour: int) -> bool:
	var dark: bool = hour >= LAMP_ON_HOUR or hour < LAMP_OFF_HOUR
	return dark and lamp_allowed(year, month, day, hour)


## `mSC_LightHouse_In_Check`: the door opens only on a quest night the switch is still off,
## 18:00–21:59, and never during the first job.
func door_open(year: int, month: int, day: int, hour: int, first_job_active: bool = false) -> bool:
	if first_job_active or start_ordinal <= 0:
		return false
	var ordinal: int = EventDates.ordinal(year, month, day)
	if period_on(ordinal) != Period.NIGHTS:
		return false
	if hour < DOOR_OPEN_HOUR or hour >= DOOR_CLOSE_HOUR:
		return false
	return not is_night_lit(ordinal)


## Daytime → OFF; night outside the quest nights → AUTO_ON (the switch flips itself);
## a quest night → MANUAL (only the player can throw it).
func switch_mode(year: int, month: int, day: int, hour: int) -> SwitchMode:
	if not (hour >= LAMP_ON_HOUR or hour < LAMP_OFF_HOUR):
		return SwitchMode.OFF
	if period_on(EventDates.ordinal(year, month, day)) == Period.NIGHTS:
		return SwitchMode.MANUAL
	return SwitchMode.AUTO_ON


## `mSC_LightHouse_Switch_On`: the player threw the switch tonight.
func switch_on(year: int, month: int, day: int) -> void:
	nights_lit |= 1 << night_index(EventDates.ordinal(year, month, day))
	contributed = true


func all_nights_lit() -> bool:
	var full: int = (1 << NIGHT_COUNT) - 1
	return nights_lit & full == full


## `mSC_LightHouse_travel_check`: the quest nights keep Tortimer away from the plaza.
func in_nights(year: int, month: int, day: int) -> bool:
	return period_on(EventDates.ordinal(year, month, day)) == Period.NIGHTS


## The same checks against the live clock.
func lamp_on_now() -> bool:
	return lamp_on(Clock.year, Clock.month, Clock.day, Clock.hour)


func door_open_now() -> bool:
	var job: bool = Game != null and Game.first_job != null and Game.first_job.is_active()
	return door_open(Clock.year, Clock.month, Clock.day, Clock.hour, job)


func switch_mode_now() -> SwitchMode:
	return switch_mode(Clock.year, Clock.month, Clock.day, Clock.hour)


func switch_on_now() -> void:
	switch_on(Clock.year, Clock.month, Clock.day)


func start_quest_now() -> void:
	start_quest(Clock.year, Clock.month, Clock.day)


func to_save() -> Dictionary:
	return {
		"start": start_ordinal,
		"month": start_month,
		"nights_lit": nights_lit,
		"taken": quest_taken,
		"contributed": contributed,
		"completed": completed,
	}


func apply_snapshot(data: Dictionary) -> void:
	clear()
	if data == null:
		return
	start_ordinal = int(data.get("start", 0))
	start_month = int(data.get("month", 0))
	nights_lit = int(data.get("nights_lit", 0))
	quest_taken = bool(data.get("taken", false))
	contributed = bool(data.get("contributed", false))
	completed = bool(data.get("completed", false))


func _night_ordinal(year: int, month: int, day: int, hour: int) -> int:
	var ordinal: int = EventDates.ordinal(year, month, day)
	return ordinal - 1 if hour < NIGHT_ROLLOVER_HOURS else ordinal
