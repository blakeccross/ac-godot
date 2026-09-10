class_name FishCatalog
extends RefCounted

## Loads `res://data/creatures/*.tres` and resolves a species by id, `aGYO_TYPE_*`
## index or size — the reference query behind the museum, the encyclopedia and the
## coarse "what can bite this month" list. The live per-acre spawn decision, with the
## 24 half-month `gyoei_term` weights and their 5-day transition ramp, is
## `FishSpawnScheduler` (from `data/creatures/fish_spawn_table.json`). Not an autoload.

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


## Real catchable species only — the trash placeholders (`is_trash`) are never in a
## spawn pool and only appear via `trash_for_size` when a committing fish swaps out.
static func all_fish() -> Array[FishData]:
	ensure_loaded()
	var out: Array[FishData] = []
	for fish: FishData in _fish:
		if not fish.is_trash:
			out.append(fish)
	return out


static func get_fish(fish_id: StringName) -> FishData:
	ensure_loaded()
	for fish: FishData in _fish:
		if fish.id == fish_id:
			return fish
	return null


## `aGYO_TYPE_*` index → species (`FishData.TYPE_IDS`).
static func get_by_type(type_index: int) -> FishData:
	if type_index < 0 or type_index >= FishData.TYPE_IDS.size():
		return null
	return get_fish(FishData.TYPE_IDS[type_index])


## `water` is a `WaterBodies.Kind`, or -1 for "anywhere" when there is no body in hand.
static func available(month: int, hour: int, water: int = -1, raining: bool = false) -> Array[FishData]:
	ensure_loaded()
	var out: Array[FishData] = []
	for fish: FishData in _fish:
		if fish.is_trash:
			continue
		if not fish.is_available(month, hour, raining):
			continue
		if water >= 0 and not fish.in_water(water):
			continue
		out.append(fish)
	return out


## `gomi[gyo->size_type]` (`aGTT_touch`): what a committing fish becomes 1 time in 20.
## XXS/XS → can, S/M/L → boot, XL/XXL/WHALE → tire.
static func trash_for_size(size: FishData.SizeClass) -> FishData:
	ensure_loaded()
	var id: StringName = &"old_tire"
	if int(size) <= int(FishData.SizeClass.XS):
		id = &"empty_can"
	elif int(size) <= int(FishData.SizeClass.L):
		id = &"leaky_boot"
	return get_fish(id)


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
