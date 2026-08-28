class_name ItemCatalog
extends RefCounted

## Loads `res://data/items/*.tres` once and resolves `ItemData` by id.

const ITEMS_DIR := "res://data/items"

static var _by_id: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_by_id.clear()
	var dir := DirAccess.open(ITEMS_DIR)
	if dir == null:
		_loaded = true
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".tres"):
			var path := "%s/%s" % [ITEMS_DIR, name]
			var res: Resource = load(path)
			if res is ItemData:
				var data := res as ItemData
				if data.id != &"":
					_by_id[data.id] = data
		name = dir.get_next()
	dir.list_dir_end()
	_loaded = true


static func get_item(item_id: StringName) -> ItemData:
	ensure_loaded()
	if item_id == &"":
		return null
	return _by_id.get(item_id) as ItemData


static func all_items() -> Array[ItemData]:
	ensure_loaded()
	var out: Array[ItemData] = []
	for value: Variant in _by_id.values():
		if value is ItemData:
			out.append(value as ItemData)
	return out


static func reload() -> void:
	_loaded = false
	ensure_loaded()
