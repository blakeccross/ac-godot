class_name FishSpawnScheduler
extends RefCounted

## `aSOG_gyoei_set` — the fish shadow spawn decision for one acre, made once each time the
## player enters it (`FishSchool._tick_spawn`).
##
## `data/creatures/fish_spawn_table.json` (from `tools/generate_fish.py`) holds the
## `r_month` / `s_month` / `p_month` / `f_event` / `f_island` weights, keyed by the 24
## half-month terms and the four `aSOG_TIME_*` slots. This layer is the scheduler around
## them:
##  - which list an acre fishes from, by its `mRF_BLOCKKIND_*` flags
##    (`aSOG_gyoei_make_range_data`): marine → sea / offing / island, river → river or the
##    tourney bass list, anything else → pond
##  - the 5-day ramp into the *next* half-month (`aSOG_gyoei_chk_term_info`)
##  - the coelacanth (rain, not 9am–4pm) and whale (offing) splices
##  - `env_rate` weighting and the weighted roll with its sub-area retry
##    (`aSOG_gyoei_get_idx` / `aSOG_gyoei_place_check`)
##  - the per-species unit filter inside the acre's inner 12×12 (`aSOG_gyoei_set_gyoei_data`)
##    and the spawn point inside that unit (`aSOG_gyoei_make`)

const TABLE_PATH := "res://data/creatures/fish_spawn_table.json"

## `mRF_BLOCKKIND_*` bits the fish code reads.
const KIND_RIVER := 1 << 7
const KIND_WATERFALL := 1 << 8
const KIND_BRIDGE := 1 << 9
const KIND_MARINE := 1 << 11
const KIND_POOL := 1 << 15
const KIND_ISLAND := 1 << 21
const KIND_OFFING := 1 << 22

## `mRF_block_info[mFM_BLOCK_TYPE_*]` (`m_random_field.c`), reduced to the bits above.
## Indexed by the decomp block type (`TownMap.decomp_block_type`).
const _R := KIND_RIVER
const _WF := KIND_RIVER | KIND_WATERFALL
const _BR := KIND_RIVER | KIND_BRIDGE
const _PL := KIND_RIVER | KIND_POOL
const _M := KIND_MARINE
const _OFF := KIND_MARINE | KIND_OFFING
const _IS := KIND_MARINE | KIND_ISLAND
const BLOCK_INFO: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0,                          ## 0-9 border (RIVER0 only), tunnel
	0, 0, 0, _R, 0, 0, 0, 0, 0, 0,                         ## 10-19 station, dump, tracks river
	0, 0, _WF, _WF, _R, _R, _WF, _R, _R, _R,               ## 20-29 cliff rivers
	_WF, _WF, _R, _R, _R, _R, _R, _WF, _WF, 0,             ## 30-39 (39 flat)
	_R, _R, _R, _R, _R, _R, _R, _BR, _BR, _BR,             ## 40-49 rivers, bridges
	_BR, _BR, _BR, _BR, 0, 0, 0, 0, 0, 0,                  ## 50-59 bridges, slopes
	0, 0, 0, _M, _M | _R, 0, 0, 0, 0, _PL,                 ## 60-69 beach, beach river, pool
	_PL, _PL, _PL, _PL, _PL, _PL, 0, _R, 0, 0,             ## 70-79 pools, border river
	_M, _M, _M | _BR, 0, 0, _M, _BR, _BR, _BR, _BR,        ## 80-89 marine border, museum, tailors
	_BR, _BR, _BR, _BR, _OFF, _OFF, _OFF, _OFF, _IS, _IS,  ## 90-99 offing, island
	_M, _OFF, _OFF, _OFF, _OFF, _BR, _BR, _BR,             ## 100-107 dock, offing
]

## `aSOG_SPAWN_AREA_*`.
enum Area { POOL, WATERFALL, RIVER_MOUTH, OFFING, SEA, RIVER, POND }

## `aGYO_TYPE_*` the spawn code singles out.
const TYPE_LARGE_CHAR := 19
const TYPE_SALMON := 22
const TYPE_COELACANTH := 31
const TYPE_JELLYFISH := 35
const TYPE_SEA_BASS := 36
const TYPE_RED_SNAPPER := 37
const TYPE_BARRED_KNIFEJAW := 38
## `aGYO_TYPE_NUM` — also what `aSOG_gyoei_get_idx_sub` returns for "rolled a sub-area
## this acre does not have, roll again".
const TYPE_NUM := 40
const TYPE_WHALE := 40
const TYPE_SALMON2 := 44
const INVALID := -1

## `env_rate_table[mFAs_FIELDRANK_*]` — identical to the insect scheduler.
const ENV_RATE := [0.5, 0.75, 0.875, 1.0, 1.0, 1.0, 1.0]
## `aSOG_gyoei_chk_term_info` `rate[]`: the *current* term's share on each day of the
## ramp into the next one. The next term takes the rest.
const TERM_RATE := [5.0 / 6.0, 4.0 / 6.0, 3.0 / 6.0, 2.0 / 6.0, 1.0 / 6.0]
## `aSOG_TERM_TRANSITION_MAX_DAYS`.
const TRANSITION_DAYS := 5
## `aSOG_add_kaseki_range_data`: `FISH_SPAWN(COELACANTH, SEA, 2.0f)`.
const COELACANTH_WEIGHT := 2.0
## `aSOG_gyoei_make_offing_range_data`: the sea list ×10, then `FISH_SPAWN(WHALE, OFFING, 1.0f)`.
const OFFING_SCALE := 10.0
const WHALE_WEIGHT := 1.0
## `aSOG_gyoei_check_fishing_event`: 75% of pool / bridge / waterfall river acres switch
## to the bass list while a tourney runs.
const TOURNEY_CHANCE := 0.75
const TOURNEY_EVENTS: Array[StringName] = [&"fishing_tourney_1", &"fishing_tourney_2"]
const TOURNEY_KINDS: Array[int] = [KIND_POOL, KIND_BRIDGE, KIND_WATERFALL]

## Units per acre side (`UT_X_NUM` / `UT_Z_NUM`).
const UT := 16
## `aSOG_gyoei_set_gyoei_data`: fish only spawn in units 2..13 of the acre, the whale in 5..10.
const INNER_MARGIN := 2
const WHALE_MARGIN := 5
## `mCoBG_GetWaterHeight` for `SEA`: a flat 20 GX. Sea fish need `water - bg >= 20`.
const SEA_WATER_HEIGHT_GX := 20.0
const SEA_MIN_DEPTH_GX := 20.0

## `mCoBG_ATTRIBUTE_*` the unit filter reads.
const ATTR_WATER := 12
const ATTR_WATERFALL := 13
const ATTR_RIVER_NE := 21
const ATTR_SEA := 24

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


## `mFAs_GetFieldRank`. No town-assessment system yet: the calendar's constant rank 3,
## so `env_rate` is 1.0.
static func field_rank() -> int:
	if Game != null and Game.events != null:
		return Game.events.field_rank
	return EventCalendar.DEFAULT_FIELD_RANK


static func env_rate() -> float:
	return ENV_RATE[clampi(field_rank(), 0, ENV_RATE.size() - 1)]


# ---- acre classification ------------------------------------------

## `mFI_BkNum2BlockKind` for a `TownFieldGenerator` block type.
static func block_kind_for_type(godot_type: int) -> int:
	## The lighthouse is not a decomp block type (`BLOCK_COMBI_ROM_TOUDAI` is NONE).
	if godot_type == TownFieldGenerator.T_LIGHTHOUSE:
		return 0
	var t: int = TownMap.decomp_block_type(godot_type)
	if t < 0 or t >= BLOCK_INFO.size():
		return 0
	return BLOCK_INFO[t]


## Authored test towns carry no block types. Stand in with the water body's kind so the
## right list is used: sea water fishes the sea list, a river the river list.
static func block_kind_for_water(water_kind: int) -> int:
	match water_kind:
		WaterBodies.Kind.OCEAN:
			return KIND_MARINE
		WaterBodies.Kind.RIVER:
			return KIND_RIVER
		_:
			return 0


## `mCoBG_CheckWaterAttribute`: water, waterfall, the eight river flows, and sea.
static func is_water_attr(attr: int) -> bool:
	return attr == ATTR_SEA or (attr >= ATTR_WATER and attr <= ATTR_RIVER_NE)


## `mCoBG_CheckWaterAttribute_OutOfSea`.
static func is_fresh_water_attr(attr: int) -> bool:
	return attr >= ATTR_WATER and attr <= ATTR_RIVER_NE


# ---- term ---------------------------------------------------------

## `aSOG_gyoei_chk_term_info`. `Game.gyoei_term` is the *next* half-month (what
## `aSOG_gyoei_renew_term_info` saves) and `Game.gyoei_term_offset` a 0–5 day lead. From
## that many days before the next term starts, for five days, the next term's list fades
## in at 1/6 a day while the current one fades out. Returns
## `{term0, term1, term0_rate}`; `term0_rate` is 1.0 outside the ramp.
static func chk_term_info(rng: RandomNumberGenerator) -> Dictionary:
	var saved: int = Game.gyoei_term
	var now_term: int = (Clock.month - 1) * 2 + (1 if Clock.day > 15 else 0)
	var next_term: int = 0 if now_term == 23 else now_term + 1
	var pure := {"term0": now_term, "term1": now_term, "term0_rate": 1.0}
	if absi(saved - now_term) > 1 and saved != 0 and now_term != 23:
		_renew_term(next_term, rng)
		return pure
	## Midnight on the next term's first day (the 15th for a second half), less the lead.
	var year: int = Clock.year
	var day: int = 1
	if (saved & 1) == 0:
		if saved != now_term and now_term == 23:
			year += 1
	else:
		day = 15
	var start: int = _day_number(year, (saved >> 1) + 1, day) - Game.gyoei_term_offset
	var today: int = _day_number(Clock.year, Clock.month, Clock.day)
	var past_midnight: bool = Clock.hour > 0 or Clock.minute > 0 or Clock.second > 0
	## `lbRTC_IsOverRTC`: strictly after that moment.
	var over_end: bool = today > start + TRANSITION_DAYS or (
		today == start + TRANSITION_DAYS and past_midnight
	)
	if over_end:
		_renew_term(next_term, rng)
		return pure
	var over_start: bool = today > start or (today == start and past_midnight)
	if not over_start:
		return pure
	var days_in: int = clampi(today - start, 0, TERM_RATE.size() - 1)
	return {"term0": now_term, "term1": saved, "term0_rate": float(TERM_RATE[days_in])}


static func _renew_term(term: int, rng: RandomNumberGenerator) -> void:
	Game.gyoei_term = term
	Game.gyoei_term_offset = int((rng.randf() if rng != null else 0.0) * float(TRANSITION_DAYS + 1))


static func _day_number(year: int, month: int, day: int) -> int:
	var unix: int = Time.get_unix_time_from_datetime_dict(
		{"year": year, "month": month, "day": day, "hour": 0, "minute": 0, "second": 0}
	)
	return floori(float(unix) / 86400.0)


# ---- range data ---------------------------------------------------

## `aSOG_gyoei_make_range_data`: the weighted list for one acre at this term and hour.
## Returns `[{type_index, spawn_area, weight}]`; empty for an out-of-season pond.
static func make_range_data(
	block_kind: int, raining: bool, rng: RandomNumberGenerator, tourney: int = -1
) -> Array:
	ensure_loaded()
	var info: Dictionary = chk_term_info(rng)
	var term0_rate: float = float(info["term0_rate"])
	var proc: StringName = &"pool"
	if (block_kind & KIND_MARINE) == KIND_MARINE:
		if (block_kind & KIND_OFFING) == KIND_OFFING:
			proc = &"offing"
			term0_rate = 1.0
		elif (block_kind & KIND_ISLAND) == KIND_ISLAND:
			proc = &"island"
			term0_rate = 1.0
		else:
			proc = &"sea"
	elif (block_kind & KIND_RIVER) == KIND_RIVER:
		if check_fishing_event(block_kind, rng, tourney):
			proc = &"event"
			term0_rate = 1.0
		else:
			proc = &"river"
	var slot: int = int(FishData.slot_for_hour(Clock.hour))
	var out: Array = []
	_range_proc(out, proc, slot, int(info["term0"]), false, term0_rate, raining)
	if term0_rate != 1.0:
		_range_proc(out, proc, slot, int(info["term1"]), true, 1.0 - term0_rate, raining)
	return out


## The same list for a water body, when there is no block table (authored test towns).
static func build_pool(water_kind: int, raining: bool, rng: RandomNumberGenerator = null) -> Array:
	return make_range_data(block_kind_for_water(water_kind), raining, rng if rng != null else _srng, 0)


## `aSOG_gyoei_check_fishing_event`. `tourney` < 0 reads the event calendar; 0 / 1 force it.
static func check_fishing_event(block_kind: int, rng: RandomNumberGenerator, tourney: int = -1) -> bool:
	var active: bool = tourney > 0
	if tourney < 0 and Game != null and Game.events != null:
		for id: StringName in TOURNEY_EVENTS:
			if Game.events.is_active(id):
				active = true
	if not active:
		return false
	for kind: int in TOURNEY_KINDS:
		if (kind & block_kind) == kind:
			return (rng.randf() if rng != null else 0.0) < TOURNEY_CHANCE
	return false


static func _range_proc(
	out: Array, proc: StringName, slot: int, term: int, is_next: bool, rate: float, raining: bool
) -> void:
	match proc:
		&"river":
			_copy(out, _slot_entries(term, "river", slot), rate)
		&"sea":
			_copy(out, _slot_entries(term, "sea", slot), rate)
			_add_kaseki(out, slot, is_next, raining)
		&"offing":
			_copy(out, _slot_entries(term, "sea", slot), rate)
			_add_kaseki(out, slot, is_next, raining)
			## `aSOG_gyoei_make_offing_range_data_sub` scales everything already in the list.
			for e: Dictionary in out:
				e["weight"] = float(e["weight"]) * OFFING_SCALE
			if not is_next:
				out.append({"type_index": TYPE_WHALE, "spawn_area": Area.OFFING, "weight": WHALE_WEIGHT})
		&"pool":
			_copy(out, _slot_entries(term, "pond", slot), rate)
		&"event":
			_copy(out, _raw(_event, slot), 1.0)
		&"island":
			_copy(out, _raw(_island, slot), 1.0)
			_add_kaseki(out, slot, is_next, raining)


## `aSOG_add_kaseki_range_data`: current term only, raining, not 9am–3:59pm. Unscaled by
## the term rate, so the coelacanth gets relatively rarer through a ramp.
static func _add_kaseki(out: Array, slot: int, is_next: bool, raining: bool) -> void:
	if is_next or not raining or slot == int(FishData.TimeSlot.DAY):
		return
	out.append({"type_index": TYPE_COELACANTH, "spawn_area": Area.SEA, "weight": COELACANTH_WEIGHT})


# ---- the roll -----------------------------------------------------

## `aSOG_gyoei_place_check` (GAFE01 rules: the river mouth only needs a river).
static func place_check(spawn_area: int, block_kind: int) -> bool:
	match spawn_area:
		Area.WATERFALL:
			return (block_kind & KIND_WATERFALL) == KIND_WATERFALL
		Area.POOL:
			return (block_kind & KIND_POOL) == KIND_POOL
		Area.RIVER_MOUTH:
			return (block_kind & KIND_RIVER) == KIND_RIVER
	return true


## `aSOG_gyoei_get_idx`: roll, and if the pick is a sub-area this acre lacks, strike it and
## roll again among the rest (once per entry). Returns the index into `pool`, or -1.
static func get_idx(pool: Array, block_kind: int, rng: RandomNumberGenerator) -> int:
	var tried: Array[bool] = []
	tried.resize(pool.size())
	tried.fill(false)
	var rate: float = env_rate()
	var idx: int = INVALID
	for _i: int in pool.size():
		idx = _get_idx_sub(pool, tried, block_kind, rate, rng)
		if idx == INVALID or idx != TYPE_NUM:
			break
	## Every entry failed its sub-area: the original indexes past the list and gives up.
	return INVALID if idx == TYPE_NUM else idx


static func _get_idx_sub(
	pool: Array, tried: Array[bool], block_kind: int, rate: float, rng: RandomNumberGenerator
) -> int:
	var total: float = 0.0
	for i: int in pool.size():
		if not tried[i]:
			total += float(pool[i]["weight"])
	var selected: float = total * (rng.randf() if rng != null else 0.5)
	var now: float = total
	for i: int in pool.size():
		if tried[i]:
			continue
		now -= float(pool[i]["weight"]) * rate
		if now < 0.0:
			return INVALID
		if selected >= now:
			tried[i] = true
			if not place_check(int(pool[i]["spawn_area"]), block_kind):
				return TYPE_NUM
			return i
	return INVALID


## `aSOG_gyoei_set_gyoei_data`'s per-species unit filter. `attr` is the unit's
## `mCoBG_ATTRIBUTE_*`, `bg_gx` its centre height in GX.
static func unit_accepts(type_index: int, ux: int, uz: int, attr: int, bg_gx: float) -> bool:
	if ux < INNER_MARGIN or ux >= UT - INNER_MARGIN or uz < INNER_MARGIN or uz >= UT - INNER_MARGIN:
		return false
	match type_index:
		TYPE_LARGE_CHAR:
			return attr == ATTR_WATERFALL
		TYPE_COELACANTH, TYPE_JELLYFISH, TYPE_SEA_BASS, TYPE_RED_SNAPPER, TYPE_BARRED_KNIFEJAW:
			return attr == ATTR_SEA and _deep(bg_gx)
		TYPE_SALMON, TYPE_SALMON2:
			if not is_water_attr(attr):
				return false
			return attr != ATTR_SEA or _deep(bg_gx)
		TYPE_WHALE:
			return (
				ux >= WHALE_MARGIN and ux < UT - WHALE_MARGIN
				and uz >= WHALE_MARGIN and uz < UT - WHALE_MARGIN
				and is_water_attr(attr)
			)
	return is_water_attr(attr)


static func _deep(bg_gx: float) -> bool:
	return SEA_WATER_HEIGHT_GX - bg_gx >= SEA_MIN_DEPTH_GX


## Every unit in the acre a species may spawn on. `units` is the acre's 256 rows
## (`uz * 16 + ux`), each `{"a": attr, "y": bg_gx}`.
static func candidate_units(type_index: int, units: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for uz: int in UT:
		for ux: int in UT:
			var i: int = uz * UT + ux
			if i >= units.size():
				continue
			var row: Dictionary = units[i]
			if unit_accepts(type_index, ux, uz, int(row.get("a", -1)), float(row.get("y", 0.0))):
				out.append(Vector2i(ux, uz))
	return out


## `aSOG_gyoei_decide_gyoei`: roll a species for the acre and a unit to put it on.
## Returns `{"type_index", "fish", "unit"}`, or an empty dictionary for no fish.
static func decide(
	block_kind: int, units: Array, raining: bool, rng: RandomNumberGenerator, tourney: int = -1
) -> Dictionary:
	var pool: Array = make_range_data(block_kind, raining, rng, tourney)
	if pool.is_empty():
		return {}
	var idx: int = get_idx(pool, block_kind, rng)
	if idx == INVALID:
		return {}
	var type_index: int = int(pool[idx]["type_index"])
	var cands: Array[Vector2i] = candidate_units(type_index, units)
	if cands.is_empty():
		return {}
	var unit: Vector2i = cands[int((rng.randf() if rng != null else 0.0) * float(cands.size()))]
	var fish: FishData = FishCatalog.get_by_type(type_index)
	if fish == null:
		return {}  ## the whale: an offing shadow with no catch behind it
	return {"type_index": type_index, "fish": fish, "unit": unit}


## `aSOG_gyoei_make`: where in the chosen unit the shadow appears, as a fraction of a unit
## from its north-west corner. `water_south` is whether the unit below is water.
## Every fish sits on the corner (`aSOG_get_water_attribute_position` returns the first
## water point, and the whole unit is water). The large char is pushed to the foot of its
## waterfall: half a unit across and one unit down when that is water, else unit centre.
static func spawn_offset(type_index: int, water_south: bool) -> Vector2:
	if type_index == TYPE_LARGE_CHAR:
		return Vector2(0.5, 1.0) if water_south else Vector2(0.5, 0.5)
	return Vector2.ZERO


# ---- helpers -------------------------------------------------------

static func _slot_entries(term: int, key: String, slot: int) -> Array:
	var t: Dictionary = _terms.get(str(term), {})
	return _raw(t.get(key, {}), slot)


static func _raw(table: Dictionary, slot: int) -> Array:
	var raw: Variant = table.get(str(slot), [])
	return raw if raw is Array else []


## `aSOG_gyoei_copy_range_data`.
static func _copy(out: Array, entries: Array, scale: float) -> void:
	for e: Variant in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		out.append({
			"type_index": int(e.get("type_index", -1)),
			"spawn_area": int(e.get("spawn_area", -1)),
			"weight": float(e.get("weight", 0)) * scale,
		})


static var _srng: RandomNumberGenerator = RandomNumberGenerator.new()
