class_name VoiceCatalog
extends RefCounted

## Maps animalese phoneme clips (`spec` 1–3 × phoneme `0x00`–`0x77`) to generated streams.

const GENERATED_DIR := "res://assets/generated/audio"
const CATALOG_PATH := GENERATED_DIR + "/catalog.json"

static var _loaded: bool = false
static var _entries: Dictionary = {}
static var _streams: Dictionary = {}


static func reset() -> void:
	_entries.clear()
	_streams.clear()
	_loaded = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_entries.clear()
	_load_catalog()
	_loaded = true


static func register_stream(spec: int, phoneme: int, stream: AudioStream) -> void:
	if stream == null:
		return
	_streams[_key(spec, phoneme)] = stream


static func stream_for(spec: int, phoneme: int) -> AudioStream:
	ensure_loaded()
	var key := _key(spec, phoneme)
	if _streams.has(key):
		return _streams[key] as AudioStream
	var path := _path_for(spec, phoneme)
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var loaded: Resource = load(path)
	if loaded is AudioStream:
		var stream := loaded as AudioStream
		_apply_oneshot(stream)
		_streams[key] = stream
		return stream
	return null


static func _key(spec: int, phoneme: int) -> StringName:
	return StringName("spec_%d/ph_%02x" % [spec, phoneme & 0xFF])


static func _load_catalog() -> void:
	if not FileAccess.file_exists(CATALOG_PATH):
		return
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var rows: Variant = (parsed as Dictionary).get("voice", [])
		if rows is Array:
			for row: Variant in rows as Array:
				if row is Dictionary:
					var rec := row as Dictionary
					var key := StringName(str(rec.get("id", "")))
					if key != &"":
						_entries[key] = rec


static func _path_for(spec: int, phoneme: int) -> String:
	var key := _key(spec, phoneme)
	var rec: Variant = _entries.get(key)
	if rec is Dictionary:
		var rel := str((rec as Dictionary).get("path", ""))
		if not rel.is_empty():
			if rel.begins_with("res://"):
				return rel
			return "%s/%s" % [GENERATED_DIR, rel]
	return "%s/voice/spec_%d/ph_%02x.ogg" % [GENERATED_DIR, spec, phoneme & 0xFF]


static func _apply_oneshot(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = false
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
