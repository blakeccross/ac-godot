class_name SeCatalog
extends RefCounted

## Maps SE ids (`cursol`, `bebe`, `hanabi0`, …) to generated one-shot streams.
## Missing `assets/generated/audio/` is silence, same as missing GLBs.

const GENERATED_DIR := "res://assets/generated/audio"
const CATALOG_PATH := GENERATED_DIR + "/catalog.json"

static var _loaded: bool = false
static var _entries: Dictionary = {}
static var _streams: Dictionary = {}
## Catalog id by sound number (`se_num`), for hex ids the game names by number.
static var _by_num: Dictionary = {}
## `SE_SINGLETON` (0x8000) and `SE_MONO` (0x1000) are flags on the number, not other sounds:
## `8026` is SINGLETON(0x26), `1050` MONO(`register`).
const FLAG_BITS: Array[int] = [0x8000, 0x1000, 0x9000]


static func reset() -> void:
	_entries.clear()
	_streams.clear()
	_by_num.clear()
	_loaded = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_entries.clear()
	_by_num.clear()
	_load_catalog()
	_loaded = true


## The catalog id a hex sound id stands for: itself, the row with that number (`54` is
## `kokoro_toguru`), or the same number without its play flags. `id` when nothing matches.
static func resolve(id: StringName) -> StringName:
	ensure_loaded()
	if _entries.has(id) or _streams.has(id):
		return id
	var raw := String(id)
	if not raw.is_valid_hex_number():
		return id
	var num: int = raw.hex_to_int()
	if _by_num.has(num):
		return _by_num[num]
	for bits: int in FLAG_BITS:
		if num & bits and _by_num.has(num & ~bits):
			return _by_num[num & ~bits]
	return id


static func register_stream(id: StringName, stream: AudioStream) -> void:
	if id == &"" or stream == null:
		return
	_streams[id] = stream


static func has_id(id: StringName) -> bool:
	if id == &"":
		return false
	ensure_loaded()
	id = resolve(id)
	if _streams.has(id):
		return true
	if _entries.has(id):
		return true
	return FileAccess.file_exists(_stream_path(id))


static func stream_for(id: StringName) -> AudioStream:
	if id == &"":
		return null
	ensure_loaded()
	id = resolve(id)
	if _streams.has(id):
		return _streams[id] as AudioStream
	var path := _path_for(id)
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var loaded: Resource = load(path)
	if loaded is AudioStream:
		var stream := loaded as AudioStream
		_apply_oneshot(stream)
		_streams[id] = stream
		return stream
	return null


static func _load_catalog() -> void:
	if not FileAccess.file_exists(CATALOG_PATH):
		return
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var rows: Variant = (parsed as Dictionary).get("sfx", [])
		if rows is Array:
			for row: Variant in rows as Array:
				if row is Dictionary:
					var rec := row as Dictionary
					var key := StringName(str(rec.get("id", "")))
					if key != &"":
						_entries[key] = rec
						if rec.has("se_num") and not _by_num.has(int(rec["se_num"])):
							_by_num[int(rec["se_num"])] = key


static func _path_for(id: StringName) -> String:
	var rec: Variant = _entries.get(id)
	if rec is Dictionary:
		var rel := str((rec as Dictionary).get("path", ""))
		if not rel.is_empty():
			if rel.begins_with("res://"):
				return rel
			return "%s/%s" % [GENERATED_DIR, rel]
	return _stream_path(id)


static func _stream_path(id: StringName) -> String:
	return "%s/sfx/%s.ogg" % [GENERATED_DIR, String(id)]


static func _apply_oneshot(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = false
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
