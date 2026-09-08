class_name SpeciesLog
extends RefCounted

## "Caught at least once" set for the fish / insect encyclopedia pages
## (`mIV_set_collect_itemNo` reads `furniture_collected_bitfield`). Owned by `Game`.
## Distinct from `MuseumBook` (donated) — a species registers here the moment it
## first enters the pockets, whether or not it is ever given to Blathers.

signal registered(id: StringName, kind: StringName)

var _caught: Dictionary = {}  # StringName -> true


func clear() -> void:
	_caught.clear()


## Record a fresh catch. Returns true only the first time a species is seen.
func record(id: StringName) -> bool:
	if id == &"" or _caught.has(id):
		return false
	var kind: StringName = EncyclopediaCatalog.kind_of(id)
	if kind == &"":
		return false
	_caught[id] = true
	registered.emit(id, kind)
	return true


func has(id: StringName) -> bool:
	return _caught.has(id)


## Number registered on one encyclopedia page (`kind` = &"fish" / &"insect").
func page_count(kind: StringName) -> int:
	var n: int = 0
	for row: Dictionary in EncyclopediaCatalog.page(kind):
		if _caught.has(row["id"]):
			n += 1
	return n


func page_total(kind: StringName) -> int:
	return EncyclopediaCatalog.page(kind).size()


func to_save() -> Dictionary:
	var ids: Array[String] = []
	for id: StringName in _caught:
		ids.append(String(id))
	ids.sort()
	return {"caught": ids}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var raw: Variant = (data as Dictionary).get("caught", [])
	if typeof(raw) != TYPE_ARRAY:
		return
	for entry: Variant in raw as Array:
		_caught[StringName(str(entry))] = true
