class_name IntroProgress
extends RefCounted

## Where a new resident is in the station arrival (`ac_intro_demo`): Porter, then Nook, the
## house pick and the down payment. Session-only; `Game.complete_intro_station` ends it.

## The player pressed A on a vacant plot; the director plays `msg_2020` and then enters.
signal house_look_requested(house_id: StringName)
signal payment_resolved(paid: bool)

## The arrival demo is running in the generated world.
var active: bool = false
## After Porter, until the debt and job finish: vacant myhome doors can be entered to pick one.
var can_pick_house: bool = false
## Resume the debt talk after leaving the chosen house (`IN_HOUSE` -> outdoor).
var resume_debt: bool = false
var house_id: StringName = &""
var pending_house_id: StringName = &""
## `aNRG_demand_payment`: after the debt line Nook opens the pockets (`mSM_IV_OPEN_QUEST`) so
## the player hands over the starting money bag before the job talk.
var payment_pending: bool = false


## The demo is over. The house pick stays for the rest of the session.
func finish() -> void:
	active = false
	can_pick_house = false
	resume_debt = false
	pending_house_id = &""
	payment_pending = false


func clear() -> void:
	finish()
	house_id = &""


## A vacant plot was interacted with during the pick: Nook speaks (`msg_2020`) before the door.
func request_house_look(plot_id: StringName) -> void:
	if not active or not can_pick_house or plot_id == &"":
		return
	can_pick_house = false
	pending_house_id = plot_id
	Game.set_interact_prompt("")
	house_look_requested.emit(plot_id)


## The pick outlives the intro: the saved house record carries it (`PlayerHouse.owned_building_id`).
func claim_house(plot_id: StringName) -> void:
	if not active:
		return
	house_id = plot_id
	var record: House = Game.interiors.player_house()
	if record != null and plot_id != &"":
		record.outdoor_building_id = plot_id
	pending_house_id = &""
	can_pick_house = false
	resume_debt = true


func payment_made() -> void:
	if payment_pending:
		payment_pending = false
		payment_resolved.emit(true)


func payment_declined() -> void:
	if payment_pending:
		payment_pending = false
		payment_resolved.emit(false)
