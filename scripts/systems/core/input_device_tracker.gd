extends Node

## Which device the player last used: a finger, or keys / a pad. The touch HUD
## shows only while it is `TOUCH`, and the touch driver gives the player back to
## the stick when a key or button comes in.

enum Device { KEYS, TOUCH }

const _WINDOW_DISMISS := preload("res://scripts/systems/ui/window_dismiss.gd")

signal device_changed(device: Device)
## The window crossed between portrait and landscape.
signal layout_changed

var device: Device = Device.KEYS
## Android or iOS. The bottom tab bar shows only there. Debug builds also take
## `-- --mobile` to preview the phone UI on a desktop. Tests set this directly.
var on_mobile: bool = (
	OS.has_feature("android") or OS.has_feature("ios")
	or (OS.is_debug_build() and OS.get_cmdline_user_args().has("--mobile"))
)
## Tests pin orientation. -1 follows the window, 0 is landscape, 1 is portrait.
var portrait_override: int = -1
var _portrait: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_portrait = is_portrait()
	var root := get_tree().root
	if not root.size_changed.is_connected(_on_viewport_resized):
		root.size_changed.connect(_on_viewport_resized)


func _input(event: InputEvent) -> void:
	if _WINDOW_DISMISS.handle(get_tree(), event, not uses_mobile_ui()):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_set_device(Device.TOUCH)
	elif event is InputEventKey or event is InputEventJoypadButton:
		## The touch menu pad's keys are a finger's.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if event.is_pressed() and not event.is_echo():
			_set_device(Device.KEYS)
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			_set_device(Device.KEYS)


func is_touch() -> bool:
	return device == Device.TOUCH


## The bottom tab bar and verb chips: on a phone or tablet, while touch is the last device.
func shows_touch_buttons() -> bool:
	return on_mobile and is_touch()


## Taller than wide. `portrait_override` lets tests choose without resizing the window.
func is_portrait() -> bool:
	if portrait_override == 0:
		return false
	if portrait_override == 1:
		return true
	var size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2.ZERO
	if size.x <= 1.0 or size.y <= 1.0:
		size = Vector2(DisplayServer.window_get_size())
	return size.y > size.x


## Card sheets and the portrait menu frame. Landscape keeps the desktop windows.
func uses_mobile_ui() -> bool:
	return on_mobile and is_portrait()


func _on_viewport_resized() -> void:
	var next := is_portrait()
	if next == _portrait:
		return
	_portrait = next
	layout_changed.emit()


func _set_device(next: Device) -> void:
	if next == device:
		return
	device = next
	device_changed.emit(device)
