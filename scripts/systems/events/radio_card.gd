class_name RadioCard
extends BankTalk

## Tortimer's exercise card at Morning Aerobics (`mSC_Radio_Set_Talk_Proc`, `mSCR_talk_*`).
## The first visit of the summer hands over a card with one stamp (`ITM_EXCERCISE_CARD00`);
## each later day he looks the card over and stamps it once (`EXCERCISE_CARD00 + days`). The
## fourteenth stamp trades the card for the aerobics radio (`FTR_RADIO_TEST`). A lost card is
## remembered and replaced; two cards, or one from an earlier year, are taken away. From
## August 19 there's no new card unless one is under way (`mSC_Radio_limit_check`).
##
## `Game.radio_card`: `{year, month, day, days}` — the last stamp's date and the stamps on
## the card less one (`mPr_day_day_c`).

const CARD_PREFIX := "exercise_card_"
## `mSC_RADIO_DAYS`: cards 00..12; the stamp after card 12 wins the radio.
const DAYS := 13
## `FTR_RADIO_TEST`.
const RADIO_FTR := 1011
## The aerobics Tortimer's calendar entry, for "already talked today" (`mCD_calendar_event_check`).
const CALENDAR_KEY := "morning_aerobics"

const MSG_NEW := 0x3422
const MSG_NEW_AGAIN := 0x3423
const MSG_NEW_FULL := 0x3424
const MSG_NEW_GIVE := 0x3425
const MSG_NEW_AFTER := 0x3426
const MSG_STAMP := 0x3427
const MSG_STAMP_COUNT := 0x3428
const MSG_STAMP_AFTER := 0x3429
const MSG_FINISH := 0x342A
const MSG_FINISH_COUNT := 0x342B
const MSG_FINISH_PRESENT := 0x342C
const MSG_PRIZE := 0x342D
const MSG_LOST := 0x342E
const MSG_LOST_AGAIN := 0x342F
const MSG_LOST_FULL := 0x3430
const MSG_LOST_GIVE := 0x3431
const MSG_LOST_AFTER := 0x3432
const MSG_SAME_DAY := 0x3433
const MSG_SAME_DAY_AFTER := 0x3434
const MSG_TOO_LATE := 0x3437
const MSG_TOO_LATE_AFTER := 0x3438
const MSG_FOREIGNER := 0x343B
const MSG_OLD_CARD := 0x343C
const MSG_LOST_FINISH := 0x343D
const MSG_LOST_FINISH_FULL := 0x343E

## `mSC_RADIO_TIME_*` (`mSC_Radio_time_check`).
enum Stamp { LESS, SAME_DAY, OVER }
## `mSCR_ACTION_*`.
enum Action { TOO_LATE, DELETE_OLD_CARD, NEW_CARD, LOST_CARD, STAMP_CARD, FINISH_CARD, LOST_CARD_AND_FINISH }

var inventory: Inventory
var card: Dictionary
## `soncho_record`: the aerobics day goes on Tortimer's calendar here.
var record: Dictionary
var rng: RandomNumberGenerator
var foreigner: bool = false
var year: int
var month: int
var day: int
## The card (or radio) changing hands, and what he does at each message's end.
var held: StringName = &""
var _steps: Dictionary = {}
var _take_old: bool = false


func _init(
	p_inventory: Inventory, p_card: Dictionary, p_record: Dictionary,
	p_rng: RandomNumberGenerator = null, p_date: Vector3i = Vector3i.ZERO
) -> void:
	inventory = p_inventory
	card = p_card
	record = p_record
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()
	if p_date == Vector3i.ZERO:
		p_date = Vector3i(Clock.year, Clock.month, Clock.day)
	year = p_date.x
	month = p_date.y
	day = p_date.z


static func new_state() -> Dictionary:
	return {"year": 0, "month": 0, "day": 0, "days": 0}


static func from_save(data: Variant) -> Dictionary:
	var out: Dictionary = new_state()
	if typeof(data) == TYPE_DICTIONARY:
		for key: String in out.keys():
			out[key] = int((data as Dictionary).get(key, 0))
	return out


static func card_id(days: int) -> StringName:
	return StringName("%s%02d" % [CARD_PREFIX, clampi(days, 0, DAYS - 1)])


static func is_card(id: StringName) -> bool:
	return String(id).begins_with(CARD_PREFIX)


static func radio_id() -> StringName:
	return FtrCatalog.item_id(RADIO_FTR)


## `mSC_Radio_many_taisou_card`: unwrapped cards in the pockets.
static func card_count(inv: Inventory) -> int:
	var n: int = 0
	if inv == null:
		return 0
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inv.slot_at(i)
		if slot != null and not slot.is_empty() and is_card(slot.item.item_id) \
				and slot.item.condition == InventoryItem.Condition.NORMAL:
			n += 1
	return n


## `mSC_Radio_have_taisou_card`: the lowest card held (card 00 when none).
static func held_card(inv: Inventory) -> StringName:
	for d: int in DAYS:
		if inv != null and inv.count_of(card_id(d)) > 0:
			return card_id(d)
	return card_id(0)


## `mSC_Radio_time_check`: another year counts as earlier.
static func time_check(state: Dictionary, y: int, m: int, d: int) -> int:
	if y != int(state.get("year", 0)):
		return Stamp.LESS
	var now: int = m * 32 + d
	var last: int = int(state.get("month", 0)) * 32 + int(state.get("day", 0))
	if now == last:
		return Stamp.SAME_DAY
	return Stamp.OVER if now > last else Stamp.LESS


## `mSC_Radio_limit_check`: no new cards once it's August 19 or later (the GCN test is
## `month >= AUGUST && day >= 19`).
static func limit_ok(m: int, d: int) -> bool:
	return not (m >= 8 and d >= 19)


## The `mSCR_ACTION_*` for a resident's talk (not the same-day case).
static func action_for(state: Dictionary, cards: int, held_days: int, time: int, m: int, d: int) -> int:
	if cards <= 0:
		var days: int = int(state.get("days", 0))
		if not limit_ok(m, d) and (days == DAYS or time == Stamp.LESS):
			return Action.TOO_LATE
		match time:
			Stamp.LESS:
				return Action.NEW_CARD
			Stamp.OVER:
				if days == DAYS - 1:
					return Action.LOST_CARD_AND_FINISH
				if days < DAYS:
					return Action.LOST_CARD
				return Action.NEW_CARD
		return Action.TOO_LATE
	if cards > 1:
		return Action.DELETE_OLD_CARD
	match time:
		Stamp.LESS:
			return Action.DELETE_OLD_CARD
		Stamp.OVER:
			return Action.FINISH_CARD if held_days + 1 >= DAYS else Action.STAMP_CARD
	return Action.TOO_LATE


func _stamp(days: int) -> void:
	card["year"] = year
	card["month"] = month
	card["day"] = day
	card["days"] = days


func _calendar_marked() -> bool:
	return int(record.get(CALENDAR_KEY, -1)) == EventDates.ordinal(year, month, day)


func _swap_card(old: StringName, new_id: StringName) -> void:
	if inventory == null:
		return
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inventory.slot_at(i)
		if slot != null and not slot.is_empty() and slot.item.item_id == old:
			slot.item.item_id = new_id
			inventory.changed.emit()
			return


func _give(id: StringName) -> void:
	var data: ItemData = ItemCatalog.get_item(id)
	if data != null and inventory != null:
		inventory.add(data, 1)


func _set_prize_name() -> void:
	var data: ItemData = ItemCatalog.get_item(radio_id())
	set_free(1, PoliceTalk.with_article(data.display_name) if data != null else "")


func start_msg() -> int:
	var marked: bool = _calendar_marked()
	record[CALENDAR_KEY] = EventDates.ordinal(year, month, day)
	if Game != null:
		CalendarBook.event_on(Game.calendar, EventDates.ordinal(year, month, day))
	if foreigner:
		return MSG_FOREIGNER
	var time: int = time_check(card, year, month, day)
	if time == Stamp.SAME_DAY:
		_steps[MSG_SAME_DAY] = {"msg": MSG_SAME_DAY_AFTER + rng.randi_range(0, 2)}
		return MSG_SAME_DAY
	var cards: int = card_count(inventory)
	var current: StringName = held_card(inventory)
	var held_days: int = int(String(current).substr(CARD_PREFIX.length()))
	var room: bool = inventory != null and inventory.has_space(1)
	match action_for(card, cards, held_days, time, month, day):
		Action.DELETE_OLD_CARD:
			_take_old = true
			return MSG_OLD_CARD
		Action.NEW_CARD:
			var first: int = MSG_NEW_AGAIN if marked else MSG_NEW
			if not room:
				_steps[first] = {"msg": MSG_NEW_FULL}
				return first
			held = card_id(0)
			_give(held)
			_stamp(0)
			_steps[first] = {"msg": MSG_NEW_GIVE}
			_steps[MSG_NEW_GIVE] = {"anim": {"give": held}, "msg": MSG_NEW_AFTER}
			return first
		Action.LOST_CARD, Action.LOST_CARD_AND_FINISH:
			var finish: bool = int(card.get("days", 0)) == DAYS - 1
			var first: int = MSG_LOST_AGAIN if marked else MSG_LOST
			set_free(0, str(int(card.get("days", 0)) + 2))
			if not room:
				_steps[first] = {"msg": MSG_LOST_FINISH_FULL if finish else MSG_LOST_FULL}
				return first
			var days: int = int(card.get("days", 0)) + 1
			held = radio_id() if finish else card_id(days)
			_give(held)
			_stamp(days)
			if finish:
				_set_prize_name()
				_steps[first] = {"msg": MSG_LOST_FINISH}
				_steps[MSG_LOST_FINISH] = {"anim": {"give": held}, "msg": MSG_PRIZE}
			else:
				_steps[first] = {"msg": MSG_LOST_GIVE}
				_steps[MSG_LOST_GIVE] = {"anim": {"give": held}, "msg": MSG_LOST_AFTER}
			return first
		Action.STAMP_CARD:
			var days: int = held_days + 1
			_stamp(days)
			held = card_id(days)
			_swap_card(current, held)
			set_free(0, str(days + 1))
			_steps[MSG_STAMP] = {"anim": {"take": current}, "msg": MSG_STAMP_COUNT}
			_steps[MSG_STAMP_COUNT] = {"anim": {"give": held}, "msg": MSG_STAMP_AFTER}
			return MSG_STAMP
		Action.FINISH_CARD:
			_stamp(held_days + 1)
			held = radio_id()
			_swap_card(current, held)
			_set_prize_name()
			_steps[MSG_FINISH] = {"anim": {"take": current}, "msg": MSG_FINISH_COUNT}
			_steps[MSG_FINISH_COUNT] = {"msg": MSG_FINISH_PRESENT}
			_steps[MSG_FINISH_PRESENT] = {"anim": {"give": held}, "msg": MSG_PRIZE}
			return MSG_FINISH
	_steps[MSG_TOO_LATE] = {"msg": MSG_TOO_LATE_AFTER + rng.randi_range(0, 2)}
	return MSG_TOO_LATE


func next_step() -> Dictionary:
	return (_steps.get(current_msg, {}) as Dictionary).duplicate()


## `mSCR_talk_pickup_all`: "Hand it over" takes every card.
func lock_continue() -> Dictionary:
	if current_msg == MSG_OLD_CARD and _take_old and order_value("npc0", 9) == 1:
		_take_old = false
		var shown: StringName = held_card(inventory)
		for d: int in DAYS:
			if inventory != null:
				inventory.remove(card_id(d), inventory.count_of(card_id(d)))
		return {"anim": {"take": shown}}
	return {}
