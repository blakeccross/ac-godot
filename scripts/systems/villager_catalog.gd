class_name VillagerCatalog
extends RefCounted

## Loads `res://data/villagers/*.tres`. New-town pick is `mNpc_DecideLivingNpcMax`.

const DIR := "res://data/villagers"

static var _by_id: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_by_id.clear()
	var dir := DirAccess.open(DIR)
	if dir == null:
		_loaded = true
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".tres"):
			var res: Resource = load("%s/%s" % [DIR, name])
			if res is VillagerData:
				var data := res as VillagerData
				if data.id != &"":
					_by_id[data.id] = data
		name = dir.get_next()
	dir.list_dir_end()
	_loaded = true


static func reload() -> void:
	_loaded = false
	ensure_loaded()


static func get_villager(villager_id: StringName) -> VillagerData:
	ensure_loaded()
	if villager_id == &"":
		return null
	return _by_id.get(villager_id) as VillagerData


static func all_villagers() -> Array[VillagerData]:
	ensure_loaded()
	var out: Array[VillagerData] = []
	for value: Variant in _by_id.values():
		if value is VillagerData:
			out.append(value as VillagerData)
	out.sort_custom(func(a: VillagerData, b: VillagerData) -> bool: return String(a.id) < String(b.id))
	return out


static func starters() -> Array[VillagerData]:
	var out: Array[VillagerData] = []
	for villager: VillagerData in all_villagers():
		if villager.starter:
			out.append(villager)
	return out


## One of each looks from the starter pool (`mNpc_DecideLivingNpcMax`).
static func pick_starters(rng: RandomNumberGenerator, count: int = 6) -> Array[VillagerData]:
	var pool: Array[VillagerData] = starters()
	var n: int = pool.size()
	var order: PackedInt32Array = PackedInt32Array()
	order.resize(n)
	for i: int in n:
		order[i] = i
	## `mNpc_MakeRandTable(table, NPC_NUM, NPC_NUM)` — N random swaps.
	for _swap: int in n:
		if n <= 1:
			break
		var a: int = rng.randi_range(0, n - 1)
		var b: int = rng.randi_range(0, n - 1)
		var tmp: int = order[a]
		order[a] = order[b]
		order[b] = tmp
	var used_looks: Dictionary = {}
	var picked: Array[VillagerData] = []
	for i: int in n:
		if picked.size() >= count:
			break
		var villager: VillagerData = pool[order[i]]
		if villager.personality == null:
			continue
		var looks: int = int(villager.personality.looks)
		if used_looks.has(looks):
			continue
		used_looks[looks] = true
		picked.append(villager)
	return picked
