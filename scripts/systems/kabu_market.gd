class_name KabuMarket
extends RefCounted

## The Stalk Market (`m_kabu_manager.c`). A weekly price schedule keyed to the Sunday that
## starts the week: Joan's Sunday buy price in [70, 130) and Nook's Mon–Sat prices from one
## of three trends (A spike / B random / C falling), each chosen from the last one's odds.
## Owned by `ShopBook`; Nook quotes and pays `price_today()`.

enum Trend { SPIKE, RANDOM, FALLING }

const PRICE_MIN := 10
const PRICE_MAX := 2000
## `Kabu_decide_trade_market`: odds of the next trend given the current one (C is the rest).
const NEXT_TREND_ODDS: Array = [[0.5, 0.3], [0.6, 0.2], [0.6, 0.3]]
const SPIKE_MULTIPLIER := 8.0
const B_SUNDAY_MULT := 0.8
const B_INCREASE_START := 1.05
const B_DECREASE_RATE := 0.7
const B_INCREASE_RATE := 0.01
const B_DECREASE_ODDS_START := 0.1
const B_DECREASE_ODDS_RATE := 0.14
const B_DECREASE_LOWER_RATE := 0.3
const C_MULT_BASE := 0.8
const C_MULT_SPREAD := 0.15
## Nook buys the 10 / 50 / 100 bundles (`kabu_sum`); spoiled ones are junk.
const BUNDLES := {&"turnips_10": 10, &"turnips_50": 50, &"turnips_100": 100}
const SPOILED := &"spoiled_turnips"

var prices: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
var trend: Trend = Trend.RANDOM
## Ordinal of the Sunday this schedule was set on; -1 = never.
var week_ordinal: int = -1
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func clear() -> void:
	prices = PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	trend = Trend.RANDOM
	week_ordinal = -1


static func is_turnip(item_id: StringName) -> bool:
	return BUNDLES.has(item_id) or item_id == SPOILED


static func bundle_size(item_id: StringName) -> int:
	return int(BUNDLES.get(item_id, 0))


static func sunday_ordinal(year: int, month: int, day: int) -> int:
	var ord: int = EventDates.ordinal(year, month, day)
	return ord - EventDates.weekday(year, month, day)


## `Kabu_manager`: re-roll Mon–Sat on the Sunday the schedule was set, and the whole
## schedule once it is a week or more stale (either direction).
func update(year: int, month: int, day: int) -> void:
	var today: int = EventDates.ordinal(year, month, day)
	if week_ordinal >= 0 and today == week_ordinal:
		_decide_without_sunday(year, month, day)
		return
	if week_ordinal < 0 or today >= week_ordinal + 7 or today <= week_ordinal - 7:
		decide_schedule(year, month, day)


## Today's price — Sunday is Joan's buy price, the rest Nook's.
func price_on(weekday: int) -> int:
	return prices[clampi(weekday, 0, 6)]


func price_today() -> int:
	update(Clock.year, Clock.month, Clock.day)
	return price_on(Clock.weekday())


func decide_schedule(year: int, month: int, day: int) -> void:
	prices[0] = int((1.0 + (rng.randf() - 0.5) * 0.6) * 100.0)
	_decide_without_sunday(year, month, day)


func _decide_without_sunday(year: int, month: int, day: int) -> void:
	_decide_trend()
	match trend:
		Trend.SPIKE:
			_schedule_random()
			var spike_day: int = 1 + int(rng.randf() * 5.0)
			prices[spike_day] = _clamp_price(float(prices[0]) * SPIKE_MULTIPLIER)
		Trend.RANDOM:
			_schedule_random()
		Trend.FALLING:
			var current: float = float(prices[0])
			for d: int in range(1, 7):
				current *= C_MULT_BASE + C_MULT_SPREAD * rng.randf()
				prices[d] = _clamp_price(current)
	week_ordinal = sunday_ordinal(year, month, day)


func _decide_trend() -> void:
	var odds: Array = NEXT_TREND_ODDS[int(trend)]
	var chosen: float = rng.randf()
	var picked: int = 2
	for i: int in odds.size():
		if chosen < float(odds[i]):
			picked = i
			break
		chosen -= float(odds[i])
	trend = picked as Trend


func _schedule_random() -> void:
	var mult: float = B_INCREASE_START
	var decrease_odds: float = B_DECREASE_ODDS_START
	var current: float = float(prices[0])
	var floor_price: float = float(prices[0]) * B_SUNDAY_MULT
	for d: int in range(1, 7):
		if rng.randf() < decrease_odds:
			current *= B_DECREASE_RATE
			## A drop never lands above the 80%-of-Sunday floor.
			if current > floor_price:
				current = floor_price
			decrease_odds = minf(decrease_odds * B_DECREASE_LOWER_RATE, B_DECREASE_ODDS_START)
		else:
			current *= mult
			mult += B_INCREASE_RATE
			decrease_odds += B_DECREASE_ODDS_RATE
		prices[d] = _clamp_price(current)


func _clamp_price(value: float) -> int:
	return clampi(int(value), PRICE_MIN, PRICE_MAX)


func to_save() -> Dictionary:
	return {"prices": Array(prices), "trend": int(trend), "week": week_ordinal}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var row: Dictionary = data
	var raw: Variant = row.get("prices", [])
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() == 7:
		for i: int in 7:
			prices[i] = int((raw as Array)[i])
	trend = clampi(int(row.get("trend", Trend.RANDOM)), 0, 2) as Trend
	week_ordinal = int(row.get("week", -1))
