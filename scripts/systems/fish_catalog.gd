class_name FishCatalog
extends RefCounted

## Loads `res://data/creatures/*.tres` and answers "what can bite right now".
## Behavioral analog of the `aGYO_*` spawn tables: filtered by month, time slot and
## water kind. The half-month `gyoei_term` split and its transition ramp are not
## modelled, so each fish carries the highest weight it holds across the year rather
## than a per-term one. Not an autoload.

const CREATURES_DIR := "res://data/creatures"

static var _fish: Array[FishData] = []
static var _loaded: bool = false
static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_fish.clear()
	var dir := DirAccess.open(CREATURES_DIR)
	if dir != null:
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and entry.ends_with(".tres"):
				var res: Resource = load("%s/%s" % [CREATURES_DIR, entry])
				if res is FishData and (res as FishData).id != &"":
					_fish.append(res as FishData)
			entry = dir.get_next()
		dir.list_dir_end()
	_fish.sort_custom(func(a: FishData, b: FishData) -> bool: return a.id < b.id)
	_loaded = true


static func all_fish() -> Array[FishData]:
	ensure_loaded()
	return _fish.duplicate()


static func get_fish(fish_id: StringName) -> FishData:
	ensure_loaded()
	for fish: FishData in _fish:
		if fish.id == fish_id:
			return fish
	return null


## `water` is a `WaterBodies.Kind`, or -1 for "anywhere" when there is no body in hand.
static func available(month: int, hour: int, water: int = -1, raining: bool = false) -> Array[FishData]:
	ensure_loaded()
	var out: Array[FishData] = []
	for fish: FishData in _fish:
		if not fish.is_available(month, hour, raining):
			continue
		if water >= 0 and not fish.in_water(water):
			continue
		out.append(fish)
	return out


static func available_now(water: int = -1) -> Array[FishData]:
	return available(Clock.month, Clock.hour, water, Weather.is_raining())


## Weighted pick. Rare fish stay rare, so the loop is never a single guaranteed catch.
static func roll(pool: Array[FishData]) -> FishData:
	if pool.is_empty():
		return null
	var total: int = 0
	for fish: FishData in pool:
		total += maxi(fish.rarity_weight, 1)
	var pick: int = _rng.randi_range(1, total)
	for fish: FishData in pool:
		pick -= maxi(fish.rarity_weight, 1)
		if pick <= 0:
			return fish
	return pool[pool.size() - 1]


static func roll_now() -> FishData:
	return roll(available_now())


## Tests pin the weighted roll; gameplay leaves the default randomized seed alone.
static func seed_rng(value: int) -> void:
	_rng.seed = value


## The first page of a conversation, for the places that can only show one line: a headless
## run with no overlay, or the pockets-full line whose swap choice we do not offer.
static func first_line(data: DialogueData) -> String:
	if data == null:
		return ""
	data.ensure_loaded()
	return String(data.node(data.start).get("text", ""))


## Plain text for a catch report, used only when there is no dialogue overlay to play it in.
static func catch_text(catch_msg: int) -> String:
	if catch_msg == 0:
		return ""
	var text: String = first_line(DialogueCatalog.conversation(StringName("msg_%d" % catch_msg)))
	return text if not text.is_empty() else "You caught something."


static func reload() -> void:
	_loaded = false
	ensure_loaded()
