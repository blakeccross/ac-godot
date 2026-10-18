class_name InputBindings
extends RefCounted

## Player-chosen InputMap overrides, kept in `user://config.cfg` under `[input]`. Captures the
## project defaults on first load, then re-applies any saved events. Not an autoload.

const DEFAULT_PATH := "user://config.cfg"
const SECTION := "input"

## Actions the settings page can rebind. Stick axes on move / sprint stay unless replaced by a
## pad button on that same action.
const ACTIONS: Array[Dictionary] = [
	{"id": &"interact", "label": "Interact"},
	{"id": &"pick_up", "label": "Pick up"},
	{"id": &"sprint", "label": "Run"},
	{"id": &"inventory", "label": "Pockets"},
	{"id": &"map", "label": "Map"},
	{"id": &"pause_menu", "label": "Pause"},
	{"id": &"inventory_quick_grab", "label": "Quick grab"},
	{"id": &"inventory_mark", "label": "Mark item"},
	{"id": &"move_left", "label": "Move left"},
	{"id": &"move_right", "label": "Move right"},
	{"id": &"move_forward", "label": "Move forward"},
	{"id": &"move_back", "label": "Move back"},
]

static var path: String = DEFAULT_PATH
static var _defaults: Dictionary = {} ## StringName → Array[Dictionary]
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_capture_defaults()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for entry: Dictionary in ACTIONS:
		var id: StringName = entry["id"]
		if not cfg.has_section_key(SECTION, String(id)):
			continue
		var raw: Variant = cfg.get_value(SECTION, String(id), null)
		if typeof(raw) != TYPE_STRING:
			continue
		var parsed: Variant = JSON.parse_string(raw as String)
		if typeof(parsed) != TYPE_ARRAY:
			continue
		_apply_encoded(id, parsed as Array)


## Tests / a fresh install: forget overrides and restore the project map.
static func reset(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	if _defaults.is_empty():
		_capture_defaults()
	_loaded = true
	restore_defaults()


static func restore_defaults() -> void:
	if _defaults.is_empty():
		_capture_defaults()
	for action: Variant in _defaults.keys():
		_apply_encoded(StringName(str(action)), _defaults[action] as Array)
	_erase_saved()


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	for entry: Dictionary in ACTIONS:
		var id: StringName = entry["id"]
		cfg.set_value(SECTION, String(id), JSON.stringify(_encode_action(id)))
	cfg.save(path)


## Human-readable list of the action's current events ("E, Space, A").
static func describe(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for event: InputEvent in InputMap.action_get_events(action):
		var label: String = _event_label(event)
		if label != "" and not parts.has(label):
			parts.append(label)
	return ", ".join(parts) if not parts.is_empty() else "—"


## Bind `event` on `action`, replacing other events of the same device family. Clears the same
## event off any other remappable action so two verbs do not share a key.
static func rebind(action: StringName, event: InputEvent) -> bool:
	if not _is_remappable(action) or not _is_bindable(event):
		return false
	ensure_loaded()
	for entry: Dictionary in ACTIONS:
		var other: StringName = entry["id"]
		if other == action or not InputMap.has_action(other):
			continue
		for existing: InputEvent in InputMap.action_get_events(other):
			if existing.is_match(event, true):
				InputMap.action_erase_event(other, existing)
	_replace_family(action, event)
	save()
	return true


static func _capture_defaults() -> void:
	_defaults.clear()
	for entry: Dictionary in ACTIONS:
		var id: StringName = entry["id"]
		if InputMap.has_action(id):
			_defaults[id] = _encode_action(id)


static func _erase_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	if cfg.has_section(SECTION):
		cfg.erase_section(SECTION)
	cfg.save(path)


static func _is_remappable(action: StringName) -> bool:
	for entry: Dictionary in ACTIONS:
		if entry["id"] == action:
			return true
	return false


static func _is_bindable(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventJoypadButton


static func _replace_family(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	var keep: Array[InputEvent] = []
	for existing: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and existing is InputEventKey:
			continue
		if event is InputEventJoypadButton and existing is InputEventJoypadButton:
			continue
		keep.append(existing)
	InputMap.action_erase_events(action)
	for kept: InputEvent in keep:
		InputMap.action_add_event(action, kept)
	InputMap.action_add_event(action, event.duplicate())


static func _apply_encoded(action: StringName, encoded: Array) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	for item: Variant in encoded:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var event: InputEvent = _decode_event(item as Dictionary)
		if event != null:
			InputMap.action_add_event(action, event)


static func _encode_action(action: StringName) -> Array:
	var out: Array = []
	for event: InputEvent in InputMap.action_get_events(action):
		var encoded: Dictionary = _encode_event(event)
		if not encoded.is_empty():
			out.append(encoded)
	return out


static func _encode_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {"t": "key", "k": key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode}
	if event is InputEventJoypadButton:
		return {"t": "joyb", "b": (event as InputEventJoypadButton).button_index}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {"t": "joym", "a": motion.axis, "v": motion.axis_value}
	return {}


static func _decode_event(data: Dictionary) -> InputEvent:
	match str(data.get("t", "")):
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(data.get("k", 0)) as Key
			return key
		"joyb":
			var button := InputEventJoypadButton.new()
			button.button_index = int(data.get("b", 0)) as JoyButton
			return button
		"joym":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(data.get("a", 0)) as JoyAxis
			motion.axis_value = float(data.get("v", 0.0))
			return motion
	return null


static func _event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return OS.get_keycode_string(code)
	if event is InputEventJoypadButton:
		return _joy_button_label((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var side: String = "+" if motion.axis_value > 0.0 else "−"
		return "Axis %d%s" % [motion.axis, side]
	return ""


static func _joy_button_label(button: int) -> String:
	match button:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		JOY_BUTTON_LEFT_STICK:
			return "L3"
		JOY_BUTTON_RIGHT_STICK:
			return "R3"
		JOY_BUTTON_BACK:
			return "Back"
		JOY_BUTTON_START:
			return "Start"
		JOY_BUTTON_DPAD_UP:
			return "D-Up"
		JOY_BUTTON_DPAD_DOWN:
			return "D-Down"
		JOY_BUTTON_DPAD_LEFT:
			return "D-Left"
		JOY_BUTTON_DPAD_RIGHT:
			return "D-Right"
		_:
			return "Button %d" % button
