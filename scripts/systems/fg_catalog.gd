class_name FgCatalog
extends RefCounted

## Disc FG acre templates (`RESOURCE_FGDATA` / `fgdata.bin`) + `data_combi` rows.
## Gitignored under `assets/generated/environment/fg/catalog.json`.

const CATALOG_PATH := "res://assets/generated/environment/fg/catalog.json"
const UT := 16
const ITEMS_PER_ACRE := UT * UT

## `m_name_table.h` environmental / rock ids we place in this slice.
const ITEM_TREE := 0x0804
const ITEM_TREE_APPLE_FRUIT := 0x080C
const ITEM_CEDAR_TREE := 0x0861
const ITEM_TREE_PALM_FRUIT := 0x085B
const ITEM_FLOWER_PANSIES0 := 0x0845
const ITEM_FLOWER_PANSIES1 := 0x0846
const ITEM_FLOWER_PANSIES2 := 0x0847
const ITEM_FLOWER_COSMOS0 := 0x0848
const ITEM_FLOWER_COSMOS1 := 0x0849
const ITEM_FLOWER_COSMOS2 := 0x084A
const ITEM_FLOWER_TULIP0 := 0x084B
const ITEM_FLOWER_TULIP1 := 0x084C
const ITEM_FLOWER_TULIP2 := 0x084D
const ITEM_ROCK_A := 0x0063
const ITEM_ROCK_E := 0x0067
const ITEM_EMPTY := 0x0000
const ITEM_NONE := 0xFFFF
const FG_TYPE_EMPTY := 0x00CB

static var _loaded := false
static var _templates: Dictionary = {} ## int fg_id → PackedInt32Array(256)
static var _combis: Array = [] ## {bg, fg, type}


static func has_catalog() -> bool:
	_ensure()
	return not _templates.is_empty() and not _combis.is_empty()


static func pick_fg_id(bg_name: StringName, block_type: int, variant: int) -> int:
	## Prefer combi rows whose BG matches the acre mesh and type matches the acre.
	_ensure()
	if _combis.is_empty():
		return -1
	var bg := String(bg_name)
	if bg.is_empty():
		return -1
	var exact: Array[int] = []
	var bg_only: Array[int] = []
	for row: Variant in _combis:
		var d: Dictionary = row
		if String(d.get("bg", "")) != bg:
			continue
		var fg: int = int(d.get("fg", -1))
		if fg < 0 or fg == FG_TYPE_EMPTY or not _templates.has(fg):
			continue
		if int(d.get("type", -1)) == block_type:
			exact.append(fg)
		else:
			bg_only.append(fg)
	var pool: Array[int] = exact if not exact.is_empty() else bg_only
	if pool.is_empty():
		return -1
	## Prefer templates that actually plant something when ties exist.
	var with_props: Array[int] = []
	for fg: int in pool:
		if _placeable_count(fg) > 0:
			with_props.append(fg)
	if not with_props.is_empty():
		pool = with_props
	return pool[posmod(variant, pool.size())]


static func items(fg_id: int) -> PackedInt32Array:
	_ensure()
	if not _templates.has(fg_id):
		return PackedInt32Array()
	return _templates[fg_id] as PackedInt32Array


static func placement_for_item(item_id: int) -> Dictionary:
	## kind + visual_id for WorldGenerator / WorldBuilder. Empty = skip.
	if item_id == ITEM_EMPTY or item_id == ITEM_NONE or item_id == 0xFFFE:
		return {}
	if item_id == ITEM_TREE:
		return {"kind": &"tree", "visual": &"TREE", "tree": &"hardwood"}
	if item_id == ITEM_CEDAR_TREE:
		return {"kind": &"tree", "visual": &"CEDAR_TREE", "tree": &"cedar"}
	if item_id == ITEM_TREE_APPLE_FRUIT:
		return {"kind": &"tree", "visual": &"TREE_APPLE_FRUIT", "tree": &"apple"}
	if item_id == ITEM_TREE_PALM_FRUIT or (item_id >= 0x0854 and item_id <= 0x085B):
		return {"kind": &"tree", "visual": &"TREE_PALM_FRUIT", "tree": &"palm"}
	if item_id >= ITEM_FLOWER_PANSIES0 and item_id <= ITEM_FLOWER_TULIP2:
		var flower_visuals: Array[StringName] = [
			&"FLOWER_PANSIES0",
			&"FLOWER_PANSIES1",
			&"FLOWER_PANSIES2",
			&"FLOWER_PANSIES0",
			&"FLOWER_PANSIES1",
			&"FLOWER_PANSIES2",
			&"FLOWER_PANSIES0",
			&"FLOWER_PANSIES1",
			&"FLOWER_PANSIES2",
		]
		return {
			"kind": &"flower",
			"visual": flower_visuals[item_id - ITEM_FLOWER_PANSIES0],
		}
	if item_id >= ITEM_ROCK_A and item_id <= ITEM_ROCK_E:
		var rock_visuals: Array[StringName] = [
			&"ROCK_A", &"ROCK_B", &"ROCK_C", &"ROCK_D", &"ROCK_E"
		]
		return {"kind": &"rock", "visual": rock_visuals[item_id - ITEM_ROCK_A]}
	return {}


static func _placeable_count(fg_id: int) -> int:
	var arr: PackedInt32Array = items(fg_id)
	var n := 0
	for i: int in arr.size():
		if not placement_for_item(arr[i]).is_empty():
			n += 1
	return n


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_templates.clear()
	_combis.clear()
	if not FileAccess.file_exists(CATALOG_PATH):
		return
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root: Dictionary = parsed
	var t: Variant = root.get("templates", {})
	if typeof(t) == TYPE_DICTIONARY:
		for key: Variant in t:
			var fid: int = int(str(key))
			var raw: Variant = t[key]
			if typeof(raw) != TYPE_ARRAY:
				continue
			var packed := PackedInt32Array()
			packed.resize(ITEMS_PER_ACRE)
			var arr: Array = raw
			for i: int in mini(ITEMS_PER_ACRE, arr.size()):
				packed[i] = int(arr[i])
			_templates[fid] = packed
	var c: Variant = root.get("combis", [])
	if typeof(c) == TYPE_ARRAY:
		_combis = c
