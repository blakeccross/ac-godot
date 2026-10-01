class_name Sunburn
extends RefCounted

## Summer tan (`Player_actor_Check_player_sunburn_*`, `mPr_sunburn_c`). Out in town on a clear
## day between 10:00 and 16:59, July 16 – September 15, without an umbrella up, every fifteen
## minutes in the sun (counted in 60 Hz ticks, `mPlayer_SUNBURN_TIME_VILLAGE`) earns a rank,
## up to 8. A fresh rank holds for two days (`rankdown_days`); after that the tan fades a rank
## for each day it is left. A pending change shows the next time the player is set up (a
## scene change or an acre crossing), when the face palette is swapped
## (`mPlib_change_player_face_pallet`). State: {rank, changed (day number), hold}.

const MAX_RANK := 8
const HOLD_DAYS := 2
const SUN_TICKS := 15 * 60 * 60
const FIRST_HOUR := 10
const LAST_HOUR := 16

## Common `sunburn_time` and the player's rank-up / rank-down requests: not saved.
static var sun_ticks: int = 0
static var rankup_pending: bool = false
static var rankdown_pending: bool = false


static func reset_session() -> void:
	sun_ticks = 0
	rankup_pending = false
	rankdown_pending = false


## Town dates the sun can burn: July 16 – September 15.
static func in_season(month: int, day: int) -> bool:
	match month:
		7:
			return day >= 16
		8:
			return true
		9:
			return day <= 15
	return false


static func sunny_hour(hour: int) -> bool:
	return hour >= FIRST_HOUR and hour <= LAST_HOUR


## `_ChangeDay`: a clock wound back below the last change resets that day.
static func change_day(state: Dictionary, today: int) -> void:
	if int(state.get("rank", 0)) > 0 and today < int(state.get("changed", today)):
		state["changed"] = today


## `_rankdown_interval`: the hold runs down as days pass (two at most per check).
static func rankdown_interval(state: Dictionary, today: int) -> void:
	if int(state.get("rank", 0)) <= 0:
		return
	var hold: int = int(state.get("hold", 0))
	if hold <= 0:
		return
	var days: int = today - int(state.get("changed", today))
	if days <= 0:
		return
	if hold >= 2:
		state["changed"] = int(state.get("changed", today)) + 1
	hold -= 1 if days == 1 else 2
	state["hold"] = maxi(hold, 0)


## `_rankdown`: days past the hold mean the tan is fading.
static func check_rankdown(state: Dictionary, today: int) -> void:
	if int(state.get("rank", 0)) > 0 and not rankdown_pending:
		if today - int(state.get("changed", today)) - int(state.get("hold", 0)) > 0:
			rankdown_pending = true


## `_rankup` for one tick in the sun. `exposed`: outdoors in town, clear sky, no umbrella,
## not the first arrival.
static func sun_tick(state: Dictionary, exposed: bool, month: int, day: int, hour: int) -> void:
	if rankup_pending or not exposed or not sunny_hour(hour) or not in_season(month, day):
		return
	if int(state.get("rank", 0)) > 0 and int(state.get("hold", 0)) >= HOLD_DAYS:
		return
	if rankdown_pending:
		return
	if sun_ticks >= SUN_TICKS:
		rankup_pending = true
	sun_ticks += 1


## `_Set_player_sunburn_rankup` / `_rankdown`: apply what is pending. True when the rank
## changed (the face needs repainting).
static func settle(state: Dictionary, today: int) -> bool:
	var changed := false
	if rankup_pending:
		state["rank"] = mini(int(state.get("rank", 0)) + 1, MAX_RANK)
		state["changed"] = today
		state["hold"] = HOLD_DAYS
		sun_ticks = 0
		rankup_pending = false
		changed = true
	if rankdown_pending:
		var diff: int = today - int(state.get("changed", today)) - int(state.get("hold", 0))
		if diff > 0:
			state["rank"] = maxi(int(state.get("rank", 0)) - diff, 0)
			state["changed"] = today
			changed = true
		rankdown_pending = false
	return changed


## Every check the player makes on set-up (`_for_ct` / `_for_dt`).
static func on_setup(state: Dictionary, today: int) -> bool:
	change_day(state, today)
	rankdown_interval(state, today)
	check_rankdown(state, today)
	return settle(state, today)
