class_name BgmCatalog
extends RefCounted

## Maps BGM ids (`title`, `field_14`, `rain`, `shop0`, …) to generated streams.
## Missing `assets/generated/audio/` is silence, same as missing GLBs.

const GENERATED_DIR := "res://assets/generated/audio"
const CATALOG_PATH := GENERATED_DIR + "/catalog.json"

static var _loaded: bool = false
static var _entries: Dictionary = {}
static var _streams: Dictionary = {}


static func reset() -> void:
	_entries.clear()
	_streams.clear()
	_loaded = false


static func field_id(hour: int) -> StringName:
	var wrapped: int = hour % 24
	if wrapped < 0:
		wrapped += 24
	return StringName("field_%02d" % wrapped)


static func outdoor_id(hour: int, weather: StringName) -> StringName:
	if weather == &"rain":
		return &"rain"
	return field_id(hour)


static func room_id(kind: Room.Kind) -> StringName:
	match kind:
		Room.Kind.SHOP, Room.Kind.NEEDLEWORK:
			return &"shop0"
		_:
			return &""


static func ensure_loaded() -> void:
	if _loaded:
		return
	_entries.clear()
	_load_catalog()
	_loaded = true


static func register_stream(id: StringName, stream: AudioStream) -> void:
	if id == &"" or stream == null:
		return
	_streams[id] = stream


static func has_id(id: StringName) -> bool:
	if id == &"":
		return false
	ensure_loaded()
	if _streams.has(id):
		return true
	if _entries.has(id):
		return true
	return FileAccess.file_exists(_stream_path(id))


static func stream_for(id: StringName) -> AudioStream:
	if id == &"":
		return null
	ensure_loaded()
	if _streams.has(id):
		return _streams[id] as AudioStream
	var path := _path_for(id)
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var loaded: Resource = load(path)
	if loaded is AudioStream:
		var stream := loaded as AudioStream
		_apply_loop(id, stream)
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
		var rows: Variant = (parsed as Dictionary).get("bgm", [])
		if rows is Array:
			for row: Variant in rows as Array:
				if row is Dictionary:
					var rec := row as Dictionary
					var key := StringName(str(rec.get("id", "")))
					if key != &"":
						_entries[key] = rec


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
	return "%s/bgm/%s.ogg" % [GENERATED_DIR, String(id)]


static func _apply_loop(id: StringName, stream: AudioStream) -> void:
	var rec: Variant = _entries.get(id)
	var loop := true
	var loop_start := 0.0
	if rec is Dictionary:
		loop = bool((rec as Dictionary).get("loop", true))
		loop_start = float((rec as Dictionary).get("loop_start_sec", 0.0))
	if stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = loop
		ogg.loop_offset = loop_start
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
