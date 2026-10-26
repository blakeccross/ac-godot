extends Node

## Which device the player last used: a finger, or keys / a pad. The touch HUD
## shows only while it is `TOUCH`, and the touch driver gives the player back to
## the stick when a key or button comes in.

enum Device { KEYS, TOUCH }

signal device_changed(device: Device)

var device: Device = Device.KEYS
## Android or iOS: on-screen buttons show only there (a desktop has keys and a mouse).
## Tests set it to check the buttons.
var on_mobile: bool = OS.has_feature("android") or OS.has_feature("ios")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
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


## On-screen buttons: on a phone or tablet, while touch is the last device used.
func shows_touch_buttons() -> bool:
	return on_mobile and is_touch()


func _set_device(next: Device) -> void:
	if next == device:
		return
	device = next
	device_changed.emit(device)
