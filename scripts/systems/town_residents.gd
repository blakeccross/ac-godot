class_name TownResidents
extends RefCounted

## Who lives in town (`Save_Get(animals)` + `now_npc_max`, `m_npc.c`). Fifteen fixed slots
## in the save's order: several decomp picks walk slots in order, so the layout matters.
##
## Session start (`mSDI_StartInit` / `mSDI_StartInitAfter`) runs, in order:
##   `pick_moving_candidate` (`mNpc_SetRemoveAnimalNo`) → `force_remove` (`mNpc_ForceRemove`)
##   → `grow` (`mNpc_Grow`) → `assign_homes` (`mNpc_InitNpcData` / `mNpc_SetNpcHome`).
## The world is regenerated from its seed every load, so houses are rebuilt from these
## slots (`WorldGenerator.apply_residents`).
##
## Everything that needs the rest of the game comes in through a context dictionary so the
## rules can be tested on their own:
##   `rng` RandomNumberGenerator, `day` (`Clock.day_number`), `minute` (`Clock.absolute_minute`),
##   `met` Callable(id) → bool (the player has a memory in this animal),
##   `letters` Callable(id) → int (memories holding a letter), `field_rank` int 0–6,
##   `reserves` Array[Vector2i] (free SIGN plots, FG order), `on_goodbye` Callable(id, looks).

const ANIMAL_NUM_MAX := 15
const ANIMAL_NUM_MIN := 5
const LOOKS_NUM := 6
const NO_SLOT := 0xFF
## `mNpc_MINIMUM_DAYS_BEFORE_FORCE_REMOVAL`.
const MIN_DAYS_BEFORE_FORCE_REMOVAL := 10
## `npc_grow_prob[mFAs_FIELDRANK_NUM]` (`mNpc_CheckGrowFieldRank`).
const GROW_PROB: Array[int] = [40, 50, 60, 70, 80, 90, 100]
## `mNpc_CheckGrow`: one move-in per 24 h of clock time.
const GROW_INTERVAL_MINUTES := 24 * 60
## Relation matrix value for "no opinion yet" (`mNpc_ResetAnimalRelation`).
const RELATION_NEUTRAL := 128
## `mSex`: `mNpc_GetLooks2Sex`.
const SEX_MALE := 0
const SEX_FEMALE := 1

## Slot → {"id": StringName, "home": Vector2i (SIGN cell) or NO_HOME, "moved_in": bool}.
## An empty Dictionary is a free slot (`mNpc_CheckFreeAnimalInfo`).
var slots: Array[Dictionary] = []
var now_npc_max: int = LOOKS_NUM
## `last_grow_time` in absolute minutes; -1 is `mTM_rtcTime_clear_code`.
var last_grow_minute: int = -1
## `force_remove_date` as a day number; -1 is the cleared 0xFFFF date.
var force_remove_day: int = -1
## `remove_animal_idx`: the animal telling players it may move (memory-card transfer).
var remove_idx: int = NO_SLOT
## `npc_used_tbl`: npc_index → true for every animal that has lived here this cycle.
var appeared: Dictionary = {}
## Every SIGN plot a house has stood on. `mNpc_DestroyHouse` leaves the 3×3 empty, and the
## regenerated field would otherwise grow its template trees back.
var used_plots: Dictionary = {}
## `animal_relations[15][15]`, row = slot's opinion of each other slot.
var relations: Array[PackedByteArray] = []

const NO_HOME := Vector2i(-1, -1)


func _init() -> void:
	clear()


func clear() -> void:
	slots.clear()
	for _i: int in ANIMAL_NUM_MAX:
		slots.append({})
	relations.clear()
	for _i: int in ANIMAL_NUM_MAX:
		var row := PackedByteArray()
		row.resize(ANIMAL_NUM_MAX)
		row.fill(RELATION_NEUTRAL)
		relations.append(row)
	now_npc_max = LOOKS_NUM
	last_grow_minute = -1
	force_remove_day = -1
	remove_idx = NO_SLOT
	appeared.clear()
	used_plots.clear()


func is_empty() -> bool:
	return animal_num() == 0


func is_free(slot: int) -> bool:
	return slot < 0 or slot >= slots.size() or slots[slot].is_empty()


## `mNpc_GetAnimalNum`.
func animal_num() -> int:
	var n: int = 0
	for s: Dictionary in slots:
		if not s.is_empty():
			n += 1
	return n


func resident_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s: Dictionary in slots:
		if not s.is_empty():
			out.append(s["id"] as StringName)
	return out


func slot_of(villager_id: StringName) -> int:
	for i: int in slots.size():
		if not slots[i].is_empty() and slots[i]["id"] == villager_id:
			return i
	return -1


func has_resident(villager_id: StringName) -> bool:
	return slot_of(villager_id) >= 0


func home_of(slot: int) -> Vector2i:
	if is_free(slot):
		return NO_HOME
	return slots[slot].get("home", NO_HOME) as Vector2i


func moved_in(villager_id: StringName) -> bool:
	var i: int = slot_of(villager_id)
	return i >= 0 and bool(slots[i].get("moved_in", false))


## New town: the generator already ran `mNpc_DecideLivingNpcMax` / `mNpc_SetNpcHome`; take its
## houses in slot order (`npc_house_0`…) as the starting `animals[]`.
func adopt_from_houses(houses: Array[Dictionary]) -> void:
	clear()
	var i: int = 0
	for h: Dictionary in houses:
		if i >= ANIMAL_NUM_MAX:
			break
		var id: StringName = h.get("id", &"") as StringName
		if id == &"":
			continue
		var sign: Vector2i = h.get("home", NO_HOME) as Vector2i
		slots[i] = {"id": id, "home": sign, "moved_in": false}
		if sign != NO_HOME:
			used_plots[sign] = true
		_set_appeared(id)
		i += 1
	now_npc_max = LOOKS_NUM


## `mSDI_StartInit` + `mSDI_StartInitAfter`, the villager part.
func start_session(ctx: Dictionary) -> Dictionary:
	var report := {"removed": &"", "moved_in": &""}
	pick_moving_candidate(ctx, -1)
	report["removed"] = force_remove(ctx)
	report["moved_in"] = grow(ctx)
	assign_homes(ctx)
	return report


## `mNpc_SetRemoveAnimalNo`: choose who talks about moving away. Prefers someone every
## player has met, then anyone met, then anyone (`mNpc_DecideRemoveAnimalNo`).
func pick_moving_candidate(ctx: Dictionary, ignored_idx: int) -> void:
	if now_npc_max <= ANIMAL_NUM_MIN or remove_idx != NO_SLOT:
		return
	## One player: "met by all players" and "met by any player" are the same set.
	var pick: int = _decide_remove_friend(ctx, ignored_idx)
	if pick == -1:
		pick = _decide_remove_any(ctx, ignored_idx)
	if pick != -1:
		remove_idx = pick


## `aQMgr_order_cancel_remove`: talked out of it — pick someone else.
func cancel_moving(ctx: Dictionary) -> void:
	var was: int = remove_idx
	remove_idx = NO_SLOT
	pick_moving_candidate(ctx, was)


func _decide_remove_friend(ctx: Dictionary, ignored_idx: int) -> int:
	var met: Callable = ctx.get("met", Callable()) as Callable
	var candidates: Array[int] = []
	for i: int in ANIMAL_NUM_MAX:
		if is_free(i) or i == ignored_idx:
			continue
		if met.is_valid() and bool(met.call(slots[i]["id"])):
			candidates.append(i)
	if candidates.is_empty():
		return -1
	return candidates[_random(ctx, candidates.size())]


func _decide_remove_any(ctx: Dictionary, ignored_idx: int) -> int:
	## Decomp quirk kept: the guard is `>= 0 || < MAX`, so the count always drops by one,
	## and landing on `ignored_idx` just keeps counting down.
	var n: int = now_npc_max - 1
	if n <= 0 or n > ANIMAL_NUM_MAX:
		return -1
	var selected: int = _random(ctx, n)
	for i: int in ANIMAL_NUM_MAX:
		if is_free(i):
			continue
		if selected <= 0 and ignored_idx != i:
			return i
		selected -= 1
	return -1


## `mNpc_ForceRemove`: with all fifteen homes full and ten days since the last arrival or
## departure, the animal with the fewest memories leaves, mailing every player goodbye.
## Returns the id that left, or &"".
func force_remove(ctx: Dictionary) -> StringName:
	if animal_num() != ANIMAL_NUM_MAX or force_remove_day < 0:
		return &""
	var day: int = int(ctx.get("day", 0))
	if absi(day - force_remove_day) < MIN_DAYS_BEFORE_FORCE_REMOVAL:
		return &""
	var idx: int = goodbye_index(ctx, -1)
	if idx == -1 or is_free(idx):
		return &""
	var gone: StringName = slots[idx]["id"] as StringName
	var on_goodbye: Callable = ctx.get("on_goodbye", Callable()) as Callable
	if on_goodbye.is_valid():
		on_goodbye.call(gone, _looks_of(gone))
	slots[idx] = {}
	if remove_idx == idx:
		remove_idx = NO_SLOT
	_sub_npc_max()
	force_remove_day = day
	return gone


## `mNpc_GetGoodbyAnimalIdx`: fewest memories, then fewest letters, then fewest towns
## remembered, then the looks the town has most of. Ties draw at random. The decomp's
## tie branch also absorbs an animal whose looks is *rarer*; that is kept.
func goodbye_index(ctx: Dictionary, ignored_idx: int) -> int:
	var bitfield: Array[int] = []
	var other: int = -1
	var chosen: int = -1
	for i: int in ANIMAL_NUM_MAX:
		if i == remove_idx or is_free(i):
			continue
		if ignored_idx >= 0 and ignored_idx < ANIMAL_NUM_MAX and i == ignored_idx:
			continue
		if other == -1:
			bitfield = [i]
			other = i
			chosen = i
			continue
		## `remove_exp` is never set in the retail game, so only the memory branch runs.
		match _compare_goodbye(ctx, i, other):
			-1:
				bitfield.append(i)
			1:
				bitfield = [i]
				other = i
				chosen = i
	if bitfield.size() > 1:
		chosen = bitfield[_random(ctx, bitfield.size())]
	return chosen


## `mNpc_CheckGoodbyAnimalMemoryNum(a0 = candidate, a1 = current pick)`.
func _compare_goodbye(ctx: Dictionary, a0: int, a1: int) -> int:
	var id0: StringName = slots[a0]["id"]
	var id1: StringName = slots[a1]["id"]
	var m0: int = _memory_num(ctx, id0)
	var m1: int = _memory_num(ctx, id1)
	if m1 > m0:
		return 1
	if m1 != m0:
		return 0
	var l0: int = _letter_num(ctx, id0)
	var l1: int = _letter_num(ctx, id1)
	if l1 > l0:
		return 1
	if l1 != l0:
		return 0
	## `mNpc_GetAnimalMemoryLandKindNum` counts every used memory (its dedup never feeds
	## the total), so it equals the memory count and cannot break the tie.
	var s0: int = same_looks_num(_looks_of(id0))
	var s1: int = same_looks_num(_looks_of(id1))
	return 1 if s1 < s0 else -1


func _memory_num(ctx: Dictionary, id: StringName) -> int:
	var met: Callable = ctx.get("met", Callable()) as Callable
	return 1 if met.is_valid() and bool(met.call(id)) else 0


func _letter_num(ctx: Dictionary, id: StringName) -> int:
	var letters: Callable = ctx.get("letters", Callable()) as Callable
	return int(letters.call(id)) if letters.is_valid() else 0


## `mNpc_Grow`: at most one arrival per day, only while the town has room, only once the
## player has met everyone living here, and only on a roll set by the town rating. The
## newcomer's looks is whichever the town has fewest of; ties lean to the sex with more
## residents (`mNpc_GetMinSex` compares the wrong way round — kept).
func grow(ctx: Dictionary) -> StringName:
	if not _check_grow(ctx):
		return &""
	_reset_have_appeared_if_exhausted()
	last_grow_minute = int(ctx.get("minute", 0))
	var min_info: Dictionary = _min_looks()
	var looks: int = int(min_info["looks"])
	if looks == -1:
		var bits: Array[int] = min_info["bits"]
		var min_sex: int = _min_sex()
		var kept: Array[int] = []
		for l: int in bits:
			if looks_sex(l) == min_sex:
				kept.append(l)
		if not kept.is_empty() and kept.size() != bits.size():
			bits = kept
		looks = bits[_random(ctx, bits.size())]
	var slot: int = _set_grow_npc(ctx, looks)
	if slot < 0:
		return &""
	_add_npc_max()
	force_remove_day = int(ctx.get("day", 0))
	return slots[slot]["id"] as StringName


## `mNpc_CheckGrow`. The first call only stamps the clock.
func _check_grow(ctx: Dictionary) -> bool:
	if now_npc_max >= ANIMAL_NUM_MAX:
		return false
	var minute: int = int(ctx.get("minute", 0))
	if last_grow_minute < 0:
		last_grow_minute = minute
		return false
	var rank: int = int(ctx.get("field_rank", 3))
	if rank < 0 or rank >= GROW_PROB.size():
		return false
	if _random(ctx, 100) >= GROW_PROB[rank]:
		return false
	if absi(minute - last_grow_minute) < GROW_INTERVAL_MINUTES:
		return false
	## `mNpc_CheckFriendAllAnimal`: met at least `now_npc_max` animals.
	var met: Callable = ctx.get("met", Callable()) as Callable
	var friends: int = 0
	for id: StringName in resident_ids():
		if met.is_valid() and bool(met.call(id)):
			friends += 1
	return now_npc_max <= friends


## `mNpc_GetMinLooks`. Returns {"looks": index or -1 for a tie, "bits": tied looks}.
func _min_looks() -> Dictionary:
	var best: int = ANIMAL_NUM_MAX
	var bits: Array[int] = []
	for l: int in LOOKS_NUM:
		if _not_appeared_num(l) <= 0:
			continue
		var same: int = same_looks_num(l)
		if best > same:
			best = same
			bits = [l]
		elif best == same:
			bits.append(l)
	if bits.is_empty():
		## Everyone has lived here: start the cycle over from today's residents.
		_reset_have_appeared()
		for l: int in LOOKS_NUM:
			bits.append(l)
	return {"looks": bits[0] if bits.size() == 1 else -1, "bits": bits}


## `mNpc_GetMinSex`.
func _min_sex() -> int:
	var males: int = 0
	var females: int = 0
	for id: StringName in resident_ids():
		match looks_sex(_looks_of(id)):
			SEX_MALE:
				males += 1
			SEX_FEMALE:
				females += 1
	return SEX_MALE if females < males else SEX_FEMALE


## `mNpc_SetGrowNpc` + `mNpc_GrowLooksNpcIdx`: first free slot, then a random animal of
## that looks (in NPC table order) that isn't here, hasn't lived here this cycle, and may
## move in (`mNpc_GROW_STARTER` / `_MOVE_IN`; islanders never do).
func _set_grow_npc(ctx: Dictionary, looks: int) -> int:
	var slot: int = -1
	for i: int in ANIMAL_NUM_MAX:
		if is_free(i):
			slot = i
			break
	if slot == -1:
		return -1
	_reset_relation(slot)
	var candidates: Array[VillagerData] = []
	for v: VillagerData in _table_order():
		if _looks_of_data(v) != looks:
			continue
		if v.islander or has_resident(v.id) or appeared.has(v.npc_index):
			continue
		candidates.append(v)
	if candidates.is_empty():
		return -1
	var pick: VillagerData = candidates[_random(ctx, candidates.size())]
	slots[slot] = {"id": pick.id, "home": NO_HOME, "moved_in": true}
	_set_appeared(pick.id)
	return slot


## `mNpc_InitNpcData` / `mNpc_SetNpcHome`: anyone without a house takes a free SIGN plot,
## plots drawn through `mNpc_MakeRandTable(reserved_num, 30)`.
func assign_homes(ctx: Dictionary) -> Array[int]:
	var built: Array[int] = []
	var reserves: Array[Vector2i] = []
	for r: Variant in ctx.get("reserves", []) as Array:
		reserves.append(r as Vector2i)
	var taken: Dictionary = {}
	for i: int in ANIMAL_NUM_MAX:
		if not is_free(i) and home_of(i) != NO_HOME:
			taken[home_of(i)] = true
	var free: Array[Vector2i] = []
	for r: Vector2i in reserves:
		if not _under_house(r, taken):
			free.append(r)
	var count: int = mini(free.size(), 60)
	if count <= 0:
		return built
	var table: PackedInt32Array = make_rand_table(ctx, count, 30)
	var n: int = 0
	for i: int in ANIMAL_NUM_MAX:
		if n >= count:
			break
		if is_free(i) or home_of(i) != NO_HOME:
			continue
		var plot: Vector2i = free[table[n]]
		slots[i]["home"] = plot
		used_plots[plot] = true
		built.append(i)
		n += 1
	return built


## A built house writes its whole 3×3 (`mNpc_BuildHouseBeforeFieldct`), so a reserve inside
## it is no longer `mNT_IS_RESERVE`.
static func _under_house(plot: Vector2i, taken: Dictionary) -> bool:
	for t: Variant in taken.keys():
		var d: Vector2i = plot - (t as Vector2i)
		if absi(d.x) <= 1 and absi(d.y) <= 1:
			return true
	return false


## `mNpc_MakeRandTable`: identity table, then `swap_num` random swaps.
static func make_rand_table(ctx: Dictionary, count: int, swap_num: int) -> PackedInt32Array:
	var table := PackedInt32Array()
	table.resize(count)
	for i: int in count:
		table[i] = i
	for _s: int in swap_num:
		var a: int = _random(ctx, count)
		var b: int = _random(ctx, count)
		var tmp: int = table[a]
		table[a] = table[b]
		table[b] = tmp
	return table


## `mNpc_GetSameLooksNum`.
func same_looks_num(looks: int) -> int:
	var n: int = 0
	for id: StringName in resident_ids():
		if _looks_of(id) == looks:
			n += 1
	return n


## `mNpc_GetLooks2Sex`: normal / peppy / snooty are female, lazy / jock / cranky male.
static func looks_sex(looks: int) -> int:
	match looks:
		VillagerPersonality.Looks.NORMAL, VillagerPersonality.Looks.PEPPY, VillagerPersonality.Looks.SNOOTY:
			return SEX_FEMALE
		_:
			return SEX_MALE


func relation(from_slot: int, to_slot: int) -> int:
	return int(relations[from_slot][to_slot])


func set_relation(from_slot: int, to_slot: int, value: int) -> void:
	var row: PackedByteArray = relations[from_slot]
	row[to_slot] = clampi(value, 0, 255)
	relations[from_slot] = row


## `mNpc_ResetAnimalRelation`.
func _reset_relation(idx: int) -> void:
	var own: PackedByteArray = relations[idx]
	own.fill(RELATION_NEUTRAL)
	relations[idx] = own
	for i: int in ANIMAL_NUM_MAX:
		if i != idx:
			set_relation(i, idx, RELATION_NEUTRAL)


func _not_appeared_num(looks: int) -> int:
	var n: int = 0
	for v: VillagerData in _table_order():
		if _looks_of_data(v) == looks and not v.islander and not appeared.has(v.npc_index):
			n += 1
	return n


## `mNpc_ResetHaveAppeared`: once every non-islander has lived here, start over.
func _reset_have_appeared_if_exhausted() -> void:
	for v: VillagerData in _table_order():
		if not v.islander and not appeared.has(v.npc_index):
			return
	_reset_have_appeared()


func _reset_have_appeared() -> void:
	appeared.clear()
	for id: StringName in resident_ids():
		_set_appeared(id)


func _set_appeared(id: StringName) -> void:
	var v: VillagerData = VillagerCatalog.get_villager(id)
	if v != null and v.npc_index >= 0:
		appeared[v.npc_index] = true


func _add_npc_max() -> void:
	if now_npc_max < ANIMAL_NUM_MAX:
		now_npc_max += 1


func _sub_npc_max() -> void:
	if now_npc_max > ANIMAL_NUM_MIN:
		now_npc_max -= 1


func _looks_of(id: StringName) -> int:
	return _looks_of_data(VillagerCatalog.get_villager(id))


static func _looks_of_data(v: VillagerData) -> int:
	if v == null or v.personality == null:
		return -1
	return int(v.personality.looks)


static func _table_order() -> Array[VillagerData]:
	var out: Array[VillagerData] = VillagerCatalog.all_villagers()
	out.sort_custom(func(a: VillagerData, b: VillagerData) -> bool: return a.npc_index < b.npc_index)
	return out


static func _random(ctx: Dictionary, n: int) -> int:
	if n <= 1:
		return 0
	var rng: RandomNumberGenerator = ctx.get("rng", null) as RandomNumberGenerator
	if rng == null:
		return randi() % n
	return rng.randi_range(0, n - 1)


func to_save() -> Dictionary:
	var rows: Array = []
	for s: Dictionary in slots:
		if s.is_empty():
			rows.append({})
			continue
		var home: Vector2i = s.get("home", NO_HOME) as Vector2i
		rows.append({"id": String(s["id"]), "home": [home.x, home.y], "moved_in": bool(s.get("moved_in", false))})
	var rel: Array = []
	for row: PackedByteArray in relations:
		rel.append(Array(row))
	var plots: Array = []
	for p: Variant in used_plots.keys():
		plots.append([(p as Vector2i).x, (p as Vector2i).y])
	return {
		"slots": rows,
		"now_npc_max": now_npc_max,
		"last_grow_minute": last_grow_minute,
		"force_remove_day": force_remove_day,
		"remove_idx": remove_idx,
		"appeared": appeared.keys(),
		"used_plots": plots,
		"relations": rel,
	}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var bag: Dictionary = data
	var rows: Array = bag.get("slots", []) as Array
	for i: int in mini(rows.size(), ANIMAL_NUM_MAX):
		var row: Variant = rows[i]
		if typeof(row) != TYPE_DICTIONARY or (row as Dictionary).is_empty():
			continue
		var home_raw: Array = (row as Dictionary).get("home", [-1, -1]) as Array
		var home := NO_HOME
		if home_raw.size() >= 2:
			home = Vector2i(int(home_raw[0]), int(home_raw[1]))
		slots[i] = {
			"id": StringName(str((row as Dictionary).get("id", ""))),
			"home": home,
			"moved_in": bool((row as Dictionary).get("moved_in", false)),
		}
	now_npc_max = clampi(int(bag.get("now_npc_max", LOOKS_NUM)), ANIMAL_NUM_MIN, ANIMAL_NUM_MAX)
	last_grow_minute = int(bag.get("last_grow_minute", -1))
	force_remove_day = int(bag.get("force_remove_day", -1))
	remove_idx = int(bag.get("remove_idx", NO_SLOT))
	for n: Variant in bag.get("appeared", []) as Array:
		appeared[int(n)] = true
	for p: Variant in bag.get("used_plots", []) as Array:
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
			used_plots[Vector2i(int((p as Array)[0]), int((p as Array)[1]))] = true
	var rel: Array = bag.get("relations", []) as Array
	for i: int in mini(rel.size(), ANIMAL_NUM_MAX):
		var r: Array = rel[i] as Array
		for j: int in mini(r.size(), ANIMAL_NUM_MAX):
			set_relation(i, j, int(r[j]))
