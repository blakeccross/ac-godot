class_name EventSchedule
extends RefCounted

## Static schedule rows (`m_event_schedule.c_inc` → `data/events/schedule.json`). Field
## encodings are documented in `docs/decomp_notes/events.md`; `EventCalendar` resolves them.

const PATH := "res://data/events/schedule.json"

## Event ids that only make sense once another system exists. Their rows stay in the data
## but `EventCalendar` will not schedule them (they can still be forced with `/event start`).
const UNSUPPORTED: Array[StringName] = [
	&"bridge_make", &"soncho_bridge_make", &"mask_npc", &"ghost",
	&"soncho_vacation_january", &"soncho_vacation_february",
]

## Spoken labels; anything else is title-cased from the id.
const LABELS: Dictionary = {
	&"shop_sale": "Shop sale", &"designer": "Designer visit", &"broker_sale": "Crazy Redd",
	&"artist": "Artist visit", &"carpet_peddler": "Carpet peddler", &"gypsy": "Fortune teller",
	&"kabu_peddler": "Joan's turnips", &"kk_slider": "K.K. Slider", &"dozaemon": "Gulliver",
	&"toy_day_jingle": "Jingle", &"toy_day_soncho": "Toy Day", &"fireworks_show": "Fireworks show",
	&"aprilfools_day": "April Fools' Day", &"mothers_day": "Mother's Day",
	&"fathers_day": "Father's Day", &"valentines_day": "Valentine's Day",
	&"new_years_eve_countdown": "New Year's countdown", &"new_years_day": "New Year's Day",
	&"officers_day": "Officers' Day", &"explorers_day": "Explorers' Day",
	&"mayors_day": "Mayor's Day", &"player_birthday": "Your birthday",
}

## Prefixes for events that never get an on-screen announcement.
const QUIET_PREFIXES: Array[String] = ["rumor_", "talk_", "weather_", "soncho_", "handbill_"]

static var _rows: Array[Dictionary] = []
static var _loaded: bool = false


static func rows() -> Array[Dictionary]:
	_ensure()
	return _rows


static func ids() -> Array[StringName]:
	_ensure()
	var seen: Dictionary = {}
	var out: Array[StringName] = []
	for row: Dictionary in _rows:
		var id: StringName = StringName(String(row.get("id", "")))
		if not seen.has(id):
			seen[id] = true
			out.append(id)
	return out


static func has_id(id: StringName) -> bool:
	return id in ids()


static func label(id: StringName) -> String:
	if LABELS.has(id):
		return String(LABELS[id])
	return String(id).replace("_", " ").capitalize()


static func announces(id: StringName) -> bool:
	if id in UNSUPPORTED:
		return false
	var text: String = String(id)
	for prefix: String in QUIET_PREFIXES:
		if text.begins_with(prefix):
			return false
	return true


static func is_rumor(id: StringName) -> bool:
	var text: String = String(id)
	return text.begins_with("rumor_") or text.begins_with("talk_")


static func reset() -> void:
	_loaded = false
	_rows.clear()


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_rows.clear()
	var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("EventSchedule: missing %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for raw: Variant in (parsed as Dictionary).get("rows", []) as Array:
		if typeof(raw) == TYPE_DICTIONARY:
			_rows.append(raw as Dictionary)
