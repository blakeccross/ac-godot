class_name ItemCatalog
extends RefCounted

## Loads `res://data/items/*.tres` and `res://data/furniture/*.tres`.

const ITEMS_DIR := "res://data/items"
const FURNITURE_DIR := "res://data/furniture"

static var _by_id: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_by_id.clear()
	_load_dir(ITEMS_DIR)
	_load_dir(FURNITURE_DIR)
	_loaded = true


static func _load_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".tres"):
			var path := "%s/%s" % [dir_path, name]
			var res: Resource = load(path)
			if res is ItemData:
				var data := res as ItemData
				if data.id != &"":
					_by_id[data.id] = data
		name = dir.get_next()
	dir.list_dir_end()


static func get_item(item_id: StringName) -> ItemData:
	ensure_loaded()
	if item_id == &"":
		return null
	return _by_id.get(item_id) as ItemData


static func furniture_for_visual(visual_id: StringName) -> FurnitureData:
	## Runtime stub for disc FTR that has a GLB but no authored `.tres` yet.
	ensure_loaded()
	if visual_id == &"":
		return null
	var existing: ItemData = _by_id.get(visual_id) as ItemData
	if existing is FurnitureData:
		return existing as FurnitureData
	for value: Variant in _by_id.values():
		if value is FurnitureData and (value as FurnitureData).visual_id == visual_id:
			return value as FurnitureData
	var data := FurnitureData.new()
	data.id = visual_id
	data.display_name = _display_from_visual(visual_id)
	data.visual_id = visual_id
	data.footprint = Vector2i(1, 1)
	data.indoor = true
	data.blocks_walk = true
	var raw := String(visual_id).to_lower()
	data.can_sit = raw.contains("chair") or raw.contains("sofa") or raw.contains("isu")
	_by_id[visual_id] = data
	return data


static func _display_from_visual(visual_id: StringName) -> String:
	var raw := String(visual_id)
	if raw.begins_with("int_"):
		raw = raw.substr(4)
	return raw.replace("_", " ").capitalize()


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
