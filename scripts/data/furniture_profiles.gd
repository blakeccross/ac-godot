class_name FurnitureProfiles
extends RefCounted

## Disc `aFTR_PROFILE` flags per furniture visual (`tools/asset_pipeline/furniture_profiles.py`).
## Gitignored like the rest of `assets/generated/`; without it `FurnitureData.infer_from_visual`
## falls back to name guesses.

const PATH := "res://assets/generated/environment/fg/furniture_profiles.json"

static var _loaded: bool = false
static var _profiles: Dictionary = {}


static func reset() -> void:
	_loaded = false
	_profiles.clear()


static func profile_for(visual_id: StringName) -> Dictionary:
	_ensure_loaded()
	return _profiles.get(String(visual_id), {}) as Dictionary


static func available() -> bool:
	_ensure_loaded()
	return not _profiles.is_empty()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var rows: Variant = (parsed as Dictionary).get("profiles", {})
	if typeof(rows) == TYPE_DICTIONARY:
		_profiles = rows as Dictionary
