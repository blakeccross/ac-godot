class_name TouchDriver
extends Node

## Touch drives the player through one `PlayerInput` (`scripted_input`), exactly as a stick
## and A / B would: the player can't tell a finger from a pad. There is no on-screen stick.
## - Hold a finger on the ground: the player walks toward the spot under it, running when it
##   is far ahead, and stops on it. Nothing is planned; walls stop it as a held stick would.
## - Tap the player: A (dig, swing, shake, talk to whoever is in front).
## - Tap the ground: walk there along a route round cliffs, water and things in the way
##   (`TouchPath`), steering a stick at each leg; a double tap runs. A ring marks the spot.
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
## Walking a route: the next corner counts as reached this close; the end this close. Over
## the last metre the stick eases off (not below 0.35) so the walk doesn't overshoot.
const WAYPOINT_REACH := 0.35
const ARRIVE := 0.25
const EASE_DIST := 1.0
const MIN_STICK := 0.35
## Stuck: moved less than this in this long. Re-route once, then give up.
const STALL_DIST := 0.05
const STALL_SEC := 0.3
## A second tap this soon and this close runs.
const DOUBLE_TAP_SEC := 0.3
const DOUBLE_TAP_PX := 40.0
const MARKER := preload("res://scenes/world/touch_marker.tscn")

var source := PlayerInput.new()

var _down: bool = false
var _on_self: bool = false
var _following: bool = false
var _start := Vector2.ZERO
var _now := Vector2.ZERO
var _held: float = 0.0
var _path := PackedVector3Array()
var _leg: int = 0
var _running: bool = false
var _stall_time: float = 0.0
var _stall_from := Vector3.ZERO
var _rerouted: bool = false
var _last_tap_msec: int = -100000
var _last_tap_at := Vector2(-9999, -9999)
var _marker: Node3D = null

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
	stop_walk()
	source.clear()
	if _player != null and _player.scripted_input == source:
		_player.scripted_input = null


func is_following() -> bool:
	return _following


func is_walking() -> bool:
	return not _path.is_empty()


func route() -> PackedVector3Array:
	return _path


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
	stop_walk()


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
	if _held >= TAP_SEC or _now.distance_to(_start) >= TAP_SLOP_PX * _px():
		return
	if _on_self:
		source.tap_a()
		return
	var now_msec: int = Time.get_ticks_msec()
	var run: bool = (
		now_msec - _last_tap_msec <= int(DOUBLE_TAP_SEC * 1000.0)
		and at.distance_to(_last_tap_at) <= DOUBLE_TAP_PX * _px()
	)
	_last_tap_msec = now_msec
	_last_tap_at = at
	walk_to_screen(at, run)


## Walk to the ground under a screen point (`run`: a double tap).
func walk_to_screen(at: Vector2, run: bool = false) -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var hit: Dictionary = TouchPick.ground(cam, at, _player.global_position.y, _player._bg())
	if not bool(hit["hit"]):
		return false
	walk_to(hit["pos"] as Vector3, run)
	return true


## Route to `goal` and start walking it; a straight line when there's no route.
func walk_to(goal: Vector3, run: bool = false) -> void:
	if not install():
		return
	_path = _route(goal)
	if _path.is_empty():
		_path = PackedVector3Array([_player.global_position, goal])
	_leg = 1
	_running = run
	_rerouted = false
	_stall_time = 0.0
	_stall_from = _player.global_position
	_place_marker(_path[_path.size() - 1])


func stop_walk() -> void:
	_path = PackedVector3Array()
	_leg = 0
	_running = false
	source.move = Vector2.ZERO
	source.dash_held = false
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null


func _route(goal: Vector3) -> PackedVector3Array:
	var bg: Array = _player._bg()
	if bg.size() == 2:
		return TouchPath.find(bg[0] as WorldData, bg[1] as WorldGrid, _player.global_position, goal)
	var session: IndoorSession = Game.interior_session if Game != null else null
	if Game != null and Game.is_indoors() and session != null and session.grid != null:
		return TouchPath.find(null, session.grid, _player.global_position, goal, session.room)
	return PackedVector3Array()


func _place_marker(at: Vector3) -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	var parent: Node = _player.get_parent()
	if parent == null:
		return
	_marker = MARKER.instantiate() as Node3D
	parent.add_child(_marker)
	_marker.global_position = at


## One tick along the route: a full stick toward the next corner, easing off on the last metre.
func _steer(delta: float) -> void:
	if _player._busy or _player._menu_open():
		stop_walk()
		return
	var here: Vector3 = _player.global_position
	var to: Vector3 = _path[_leg] - here
	to.y = 0.0
	while to.length() < WAYPOINT_REACH and _leg < _path.size() - 1:
		_leg += 1
		to = _path[_leg] - here
		to.y = 0.0
	var last: bool = _leg == _path.size() - 1
	if last and to.length() <= ARRIVE:
		stop_walk()
		return
	var stick: Vector2 = TouchPick.stick_for(get_viewport().get_camera_3d(), to)
	var end_dist: float = to.length() if last else INF
	source.move = stick * clampf(end_dist / EASE_DIST, MIN_STICK, 1.0)
	source.dash_held = _running and end_dist > EASE_DIST
	## Stuck against something new (a villager, a tree planted since): re-route once.
	_stall_time += delta
	if _stall_time >= STALL_SEC:
		var moved: float = Vector2(here.x - _stall_from.x, here.z - _stall_from.z).length()
		_stall_time = 0.0
		_stall_from = here
		if moved < STALL_DIST:
			if _rerouted:
				stop_walk()
				return
			_rerouted = true
			var goal: Vector3 = _path[_path.size() - 1]
			var again := _route(goal)
			if again.is_empty():
				stop_walk()
				return
			_path = again
			_leg = 1


func _physics_process(delta: float) -> void:
	if _player == null or _player.scripted_input != source:
		return
	if not _down:
		if not _path.is_empty():
			_steer(delta)
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
