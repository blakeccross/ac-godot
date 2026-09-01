class_name BugCatalog
extends RefCounted

## Loads `res://data/creatures/*.tres` and answers "what can spawn right now".
## Behavioral analog of the `aSOI_*` spawn tables: filtered by month, insect term,
## habitat, and weather. Not an autoload.

const CREATURES_DIR := "res://data/creatures"

static var _bugs: Array[BugData] = []
static var _loaded: bool = false
static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_bugs.clear()
	var dir := DirAccess.open(CREATURES_DIR)
	if dir != null:
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and entry.ends_with(".tres"):
				var res: Resource = load("%s/%s" % [CREATURES_DIR, entry])
				if res is BugData and (res as BugData).id != &"":
					_bugs.append(res as BugData)
			entry = dir.get_next()
		dir.list_dir_end()
	_bugs.sort_custom(func(a: BugData, b: BugData) -> bool: return a.id < b.id)
	_loaded = true


static func all_bugs() -> Array[BugData]:
	ensure_loaded()
	return _bugs.duplicate()


static func get_bug(bug_id: StringName) -> BugData:
	ensure_loaded()
	for bug: BugData in _bugs:
		if bug.id == bug_id:
			return bug
	return null


static func get_by_type(type_index: int) -> BugData:
	ensure_loaded()
	for bug: BugData in _bugs:
		if bug.type_index == type_index:
			return bug
	return null


## `habitat` is a `BugData.Habitat`, or -1 for "anywhere".
static func available(month: int, hour: int, habitat: int = -1, raining: bool = false) -> Array[BugData]:
	ensure_loaded()
	var out: Array[BugData] = []
	for bug: BugData in _bugs:
		if bug.needs_rain and not raining:
			continue
		if not bug.is_available(month, hour):
			continue
		if habitat >= 0 and not bug.in_habitat(habitat):
			continue
		out.append(bug)
	return out


static func available_now(habitat: int = -1, raining: bool = false) -> Array[BugData]:
	return available(Clock.month, Clock.hour, habitat, raining)


static func roll(pool: Array[BugData]) -> BugData:
	if pool.is_empty():
		return null
	var total: int = 0
	for bug: BugData in pool:
		total += maxi(bug.rarity_weight, 1)
	var pick: int = _rng.randi_range(1, total)
	for bug: BugData in pool:
		pick -= maxi(bug.rarity_weight, 1)
		if pick <= 0:
			return bug
	return pool[pool.size() - 1]


static func roll_now(habitat: int = -1, raining: bool = false) -> BugData:
	return roll(available_now(habitat, raining))


static func seed_rng(value: int) -> void:
	_rng.seed = value


static func first_line(data: DialogueData) -> String:
	if data == null:
		return ""
	data.ensure_loaded()
	return String(data.node(data.start).get("text", ""))


static func catch_text(catch_msg: int) -> String:
	if catch_msg == 0:
		return ""
	var text: String = first_line(DialogueCatalog.conversation(StringName("msg_%d" % catch_msg)))
	return text if not text.is_empty() else "You caught something."


static func reload() -> void:
	_loaded = false
	ensure_loaded()
