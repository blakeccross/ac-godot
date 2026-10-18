class_name TestInputBindings
extends GdUnitTestSuite

## Saved InputMap overrides for the settings page.

const PATH := "user://test_input_bindings.cfg"


func before_test() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	InputBindings.reset(PATH)


func after_test() -> void:
	InputBindings.restore_defaults()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	InputBindings.path = InputBindings.DEFAULT_PATH
	InputBindings._loaded = false


func test_rebind_replaces_keys_and_keeps_pad() -> void:
	var before_pad: int = _joy_button_count(&"interact")
	assert_int(before_pad).is_greater(0)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	assert_bool(InputBindings.rebind(&"interact", key)).is_true()
	assert_str(InputBindings.describe(&"interact")).contains("G")
	assert_int(_key_count(&"interact")).is_equal(1)
	assert_int(_joy_button_count(&"interact")).is_equal(before_pad)


func test_rebind_steals_key_from_another_action() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_I
	assert_bool(InputBindings.rebind(&"pick_up", key)).is_true()
	assert_bool(_action_has_key(&"pick_up", KEY_I)).is_true()
	assert_bool(_action_has_key(&"inventory", KEY_I)).is_false()


func test_saved_bindings_reload() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_H
	InputBindings.rebind(&"map", key)
	InputBindings._loaded = false
	InputMap.action_erase_events(&"map")
	var other := InputEventKey.new()
	other.physical_keycode = KEY_M
	InputMap.action_add_event(&"map", other)
	InputBindings.ensure_loaded()
	assert_bool(_action_has_key(&"map", KEY_H)).is_true()
	assert_bool(_action_has_key(&"map", KEY_M)).is_false()


func test_restore_defaults_clears_overrides() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	InputBindings.rebind(&"sprint", key)
	InputBindings.restore_defaults()
	assert_bool(_action_has_key(&"sprint", KEY_J)).is_false()
	assert_bool(_action_has_key(&"sprint", KEY_SHIFT)).is_true()


func test_settings_overlay_opens_from_hud() -> void:
	var hud: Node = auto_free(load("res://scenes/ui/clock_hud.tscn").instantiate())
	add_child(hud)
	var settings: SettingsOverlay = hud.get_node("SettingsOverlay") as SettingsOverlay
	assert_that(settings).is_not_null()
	assert_bool(settings.is_in_group("settings_ui")).is_true()
	settings.open()
	assert_bool(settings.is_open()).is_true()
	settings.close()
	assert_bool(settings.is_open()).is_false()


func _key_count(action: StringName) -> int:
	var n: int = 0
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			n += 1
	return n


func _joy_button_count(action: StringName) -> int:
	var n: int = 0
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			n += 1
	return n


func _action_has_key(action: StringName, code: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var physical: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			if physical == code:
				return true
	return false
