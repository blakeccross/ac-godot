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
		_rows = (parsed as Dictionary).get("items", [])


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


## Called from `ItemCatalog.ensure_loaded`.
static func register_items() -> void:
	_ensure()
	for r: Variant in _rows:
		var d: Dictionary = r
		var data := FurnitureData.new()
		data.id = item_id(int(d["index"]))
		data.display_name = str(d.get("name", ""))
		data.visual_id = StringName(str(d.get("visual", "")))
		data.category = ItemData.Category.FURNITURE
		data.buy_price = int(d.get("price", 0))
		data.birth = str(d.get("birth", ""))
		data.footprint = Vector2i.ZERO
		data.infer_from_visual()
		ItemCatalog.remember(data)
