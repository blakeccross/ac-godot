class_name FishSpawnScheduler
extends RefCounted

## `aSOG_gyoei_set` — the per-water-acre fish shadow spawn decision.
##
## `data/creatures/fish_spawn_table.json` (from `tools/generate_fish.py`) holds the
## decomp `r_month` / `s_month` / `p_month` weights, keyed by the 24 half-month terms
## and the four `aSOG_TIME_*` slots. This layer ports the scheduler code around them:
##  - the 5-day cross-half-month blend (`aSOG_gyoei_chk_term_info`)
##  - the coelacanth splice into the sea list while it rains (`aSOG_add_kaseki_range_data`)
##  - `env_rate` weighting by town rank and the weighted roll (`aSOG_gyoei_get_idx`)
##
## `place_check` for the WATERFALL / POOL / RIVER_MOUTH sub-areas needs acre block-kind
## flags the `WaterBodies` model does not carry, so those entries are accepted in any
## matching water body — a river-pool fish can bite anywhere in the river system.

const TABLE_PATH := "res://data/creatures/fish_spawn_table.json"

## `env_rate_table[mFAs_FIELDRANK_*]` — identical to the insect scheduler.
const ENV_RATE := [0.5, 0.75, 0.875, 1.0, 1.0, 1.0, 1.0]
## `aSOG_gyoei_chk_term_info` `rate[]` — previous-term weight over the 5-day transition.
const PREV_RATE := [1.0 / 6.0, 2.0 / 6.0, 3.0 / 6.0, 4.0 / 6.0, 5.0 / 6.0]
## `aGYO_TYPE_COELACANTH`.
const COELACANTH_TYPE := 31
const COELACANTH_WEIGHT := 5

static var _terms: Dictionary = {}
static var _event: Dictionary = {}
static var _island: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if file == null:
		push_warning("FishSpawnScheduler: missing %s" % TABLE_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_terms = parsed.get("terms", {})
	_event = parsed.get("event", {})
	_island = parsed.get("island", {})


static func reload() -> void:
	_loaded = false
	ensure_loaded()


static func field_rank() -> int:
	return 3  ## no town-assessment system yet — `env_rate` 1.0


static func env_rate() -> float:
	return ENV_RATE[clampi(field_rank(), 0, ENV_RATE.size() - 1)]


## `aSOG_gyoei_chk_term_info`: 24 half-month terms (`(month-1)*2 + (day > 15)`), with the
## previous term blending out over the 5 days after a per-term random 0-5 day offset.
static func term_blend(rng: RandomNumberGenerator) -> Dictionary:
	var term: int = (Clock.month - 1) * 2 + (1 if Clock.day > 15 else 0)
	var prev_term: int = 23 if term == 0 else term - 1
	if Game.gyoei_term != term:
		Game.gyoei_term = term
		Game.gyoei_term_offset = (rng.randi_range(0, 5) if rng != null else 0)
	## Day within the current half-month, then the transition-day index.
	var day_in_half: int = Clock.day if Clock.day <= 15 else Clock.day - 15
	var di: int = day_in_half - 1 - Game.gyoei_term_offset
	var prev_rate: float = 0.0
	if di >= 0 and di < PREV_RATE.size():
		prev_rate = PREV_RATE[di]
	return {"term": term, "prev_term": prev_term, "prev_rate": prev_rate}


## Blended weight list for one water kind (`WaterBodies.Kind`) at this term + slot.
## Returns [{type_index, spawn_area, weight}]. Empty for a dry / out-of-season pond.
static func build_pool(water_kind: int, raining: bool) -> Array:
	ensure_loaded()
	var key: String = _table_key(water_kind)
	if key.is_empty():
		return []
	var slot: int = int(FishData.slot_for_hour(Clock.hour))
	var blend: Dictionary = term_blend(_rng())
	var prev_rate: float = float(blend["prev_rate"])
	var out: Array = []
	_add(out, _slot_entries(int(blend["term"]), key, slot), 1.0 - prev_rate)
	if prev_rate > 0.0:
		_add(out, _slot_entries(int(blend["prev_term"]), key, slot), prev_rate)
	## `aSOG_add_kaseki_range_data`: coelacanth into the sea list while raining, not day.
	if key == "sea" and raining and slot != int(FishData.TimeSlot.DAY):
		out.append({"type_index": COELACANTH_TYPE, "spawn_area": 4, "weight": float(COELACANTH_WEIGHT)})
	return out


## `aSOG_gyoei_get_idx`: weighted roll with `env_rate`, capped to the body's size ceiling.
## Returns a `FishData`, or null (no fish this attempt).
static func decide(
	pool: Array, ceiling: FishData.SizeClass, rng: RandomNumberGenerator
) -> FishData:
	if pool.is_empty():
		return null
	var live: Array = []
	var total: float = 0.0
	for e: Dictionary in pool:
		var fish: FishData = FishCatalog.get_by_type(int(e["type_index"]))
		if fish == null or int(fish.size_class) > int(ceiling):
			continue
		live.append({"fish": fish, "weight": float(e["weight"])})
		total += float(e["weight"])
	if total <= 0.0:
		return null
	var rate: float = env_rate()
	var sel: float = total * (rng.randf() if rng != null else 0.5)
	var acc: float = total
	for e: Dictionary in live:
		acc -= e["weight"] * rate
		if acc < 0.0:
			return null
		if sel >= acc:
			return e["fish"]
	return null


# ---- helpers -------------------------------------------------------

static func _table_key(water_kind: int) -> String:
	match water_kind:
		WaterBodies.Kind.RIVER:
			return "river"
		WaterBodies.Kind.OCEAN:
			return "sea"
		WaterBodies.Kind.POND:
			return "pond"
		_:
			return ""


static func _slot_entries(term: int, key: String, slot: int) -> Array:
	var t: Dictionary = _terms.get(str(term), {})
	var w: Dictionary = t.get(key, {})
	var raw: Variant = w.get(str(slot), [])
	return raw if raw is Array else []


static func _add(out: Array, entries: Array, scale: float) -> void:
	for e: Variant in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		out.append({
			"type_index": int(e.get("type_index", -1)),
			"spawn_area": int(e.get("spawn_area", -1)),
			"weight": float(e.get("weight", 0)) * scale,
		})


static var _srng: RandomNumberGenerator = RandomNumberGenerator.new()


static func _rng() -> RandomNumberGenerator:
	return _srng
