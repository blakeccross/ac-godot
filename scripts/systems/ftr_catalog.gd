class_name FtrCatalog
extends RefCounted

## The disc's furniture by number (`FTR_NUM` = 1266), from the pipeline's `ftr_catalog.json`:
## name, catalog price, converted model and "birth type" — the list that hands it out
## (`mRmTp_birth_type[]`: Nook's groups, events, Jingle, Gulliver's `jonason`, …). Event
## gifts and prizes draw from these lists (`mSP_SelectRandomItem_New` with a `mSP_LISTTYPE_*`).
##
## Every entry is registered as a `FurnitureData` `ftr_<index>` so it can sit in the pockets
## and a room. They carry `birth` so Nook's own pools (authored furniture) stay as they are.

const PATH := "res://assets/generated/items/ftr_catalog.json"
const ID_PREFIX := "ftr_"

static var _rows: Array = []
static var _goods: Dictionary = {}
static var _lists: Dictionary = {}
static var _catalog: Dictionary = {}
static var _loaded: bool = false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		var d: Dictionary = parsed
		_rows = d.get("items", [])
		for kind: String in ["carpet", "wall", "cloth"]:
			_goods[kind] = d.get(kind, [])
		_lists = d.get("lists", {})
		_catalog = d.get("catalog", {})


static func available() -> bool:
	_ensure()
	return not _rows.is_empty()


static func count() -> int:
	_ensure()
	return _rows.size()


static func item_id(index: int) -> StringName:
	return StringName("%s%d" % [ID_PREFIX, index])


static func index_of(id: StringName) -> int:
	var raw := String(id)
	if not raw.begins_with(ID_PREFIX) or not raw.substr(ID_PREFIX.length()).is_valid_int():
		return -1
	return int(raw.substr(ID_PREFIX.length()))


static func row(index: int) -> Dictionary:
	_ensure()
	if index < 0 or index >= _rows.size():
		return {}
	return _rows[index]


## Item ids of every piece whose birth type is `birth` (`jonason`, `santa`, `halloween`, …).
static func list(birth: String) -> Array[StringName]:
	_ensure()
	var out: Array[StringName] = []
	for r: Variant in _rows:
		var d: Dictionary = r
		if str(d.get("birth", "")) == birth:
			out.append(item_id(int(d["index"])))
	return out


## `mSP_SelectRandomItem_New`-style: one piece from `birth`'s list not in `exclude`
## (falls back to the whole list when all are excluded).
static func pick(birth: String, rng: RandomNumberGenerator, exclude: Array = []) -> StringName:
	var pool: Array[StringName] = list(birth)
	if pool.is_empty():
		return &""
	var open: Array[StringName] = []
	for id: StringName in pool:
		if not exclude.has(id):
			open.append(id)
	if open.is_empty():
		open = pool
	return open[rng.randi_range(0, open.size() - 1)]


## Item id for entry `index` of `kind`: furniture `ftr_<n>`, carpet `floor_NN` / wallpaper
## `wall_NN` (the room style ids), clothing `shirt_NNN`.
static func goods_id(kind: String, index: int) -> StringName:
	match kind:
		"ftr":
			return item_id(index)
		"carpet":
			return InteriorStyleCatalog.floor_style_id(index)
		"wall":
			return InteriorStyleCatalog.wall_style_id(index)
		"cloth":
			return StringName("shirt_%03d" % index)
	return &""


## A named shop list (`ftr_listJonason`, `carpet_listEvent`, …) as item ids.
static func named_list(kind: String, label: String) -> Array[StringName]:
	_ensure()
	var out: Array[StringName] = []
	for i: Variant in (_lists.get(kind, {}) as Dictionary).get(label, []):
		out.append(goods_id(kind, int(i)))
	return out


## `mSP_SelectRandomItem_New(kind, list)`: one id from the named list, avoiding `exclude`.
static func pick_named(kind: String, label: String, rng: RandomNumberGenerator, exclude: Array = []) -> StringName:
	var pool: Array[StringName] = named_list(kind, label)
	if pool.is_empty():
		return &""
	var open: Array[StringName] = []
	for id: StringName in pool:
		if not exclude.has(id):
			open.append(id)
	if open.is_empty():
		open = pool
	return open[rng.randi_range(0, open.size() - 1)]


## `m_catalog_ovl_data.c_inc`: catalog page `page` (`ftr`, `wall`, `carpet`, `cloth`,
## `umbrella`, `paper`, `haniwa`, `fossil`, `music`) in page order, as the disc indices.
static func catalog_page(page: String) -> Array[int]:
	_ensure()
	var out: Array[int] = []
	for i: Variant in _catalog.get(page, []):
		out.append(int(i))
	return out


## Called from `ItemCatalog.ensure_loaded`.
static func register_items() -> void:
	_ensure()
	var categories: Dictionary = {
		"carpet": ItemData.Category.FLOOR, "wall": ItemData.Category.WALL, "cloth": ItemData.Category.CLOTH,
	}
	for kind: String in categories:
		for r: Variant in _goods.get(kind, []):
			var g: Dictionary = r
			var gid: StringName = goods_id(kind, int(g["index"]))
			var existing: ItemData = ItemCatalog.get_item(gid)
			if existing != null and not existing.from_disc:
				## Authored entry wins.
				continue
			var data := ItemData.new()
			data.id = gid
			data.display_name = str(g.get("name", ""))
			data.category = categories[kind]
			data.buy_price = int(g.get("price", 0))
			data.from_disc = true
			if kind == "cloth":
				data.cloth_index = int(g["index"])
			ItemCatalog.remember(data)
	for r: Variant in _rows:
		var d: Dictionary = r
		var data := FurnitureData.new()
		data.id = item_id(int(d["index"]))
		data.display_name = str(d.get("name", ""))
		data.visual_id = StringName(str(d.get("visual", "")))
		data.category = ItemData.Category.FURNITURE
		data.buy_price = int(d.get("price", 0))
		data.birth = str(d.get("birth", ""))
		data.from_disc = true
		data.footprint = Vector2i.ZERO
		data.infer_from_visual()
		ItemCatalog.remember(data)
