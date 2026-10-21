class_name TouchDriver
extends Node

## Touch drives the player through one `PlayerInput` (`scripted_input`), exactly as a stick
## and A / B would: the player can't tell a finger from a pad. There is no on-screen stick.
## - Hold a finger on the ground: the player walks toward the spot under it, running when it
##   is far ahead, and stops on it. Nothing is planned; walls stop it as a held stick would.
## - Tap the player: A (dig, swing, shake, talk to whoever is in front).
## The first key or pad press hands the player back to them. The title demo's recording is
## never replaced.

## A press this close to the player's screen point is on the player (720 p pixels).
const SELF_RADIUS_PX := 64.0
## Held this long, or moved this far, a press on the ground becomes a follow.
const HOLD_SEC := 0.2
const TAP_SLOP_PX := 16.0
## A tap on the player is shorter than this.
const TAP_SEC := 0.25
## Following: run beyond this far, stop within this close.
const RUN_DIST := 4.0
const FOLLOW_STOP := 0.3
## Height of the player's middle, for where the player is on screen.
const BODY_MID := 0.8

var source := PlayerInput.new()

var _down: bool = false
var _on_self: bool = false
var _following: bool = false
var _start := Vector2.ZERO
var _now := Vector2.ZERO
var _held: float = 0.0

var _player: Player:
	get:
		if _player == null:
			_player = get_parent() as Player
		return _player


func _ready() -> void:
	## Ahead of the player, so its walk reads this tick's stick.
	process_physics_priority = -1
	var tracker: Node = get_node_or_null("/root/InputDeviceTracker")
	if tracker != null:
		tracker.connect("device_changed", _on_device_changed)


func _on_device_changed(device: int) -> void:
	if device == InputDeviceTracker.Device.KEYS:
		release()


## Take the player (unless the title demo's recording is driving it).
func install() -> bool:
	if _player == null:
		return false
	if _player.scripted_input == source:
		return true
	if _player.scripted_input != null:
		return false
	_player.scripted_input = source
	return true


## Give the player back to the keys and pad.
func release() -> void:
	_down = false
	_following = false
	source.clear()
	if _player != null and _player.scripted_input == source:
		_player.scripted_input = null


func is_following() -> bool:
	return _following


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index != 0:
			return
		if touch.pressed:
			press(touch.position)
		else:
			lift(touch.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != 0 or not _down:
			return
		_now = drag.position
		get_viewport().set_input_as_handled()


func press(at: Vector2) -> void:
	var hud := TouchHud.find(get_tree())
	if hud != null and hud.covers(at):
		return
	if not install():
		return
	_down = true
	_start = at
	_now = at
	_held = 0.0
	_following = false
	_on_self = _near_player(at)


func lift(at: Vector2) -> void:
	if not _down:
		return
	_now = at
	_down = false
	if _following:
		_following = false
		source.move = Vector2.ZERO
		source.dash_held = false
		return
	if _on_self and _held < TAP_SEC and _now.distance_to(_start) < TAP_SLOP_PX * _px():
		source.tap_a()


func _physics_process(delta: float) -> void:
	if _player == null or _player.scripted_input != source:
		return
	if not _down:
		return
	_held += delta
	if not _on_self and not _following:
		if _held >= HOLD_SEC or _now.distance_to(_start) >= TAP_SLOP_PX * _px():
			_following = true
	if _following:
		_follow()


## Steer straight for the ground under the finger.
func _follow() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var hit: Dictionary = TouchPick.ground(cam, _now, _player.global_position.y, _player._bg())
	if not bool(hit["hit"]):
		source.move = Vector2.ZERO
		return
	var to: Vector3 = (hit["pos"] as Vector3) - _player.global_position
	to.y = 0.0
	var dist: float = to.length()
	if dist <= FOLLOW_STOP:
		source.move = Vector2.ZERO
		source.dash_held = false
		return
	source.move = TouchPick.stick_for(cam, to)
	source.dash_held = dist > RUN_DIST


func _near_player(at: Vector2) -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or _player == null:
		return false
	var mid: Vector3 = _player.global_position + Vector3.UP * BODY_MID
	if cam.is_position_behind(mid):
		return false
	return cam.unproject_position(mid).distance_to(at) <= SELF_RADIUS_PX * _px()


## 720 p pixels → this viewport's pixels.
func _px() -> float:
	var h: float = get_viewport().get_visible_rect().size.y
	return h / 720.0 if h > 0.0 else 1.0
