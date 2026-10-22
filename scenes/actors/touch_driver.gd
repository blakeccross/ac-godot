class_name TouchDriver
extends Node

## Touch drives the player through one `PlayerInput` (`scripted_input`), exactly as a stick
## and A / B would: the player can't tell a finger from a pad. There is no on-screen stick.
## - Hold a finger on the ground: the player walks toward the spot under it, running when it
##   is far ahead, and stops on it. Nothing is planned; walls stop it as a held stick would.
## - Tap the player: A (dig, swing, shake, talk to whoever is in front).
## - Tap the ground: walk there along a route round cliffs, water and things in the way
##   (`TouchPath`), steering a stick at each leg; a double tap runs. A ring marks the spot.
## - Tap something (a tree, a villager, fruit, a door): walk up to it, face it and press the
##   button its verb is on: B for what is picked up, A for the rest. A host with verbs on
##   both shows two chips over it to choose from.
## - With the shovel or axe, a tap on a nearby cell digs or swings at it from beside it; with
##   the rod, a tap on water walks to the bank and casts at it; with the line out any tap
##   reels. With the net, a hold raises it and creeps toward the finger; letting go swings.
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
## A tap this close round a miss still picks the object nearest it (720 p pixels).
const PICK_RING_PX := 24.0
## A host is in reach this close (flat metres; a cell is 2 m).
const REACH := 2.2
## A moving host is re-routed to this often, and given up on after this long.
const REPATH_SEC := 0.5
const GIVE_UP_SEC := 5.0
## Physics ticks between facing a host and pressing, so the probe sees the new facing.
const SETTLE_TICKS := 2
## Something else was in front: step toward the host this long, then look again (once).
const NUDGE_SEC := 0.2
## The shovel and axe act on a tapped cell this many cells away at most; farther is a walk.
const TOOL_CELLS := 2

## What the walk is for: nothing, a host to use, a cell to dig or chop, water to cast at.
enum Act { NONE, HOST, CELL, POINT }

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
var _act: Act = Act.NONE
var _act_volume: InteractVolume = null
var _act_b: bool = false
var _act_point := Vector3.ZERO
var _act_time: float = 0.0
var _repath_time: float = 0.0
var _settle: int = 0
var _nudge_time: float = 0.0
var _nudged: bool = false
var _netting: bool = false

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
	_netting = false
	stop_walk()
	source.clear()
	if _player != null and _player.scripted_input == source:
		_player.scripted_input = null


## Test-only: no in-game callers; kept for tests.
func is_following() -> bool:
	return _following


## Test-only: no in-game callers; kept for tests.
func is_walking() -> bool:
	return not _path.is_empty()


## Walking up to something to use it (or about to press).
## Test-only: no in-game callers; kept for tests.
func is_acting() -> bool:
	return _act != Act.NONE


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
	if hud != null:
		hud.hide_chips()
	## Under a menu the finger is the menu's (`TouchMenuPad`).
	if _player != null and (_player._menu_open() or TouchMenuPad.menu_open(get_tree())):
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
	if _netting:
		_netting = false
		source.set_a(false)
	if _following:
		_following = false
		source.move = Vector2.ZERO
		source.dash_held = false
		return
	if _held >= TAP_SEC or _now.distance_to(_start) >= TAP_SLOP_PX * _px():
		return
	## With the line out every tap reels (`relax_rod` takes A and nothing else).
	if _on_self or Fishing.holds(_player):
		source.tap_a()
		return
	if _tap_object(at) or _tap_tool(at):
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
	_cancel_act()
	_start_route(goal, run)
	_place_marker(_path[_path.size() - 1])


## Walk up to `volume`'s host and press B (`pickup`) or A on it.
func approach(volume: InteractVolume, pickup: bool) -> void:
	if volume == null or not install():
		return
	stop_walk()
	_begin_act(Act.HOST, volume.global_position)
	_act_volume = volume
	_act_b = pickup
	if not _in_reach():
		_start_route(volume.global_position, false)


func _start_route(goal: Vector3, run: bool) -> void:
	_path = _route(goal)
	if _path.size() < 2:
		## No route, or one that is a single point (already there): walk straight to the goal.
		_path = PackedVector3Array([_player.global_position, goal])
	_leg = 1
	_running = run
	_rerouted = false
	_stall_time = 0.0
	_stall_from = _player.global_position


func stop_walk() -> void:
	_cancel_act()
	_end_route()


func _end_route() -> void:
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
	_leg = clampi(_leg, 0, _path.size() - 1)
	var to: Vector3 = _path[_leg] - here
	to.y = 0.0
	while to.length() < WAYPOINT_REACH and _leg < _path.size() - 1:
		_leg += 1
		to = _path[_leg] - here
		to.y = 0.0
	var last: bool = _leg == _path.size() - 1
	if last and to.length() <= ARRIVE:
		_end_route()
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
				_end_route()
				return
			_rerouted = true
			var goal: Vector3 = _path[_path.size() - 1]
			var again := _route(goal)
			if again.size() < 2:
				_end_route()
				return
			_path = again
			_leg = 1


func _physics_process(delta: float) -> void:
	if _player == null or _player.scripted_input != source:
		return
	if not _down:
		if _act != Act.NONE:
			_tick_act(delta)
		elif not _path.is_empty():
			_steer(delta)
		return
	_held += delta
	if not _on_self and not _following:
		if _held >= HOLD_SEC or _now.distance_to(_start) >= TAP_SLOP_PX * _px():
			_following = true
			## With the net, holding is holding A: it rises, then creeps after the finger.
			if ToolUse.has(_player.interaction_context(), ToolData.Kind.NET):
				_netting = true
				source.set_a(true)
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


## A tap on something that offers a verb: walk up and use it, or offer chips for two.
func _tap_object(at: Vector2) -> bool:
	var volume: InteractVolume = TouchPick.object(
		get_viewport().get_camera_3d(), at, PICK_RING_PX * _px()
	)
	if volume == null:
		return false
	var verbs: Dictionary = buttons_for(volume)
	var a: Interaction = verbs["a"]
	var b: Interaction = verbs["b"]
	if a == null and b == null:
		return false
	if a != null and b != null:
		var hud := TouchHud.find(get_tree())
		if hud != null and hud.is_showing():
			hud.show_chips(volume, a.prompt, b.prompt, func(pickup: bool) -> void: approach(volume, pickup))
			return true
	approach(volume, a == null)
	return true


## The verb `volume` would give A (`a`) and B (`b`) now: B picks up, A does the rest.
func buttons_for(volume: InteractVolume) -> Dictionary:
	var a_verbs: Array[Interaction] = []
	var b_verbs: Array[Interaction] = []
	for action: Interaction in volume.offers(_player.interaction_context()):
		if action.id == Interaction.PICK_UP:
			b_verbs.append(action)
		else:
			a_verbs.append(action)
	return {"a": Interaction.primary(a_verbs), "b": Interaction.primary(b_verbs)}


## The shovel or axe on a nearby cell (from beside it), the rod on water (from the bank).
func _tap_tool(at: Vector2) -> bool:
	var bg: Array = _player._bg()
	if bg.size() != 2:
		return false
	var kind: ToolData.Kind = ToolUse.kind(_player.interaction_context())
	if kind not in [ToolData.Kind.SHOVEL, ToolData.Kind.AXE, ToolData.Kind.FISHING_ROD]:
		return false
	var hit: Dictionary = TouchPick.ground(get_viewport().get_camera_3d(), at, _player.global_position.y, bg)
	if not bool(hit["hit"]):
		return false
	var data := bg[0] as WorldData
	var grid := bg[1] as WorldGrid
	var pos: Vector3 = hit["pos"]
	var cell: Vector2i = grid.world_to_cell(pos)
	if kind == ToolData.Kind.FISHING_ROD:
		if grid.terrain_at(cell) != WorldGrid.Terrain.WATER:
			return false
		stop_walk()
		_begin_act(Act.POINT, pos)
		_start_route(pos, false)
		return true
	var here: Vector2i = grid.world_to_cell(_player.global_position)
	var off: Vector2i = (cell - here).abs()
	if cell == here or maxi(off.x, off.y) > TOOL_CELLS:
		return false
	var stand: Vector2i = _stand_beside(data, grid, cell, here)
	if stand == Vector2i(-1, -1):
		return false
	stop_walk()
	_begin_act(Act.CELL, grid.cell_to_world(cell))
	if stand != here:
		_start_route(grid.cell_to_world(stand), false)
	return true


## The open cell beside `cell` (four ways) nearest the player, or (-1, -1).
func _stand_beside(data: WorldData, grid: WorldGrid, cell: Vector2i, here: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var side: Vector2i = cell + step
		if side != here and not TouchPath.is_open(data, grid, side):
			continue
		var d: float = grid.cell_to_world(side).distance_squared_to(_player.global_position)
		if d < best_d:
			best_d = d
			best = side
	return best


func _begin_act(act: Act, point: Vector3) -> void:
	_act = act
	_act_point = point
	_act_volume = null
	_act_time = 0.0
	_repath_time = 0.0
	_settle = 0
	_nudge_time = 0.0
	_nudged = false


func _cancel_act() -> void:
	_act = Act.NONE
	_act_volume = null
	_settle = 0
	_nudge_time = 0.0


## One tick of using what was tapped: walk until in reach, face it, settle, press.
func _tick_act(delta: float) -> void:
	if _player._busy or _player._menu_open():
		stop_walk()
		return
	if _act == Act.HOST and (_act_volume == null or not is_instance_valid(_act_volume)):
		stop_walk()
		return
	_act_time += delta
	if _act_time > GIVE_UP_SEC:
		stop_walk()
		return
	if _settle > 0:
		_settle -= 1
		if _settle == 0:
			_press()
		return
	if _nudge_time > 0.0:
		_nudge_time -= delta
		source.move = TouchPick.stick_for(get_viewport().get_camera_3d(), _target() - _player.global_position)
		if _nudge_time <= 0.0:
			_face_and_settle()
		return
	if _act == Act.HOST:
		if _in_reach():
			_face_and_settle()
			return
		## A villager walks on: follow where it is now.
		_repath_time += delta
		if _repath_time >= REPATH_SEC:
			_repath_time = 0.0
			var goal: Vector3 = _act_volume.global_position
			if _path.is_empty() or Vector2(goal.x - _act_point.x, goal.z - _act_point.z).length() > 0.5:
				_act_point = goal
				_start_route(goal, false)
	if not _path.is_empty():
		_steer(delta)
		return
	## The route is walked (or there was none).
	if _act == Act.HOST:
		stop_walk()
	else:
		_face_and_settle()


func _target() -> Vector3:
	if _act == Act.HOST and _act_volume != null:
		return _act_volume.global_position
	return _act_point


func _in_reach() -> bool:
	if _act_volume == null:
		return false
	if _player._probe != null and _player._probe.overlaps_area(_act_volume):
		return true
	var to: Vector3 = _act_volume.global_position - _player.global_position
	return Vector2(to.x, to.z).length() <= REACH


func _face_and_settle() -> void:
	_end_route()
	_player.face_toward(_target())
	_settle = SETTLE_TICKS


## Press the button; for a host, only once the probe has it in front (else nudge once).
func _press() -> void:
	if _act == Act.HOST:
		var query: InteractionQuery = _player.verb_preview(_act_b)
		if query == null or query.host == null or query.host != _act_volume.host:
			if _nudged:
				stop_walk()
				return
			_nudged = true
			_nudge_time = NUDGE_SEC
			return
		if _act_b:
			source.tap_b()
		else:
			source.tap_a()
	else:
		source.tap_a()
	_cancel_act()
