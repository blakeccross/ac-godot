class_name ReddBook
extends RefCounted

## Crazy Redd (`ac_npc_black` / `aBRS_open_check`). Owned by `Game`. The tent shows up
## one day a week once unlocked; stock is a mix of genuine and forged art plus the odd
## furniture piece, one purchase per visit.

const SLOT_COUNT := 4
const ART_COUNT := MuseumBook.ART_NUM
## Paintings that are only ever sold as forgeries (`FTR_SUM_ART02` / `ART03`).
const ALWAYS_FORGED: Array[int] = [1, 2]
const FURNITURE_POOL: Array[StringName] = [
	&"wood_chair", &"wood_table", &"wood_dresser", &"wood_tv"
]

var unlocked: bool = false
## Weekday (0=Sun) the tent is pitched. -1 until the schedule is seeded.
var open_weekday: int = -1
var _stock: Array[Dictionary] = []
var _stock_day: String = ""
var _bought_visit: String = ""


func clear() -> void:
	unlocked = false
	open_weekday = -1
	_stock.clear()
	_stock_day = ""
	_bought_visit = ""


## Unlocks once the museum owns any art, or after the town is a fortnight old.
func check_unlock() -> void:
	if unlocked:
		return
	var by_art: bool = Game != null and Game.museum != null and Game.museum.count_art() > 0
	var by_age: bool = Clock != null and Clock.day >= 14
	if by_art or by_age:
		unlocked = true
		_seed_schedule()


func _seed_schedule() -> void:
	if open_weekday >= 0:
		return
	var seed_src: int = hash("redd_%s" % (Game.town_name if Game != null else "town"))
	open_weekday = int(abs(seed_src)) % 7


func is_open_today() -> bool:
	check_unlock()
	if not unlocked or open_weekday < 0 or Clock == null:
		return false
	return Clock.weekday() == open_weekday


func _day_key() -> String:
	if Clock == null:
		return ""
	return "%04d-%02d-%02d" % [Clock.year, Clock.month, Clock.day]


## Today's four items. Rolled once per open day, deterministic per town + date.
func stock() -> Array[Dictionary]:
	var today: String = _day_key()
	if _stock_day != today or _stock.is_empty():
		_roll_stock(today)
	return _stock.duplicate(true)


func _roll_stock(today: String) -> void:
	_stock_day = today
	_stock.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("redd_stock_%s_%s" % [Game.town_name if Game != null else "town", today])
	var used: Dictionary = {}
	## Slot 0 is a coin-flip furniture piece; the rest are paintings.
	if rng.randf() < 0.35:
		_stock.append({
			"item_id": FURNITURE_POOL[rng.randi_range(0, FURNITURE_POOL.size() - 1)],
			"forged": false,
			"price": rng.randi_range(3000, 6000),
		})
	while _stock.size() < SLOT_COUNT:
		var index: int = rng.randi_range(0, ART_COUNT - 1)
		if used.has(index):
			continue
		used[index] = true
		var forged: bool = index in ALWAYS_FORGED or rng.randf() < 0.5
		_stock.append({
			"item_id": art_item_id(index, forged),
			"art_index": index,
			"forged": forged,
			"price": rng.randi_range(3920, 4980),
		})


static func art_item_id(index: int, forged: bool) -> StringName:
	if forged:
		return StringName("art_forgery_%02d" % index)
	return MuseumDisplay.ART_VISUALS[index]


## Registers the genuine + forged art items so they resolve in `ItemCatalog`.
static func ensure_art_items() -> void:
	for index: int in ART_COUNT:
		var visual: StringName = MuseumDisplay.ART_VISUALS[index]
		if ItemCatalog.get_item(visual) == null:
			ItemCatalog.remember(_make_art(visual, visual, index, false))
		var fake_id: StringName = StringName("art_forgery_%02d" % index)
		if ItemCatalog.get_item(fake_id) == null:
			ItemCatalog.remember(_make_art(fake_id, visual, index, true))


static func _make_art(id: StringName, visual: StringName, index: int, forged: bool) -> FurnitureData:
	var data := FurnitureData.new()
	data.id = id
	data.visual_id = visual
	data.display_name = "Painting %d%s" % [index + 1, " (?)" if forged else ""]
	data.description = "A framed painting." if not forged else "A framed painting. Something's off about it."
	data.sell_price = 10 if forged else 3920
	data.kind = FurnitureData.Kind.DISPLAY
	data.placement = FurnitureData.Placement.WALL
	data.footprint = Vector2i(1, 1)
	data.set_meta("art_forgery", forged)
	return data


func can_buy() -> bool:
	return is_open_today() and _bought_visit != _day_key()


func buy(item_id: StringName, inv: Inventory) -> String:
	if not is_open_today():
		return "Redd isn't around today."
	if _bought_visit == _day_key():
		return "One to a customer per visit, friend."
	var entry: Dictionary = {}
	for row: Dictionary in stock():
		if StringName(str(row.get("item_id", ""))) == item_id:
			entry = row
			break
	if entry.is_empty():
		return "I don't have that one."
	var price: int = int(entry.get("price", 4000))
	if inv == null or inv.wallet < price:
		return "Not enough Bells."
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null or not inv.has_space_for(data, 1):
		return "Your pockets are full."
	inv.set_wallet(inv.wallet - price)
	inv.add(data, 1)
	_bought_visit = _day_key()
	return "Pleasure doing business."


func to_save() -> Dictionary:
	return {
		"unlocked": unlocked,
		"open_weekday": open_weekday,
		"bought_visit": _bought_visit,
	}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var row: Dictionary = data
	unlocked = bool(row.get("unlocked", false))
	open_weekday = int(row.get("open_weekday", -1))
	_bought_visit = str(row.get("bought_visit", ""))
