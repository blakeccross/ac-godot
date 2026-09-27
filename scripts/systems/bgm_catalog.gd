class_name BgmCatalog
extends RefCounted

## Maps BGM ids (`title`, `field_14`, `rain`, `shop0`, …) to generated streams.
## Missing `assets/generated/audio/` is silence, same as missing GLBs.

const GENERATED_DIR := "res://assets/generated/audio"
const CATALOG_PATH := GENERATED_DIR + "/catalog.json"
## Nook's per-building tracks, by shop level (BGM 44 / 37 / 38 / 39, late 79–82).
const SHOP_IDS: Array[StringName] = [&"shop0", &"shop1", &"shop2", &"shop3"]
const SHOP_LATE_IDS: Array[StringName] = [&"shop0_late", &"shop1_late", &"shop2_late", &"shop3_late"]
## `mBGMRoom_shop_close_time_set`: the late track starts five minutes before closing.
const SHOP_LATE_LEAD_SEC := 5 * 60

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
	## `mBGMRoom_make_scene_bgm` (`m_kankyo.c` `mEnv_SetBaseLight` scene_no switch): each
	## public building has its own fixed BGM id. Homes (`PLAYER`/`NPC`) have no `BGM_*`
	## entry in the original and stay silent indoors. Nook's track depends on the building
	## and the time: see `room_bgm`.
	match kind:
		Room.Kind.SHOP:
			return &"shop0"
		Room.Kind.NEEDLEWORK:
			return &"tailors"
		Room.Kind.MUSEUM:
			return &"museum"
		Room.Kind.POST_OFFICE:
			return &"post_office0"
		Room.Kind.POLICE:
			return &"police_box"
		Room.Kind.BROKER:
			return &"brokers_shop"
		Room.Kind.KAMAKURA:
			return &"kamakura"
		_:
			return &""


## Room BGM at `now_sec` (seconds since midnight). `job_active` is the part-time job
## (`mEv_CheckRealArbeit`), which keeps the normal shop track past closing.
static func room_bgm(room: Room, now_sec: int, job_active: bool = false) -> StringName:
	if room == null:
		return &""
	var level: int = shop_level(room)
	if level < 0:
		return room_id(room.kind)
	return shop_id(level, not job_active and shop_late(level, now_sec))


## Nook level of a shop room, -1 otherwise. Nookington's upstairs (`shop3_2`) plays the
## same track as downstairs (`mFI_FIELD_ROOM_SHOP3_2` falls to BGM 39 / 82).
static func shop_level(room: Room) -> int:
	if room == null or room.kind != Room.Kind.SHOP:
		return -1
	var base: StringName = room.parent_room_id if room.parent_room_id != &"" else room.id
	return ShopBook.NOOK_ROOM_IDS.find(base)


## `mBGMRoom_make_scene_bgm_shop_get`.
static func shop_id(level: int, late: bool) -> StringName:
	var i: int = clampi(level, 0, SHOP_IDS.size() - 1)
	return SHOP_LATE_IDS[i] if late else SHOP_IDS[i]


## `mBGMClock_after_time_check` against `mSP_GetShopCloseTime_Bgm` minus five minutes
## (hh:mm:ss only, so it clears again at midnight).
static func shop_late(level: int, now_sec: int) -> bool:
	var close_hour: int = ShopBook.CLOSE_HOURS[clampi(level, 0, ShopBook.CLOSE_HOURS.size() - 1)]
	return now_sec >= close_hour * 3600 - SHOP_LATE_LEAD_SEC


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


## Catalog id for a decomp `BGM_*` number (`md2` is bgm 128 — the ids are the pipeline's names).
static func id_for_num(bgm_num: int) -> StringName:
	ensure_loaded()
	for key: Variant in _entries.keys():
		var rec: Variant = _entries[key]
		if rec is Dictionary and int((rec as Dictionary).get("bgm_num", -1)) == bgm_num:
			return key as StringName
	return &""


## Guitar stem for `Na_TTKK_ARM` (`intro_kk_arm.ogg`), or null if missing.
static func arm_stream_for(id: StringName) -> AudioStream:
	if id == &"":
		return null
	ensure_loaded()
	var arm_id := StringName("%s_arm" % String(id))
	if _streams.has(arm_id):
		return _streams[arm_id] as AudioStream
	var path := _arm_path_for(id)
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var loaded: Resource = load(path)
	if loaded is AudioStream:
		var stream := loaded as AudioStream
		_apply_loop(id, stream)
		_streams[arm_id] = stream
		return stream
	return null


static func register_arm_stream(id: StringName, stream: AudioStream) -> void:
	if id == &"" or stream == null:
		return
	_streams[StringName("%s_arm" % String(id))] = stream


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


static func _arm_path_for(id: StringName) -> String:
	var rec: Variant = _entries.get(id)
	if rec is Dictionary:
		var rel := str((rec as Dictionary).get("arm_path", ""))
		if not rel.is_empty():
			if rel.begins_with("res://"):
				return rel
			return "%s/%s" % [GENERATED_DIR, rel]
	return "%s/bgm/%s_arm.ogg" % [GENERATED_DIR, String(id)]


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
