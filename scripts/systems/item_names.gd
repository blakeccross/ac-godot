class_name ItemNames
extends RefCounted

## Disc item names (`mIN_copy_name_str`), from the pipeline's `item_names.json`: one list per
## `itemName_*` table plus `ftrName_table` / `ftrName2_table`. Missing file → empty strings,
## and callers keep their placeholder.

const PATH := "res://assets/generated/dialogue/item_names.json"

static var _tables: Dictionary = {}
static var _loaded: bool = false


static func table(name: String) -> Array:
	_ensure()
	return _tables.get(name, [])


## Name `index` of table `name` (`itemName_minidisk`, `ftrName_table`, …), or "".
static func name_of(table_name: String, index: int) -> String:
	var rows: Array = table(table_name)
	if index < 0 or index >= rows.size():
		return ""
	return str(rows[index])


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
		_tables = parsed
