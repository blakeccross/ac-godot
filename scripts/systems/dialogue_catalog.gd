class_name DialogueCatalog
extends RefCounted

## Loads authored JSON under `res://data/dialogue/` and imported banks under
## `res://assets/generated/dialogue/` when the pipeline has been run.

const AUTHORED_DIR := "res://data/dialogue"
const GENERATED_DIR := "res://assets/generated/dialogue"
const GENERATED_CHUNK := 256

static var _by_id: Dictionary = {}
static var _loaded: bool = false


static func reset() -> void:
	_by_id.clear()
	_loaded = false


static func conversation(conv_id: StringName) -> DialogueData:
	ensure_loaded()
	if conv_id == &"":
		return null
	var found: Variant = _by_id.get(conv_id)
	if found is DialogueData:
		return found as DialogueData
	_load_generated_id(conv_id)
	found = _by_id.get(conv_id)
	if found is DialogueData:
		return found as DialogueData
	return null


static func ensure_loaded() -> void:
	if _loaded:
		return
	_by_id.clear()
	_load_dir(AUTHORED_DIR)
	_loaded = true


static func register(data: DialogueData) -> void:
	if data == null:
		return
	data.ensure_loaded()
	if data.id == &"":
		return
	_by_id[data.id] = data


static func _load_generated_id(conv_id: StringName) -> void:
	var key := String(conv_id)
	if not key.begins_with("msg_"):
		return
	var msg_no: int = int(key.substr(4))
	if msg_no < 0:
		return
	var chunk: int = (msg_no / GENERATED_CHUNK) * GENERATED_CHUNK
	_load_file("%s/%04d.json" % [GENERATED_DIR, chunk])


static func _load_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			if name == "index.json" or name == "select.json" or name == "strings.json":
				name = dir.get_next()
				continue
			_load_file("%s/%s" % [dir_path, name])
		name = dir.get_next()


static func _load_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_ingest(parsed as Dictionary)
		return
	if typeof(parsed) == TYPE_ARRAY:
		for entry: Variant in parsed as Array:
			if typeof(entry) == TYPE_DICTIONARY:
				_ingest(entry as Dictionary)


static func _ingest(data: Dictionary) -> void:
	if data.has("conversations") and typeof(data["conversations"]) == TYPE_ARRAY:
		for entry: Variant in data["conversations"] as Array:
			if typeof(entry) == TYPE_DICTIONARY:
				register(DialogueData.from_dict(entry as Dictionary))
		return
	if data.has("nodes"):
		register(DialogueData.from_dict(data))
