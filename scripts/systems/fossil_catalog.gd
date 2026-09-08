class_name FossilCatalog
extends RefCounted

## Identified fossils (`FTR_DIN_*`). The raw dug item is the generic `fossil`; once the
## Farway Museum examines it, it comes back as one of these — a `FurnitureData` keyed to
## a `MuseumDisplay.FOSSIL_VISUALS` entry, so it is placeable, sellable, and donatable.

const DATA_PATH := "res://data/fossils.json"

static var _rows: Array[Dictionary] = []
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_rows.clear()
	var raw: Variant = null
	if FileAccess.file_exists(DATA_PATH):
		raw = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(raw) == TYPE_DICTIONARY and (raw as Dictionary).get("fossils") is Array:
		for entry: Variant in (raw as Dictionary)["fossils"]:
			if typeof(entry) == TYPE_DICTIONARY:
				_rows.append(entry as Dictionary)
	else:
		## Fallback: name straight off the display table so the loop still works.
		for i: int in MuseumDisplay.FOSSIL_VISUALS.size():
			var v := String(MuseumDisplay.FOSSIL_VISUALS[i])
			_rows.append({
				"index": i,
				"visual_id": v,
				"id": "fossil_%s" % v.substr(8).to_lower(),
				"display_name": v.substr(8).replace("_", " ").capitalize(),
				"group": MuseumDisplay.fossil_set_name(i),
				"sell_price": 2000,
			})
	for row: Dictionary in _rows:
		ItemCatalog.remember(_make_item(row))


static func all_rows() -> Array[Dictionary]:
	ensure_loaded()
	return _rows.duplicate(true)


static func count() -> int:
	ensure_loaded()
	return _rows.size()


static func row_for_index(index: int) -> Dictionary:
	ensure_loaded()
	for row: Dictionary in _rows:
		if int(row.get("index", -1)) == index:
			return row
	return {}


static func item_id_for_index(index: int) -> StringName:
	return StringName(str(row_for_index(index).get("id", "")))


static func get_item(fossil_id: StringName) -> FurnitureData:
	ensure_loaded()
	var data: ItemData = ItemCatalog.get_item(fossil_id)
	return data as FurnitureData


static func _make_item(row: Dictionary) -> FurnitureData:
	var data := FurnitureData.new()
	data.id = StringName(str(row.get("id", "")))
	data.visual_id = StringName(str(row.get("visual_id", "")))
	data.display_name = str(row.get("display_name", "Fossil"))
	data.description = "An identified fossil. Donate it to the museum or sell it."
	data.sell_price = int(row.get("sell_price", 2000))
	data.kind = FurnitureData.Kind.DISPLAY
	data.footprint = Vector2i(1, 1)
	data.icon_color = Color(0.72, 0.62, 0.42)
	return data
