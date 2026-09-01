class_name FgCatalog
extends RefCounted

## Disc FG acre templates (`RESOURCE_FGDATA` / `fgdata.bin`) + `data_combi` rows.
## Gitignored under `assets/generated/environment/fg/catalog.json`.

const CATALOG_PATH := "res://assets/generated/environment/fg/catalog.json"
const UT := 16
const ITEMS_PER_ACRE := UT * UT

## `m_name_table.h` environmental / rock ids we place in this slice.
const ITEM_TREE_SAPLING := 0x0800
const ITEM_TREE := 0x0804
const ITEM_TREE_APPLE_SAPLING := 0x0805
const ITEM_TREE_APPLE_FRUIT := 0x080C
const ITEM_TREE_30000BELLS := 0x083B
const ITEM_TREE_100BELLS_SAPLING := 0x084F
const ITEM_TREE_100BELLS := 0x0853
const ITEM_TREE_PALM_SAPLING := 0x0854
const ITEM_TREE_PALM_FRUIT := 0x085B
const ITEM_CEDAR_TREE_SAPLING := 0x085D
const ITEM_CEDAR_TREE := 0x0861
const ITEM_GOLD_TREE_SAPLING := 0x0863
const ITEM_GOLD_TREE := 0x0868
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
## Structure FG ids (`m_name_table.h` STRUCTURE_START = 0x5800).
const ITEM_HOUSE0 := 0x5800
const ITEM_HOUSE1 := 0x5801
const ITEM_HOUSE2 := 0x5802
const ITEM_HOUSE3 := 0x5803
const ITEM_SHOP0 := 0x5804
const ITEM_POST_OFFICE := 0x5808
const ITEM_TRAIN_STATION := 0x5809
const ITEM_POLICE_STATION := 0x580C
const ITEM_SIGN00 := 0x5810
const ITEM_SIGN20 := 0x5824
const ITEM_WISHING_WELL := 0x5825
const ITEM_MUSEUM := 0x584A
const ITEM_NEEDLEWORK_SHOP := 0x584D
const ITEM_WATERFALL_SOUTH := 0x580D
const ITEM_WATERFALL_EAST := 0x580E
const ITEM_WATERFALL_WEST := 0x580F

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
	var tree: Dictionary = _tree_place(item_id)
	if not tree.is_empty():
		return tree
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
	## Villager house plot reserves (`mNT_IS_RESERVE` / SIGN00–SIGN20).
	if item_id >= ITEM_SIGN00 and item_id <= ITEM_SIGN20:
		return {"kind": &"reserve", "visual": &"SIGNBOARD"}
	if item_id >= ITEM_HOUSE0 and item_id <= ITEM_HOUSE3:
		return _player_house_place(item_id - ITEM_HOUSE0)
	match item_id:
		ITEM_SHOP0:
			return {
				"kind": &"structure",
				"building": &"shop",
				"visual": &"obj_s_shop1",
				"label": "Shop",
				"foot": Vector2i(2, 2),
				"nw_off": Vector2i(-1, 0),
				"occupy": false,
			}
		ITEM_POST_OFFICE:
			return {
				"kind": &"structure",
				"building": &"building",
				"visual": &"obj_s_yubinkyoku",
				"label": "Post Office",
				"foot": Vector2i(2, 2),
				"nw_off": Vector2i(-1, 0),
			}
		ITEM_TRAIN_STATION:
			return {
				"kind": &"structure",
				"building": &"building",
				"visual": &"obj_s_station1",
				"label": "Train Station",
				"foot": Vector2i(1, 1),
				"nw_off": Vector2i(0, 0),
				"occupy": false,
				## `aSTA_actor_ct`: unit center + −20 GX X (`mFI_UT_WORLDSIZE_HALF_X_F`).
				"actor_shift": Vector2(-0.5, 0.0),
			}
		ITEM_POLICE_STATION:
			return {
				"kind": &"structure",
				"building": &"building",
				"visual": &"obj_s_kouban",
				"label": "Police Station",
				"foot": Vector2i(3, 3),
				"nw_off": Vector2i(-1, -1),
			}
		ITEM_WISHING_WELL:
			return {
				"kind": &"structure",
				"building": &"building",
				"visual": &"obj_s_shrine",
				"label": "Wishing Well",
				"foot": Vector2i(2, 2),
				"nw_off": Vector2i(0, -1),
			}
		ITEM_MUSEUM:
			return {
				"kind": &"structure",
				"building": &"building",
				"visual": &"obj_s_museum",
				"label": "Museum",
				"foot": Vector2i(2, 2),
				"nw_off": Vector2i(0, 0),
			}
		ITEM_NEEDLEWORK_SHOP:
			return {
				"kind": &"structure",
				"building": &"building",
				"visual": &"obj_s_tailor",
				"label": "Able Sisters",
				"foot": Vector2i(2, 2),
				"nw_off": Vector2i(-1, 0),
				"door_verb": &"shop",
			}
		ITEM_WATERFALL_SOUTH:
			return {"kind": &"waterfall", "visual": &"obj_fallS"}
		ITEM_WATERFALL_EAST:
			return {"kind": &"waterfall", "visual": &"obj_fallSE"}
		ITEM_WATERFALL_WEST:
			return {"kind": &"waterfall", "visual": &"obj_fallSE"}
	return {}


static func _tree_place(item_id: int) -> Dictionary:
	## `IS_ITEM_TREE` families. Fruit/cedar passes still convert only visual `TREE`.
	if item_id >= ITEM_CEDAR_TREE_SAPLING and item_id <= ITEM_CEDAR_TREE:
		return {"kind": &"tree", "visual": &"CEDAR_TREE", "tree": &"cedar"}
	if item_id >= ITEM_TREE_PALM_SAPLING and item_id <= ITEM_TREE_PALM_FRUIT:
		return {"kind": &"tree", "visual": &"TREE_PALM_FRUIT", "tree": &"palm"}
	if item_id >= ITEM_TREE_APPLE_SAPLING and item_id <= ITEM_TREE_APPLE_FRUIT:
		return {"kind": &"tree", "visual": &"TREE_APPLE_FRUIT", "tree": &"apple"}
	if (
		(item_id >= ITEM_TREE_SAPLING and item_id <= ITEM_TREE)
		or (item_id > ITEM_TREE_APPLE_FRUIT and item_id <= ITEM_TREE_30000BELLS)
		or (item_id >= ITEM_TREE_100BELLS_SAPLING and item_id <= ITEM_TREE_100BELLS)
		or (item_id >= ITEM_GOLD_TREE_SAPLING and item_id <= ITEM_GOLD_TREE)
	):
		return {"kind": &"tree", "visual": &"TREE", "tree": &"hardwood"}
	return {}


static func _player_house_place(house_idx: int) -> Dictionary:
	## FG_TYPE_0069 / GRD_S_F_MH_*: HOUSE0 (3,3), HOUSE1 (12,3), HOUSE2 (3,10), HOUSE3 (12,10).
	## `aMHS_posX_table`: west plots +20 X, east plots −20 X; both +20 Z. `angle_table` is
	## +90° Y on west plots — Godot `WEST` (`+PI/2`), not `EAST` (`−PI/2`).
	var west: bool = (house_idx & 1) == 0
	var id: StringName = &"player_house"
	if house_idx != 0:
		id = StringName("player_house_%d" % house_idx)
	return {
		"kind": &"structure",
		"building": &"house",
		"visual": &"obj_s_myhome1",
		"label": "House",
		"id": id,
		"foot": Vector2i(2, 2),
		"nw_off": Vector2i(0, 0) if west else Vector2i(-1, 0),
		"mesh_facing": WorldGrid.Facing.WEST if west else WorldGrid.Facing.SOUTH,
	}


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
