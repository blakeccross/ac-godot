class_name DialogueData
extends Resource

## One conversation graph. Author as JSON (`json_path` or `data/dialogue/*.json`).
## Legacy greeting fields still build a small time-of-day tree.

const KIND_LINE := &"line"
const KIND_CHOICE := &"choice"
const KIND_BRANCH := &"branch"
const KIND_RANDOM := &"random"
const KIND_EVENT := &"event"

@export var id: StringName = &""
@export var speaker_id: StringName = &""
@export var start: StringName = &"start"
## Easy-to-edit source. Empty → use `nodes` / legacy greeting fields.
@export_file("*.json") var json_path: String = ""
@export var lines: PackedStringArray = PackedStringArray()
@export var already_talked: String = ""
@export var night: String = ""
@export var dawn: String = ""
@export var day: String = ""
@export var dusk: String = ""

var nodes: Dictionary = {}


static func from_dict(data: Dictionary) -> DialogueData:
	var out := DialogueData.new()
	out.id = StringName(str(data.get("id", "")))
	out.speaker_id = StringName(str(data.get("speaker_id", "")))
	out.start = StringName(str(data.get("start", "start")))
	var raw: Variant = data.get("nodes", {})
	if typeof(raw) == TYPE_DICTIONARY:
		out.nodes = (raw as Dictionary).duplicate(true)
	return out


static func from_json_text(text: String) -> DialogueData:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return DialogueData.new()
	return from_dict(parsed as Dictionary)


static func from_json_file(path: String) -> DialogueData:
	if path == "" or not FileAccess.file_exists(path):
		return DialogueData.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return DialogueData.new()
	return from_json_text(file.get_as_text())


func ensure_loaded() -> void:
	if not nodes.is_empty():
		return
	if json_path != "":
		var loaded: DialogueData = from_json_file(json_path)
		if loaded != null and not loaded.nodes.is_empty():
			if id == &"":
				id = loaded.id
			if speaker_id == &"":
				speaker_id = loaded.speaker_id
			start = loaded.start
			nodes = loaded.nodes
			return
	nodes = _legacy_tree()
	start = &"start"


func node(node_id: StringName) -> Dictionary:
	ensure_loaded()
	var rec: Variant = nodes.get(node_id, {})
	if typeof(rec) == TYPE_DICTIONARY:
		return rec as Dictionary
	return {}


func has_node(node_id: StringName) -> bool:
	ensure_loaded()
	return nodes.has(node_id)


func line_for_time(tod: ClockService.TimeOfDay) -> String:
	match tod:
		ClockService.TimeOfDay.NIGHT:
			return night
		ClockService.TimeOfDay.DAWN:
			return dawn
		ClockService.TimeOfDay.DAY:
			return day
		ClockService.TimeOfDay.DUSK:
			return dusk
		_:
			return ""


func _legacy_tree() -> Dictionary:
	var tree: Dictionary = {}
	tree["repeat"] = _line_node(already_talked if already_talked != "" else "Hello!")
	tree["night"] = _line_node(_first_nonempty([night, lines]))
	tree["dawn"] = _line_node(_first_nonempty([dawn, lines]))
	tree["day"] = _line_node(_first_nonempty([day, lines]))
	tree["dusk"] = _line_node(_first_nonempty([dusk, lines]))
	tree["start"] = {
		"type": "branch",
		"when": [
			{"if": {"already_talked": true}, "goto": "repeat"},
			{"if": {"time_of_day": "night"}, "goto": "night"},
			{"if": {"time_of_day": "dawn"}, "goto": "dawn"},
			{"if": {"time_of_day": "dusk"}, "goto": "dusk"},
			{"goto": "day"},
		],
	}
	return tree


func _line_node(text: String) -> Dictionary:
	return {"type": "line", "text": text}


func _first_nonempty(options: Array) -> String:
	for opt: Variant in options:
		if typeof(opt) == TYPE_STRING and str(opt) != "":
			return str(opt)
		if opt is PackedStringArray and (opt as PackedStringArray).size() > 0:
			return (opt as PackedStringArray)[0]
	return "Hello!"
