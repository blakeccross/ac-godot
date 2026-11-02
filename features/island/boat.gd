class_name Boat
extends Node3D

## Kapp'n's dinghy (`ac_boat`, `obj_e_boat`): moored at the wharf or the landing, or sailing the
## route (`aBT_move`): it cruises at 0.625 GX a tick, turns toward each way-point, bobs and rolls on the
## swell, and eases to a stop at the last one (`aBT_calc_speed` target 0, step 0.0017 a tick).

signal arrived

const VISUAL := &"obj_e_boat"
const SLOW_STEP := 0.0017 * 60.0 * 60.0 * IslandRoute.METERS_PER_GX
const ACCEL := 0.01 * 60.0 * 60.0 * IslandRoute.METERS_PER_GX
const TURN_RATE := deg_to_rad(40.0)
const BOB_HEIGHT := 0.04
const BOB_RATE := 1.6
const ROLL := deg_to_rad(2.0)
## Where Kapp'n stands in the boat (`aSEN_set_matrix`: -8, 20, -34 GX) and the passenger beside him.
const KAPPN_SEAT := Vector3(-0.4, 1.0, -1.7)
const PASSENGER_SEAT := Vector3(0.0, 1.0, 0.4)

var _points: Array[Vector3] = []
var _next: int = 0
var _speed: float = 0.0
var _base_y: float = 0.0
var _clock: float = 0.0
var _sailing: bool = false
var _surface: Callable = Callable()


## Moor at `at` (world metres) facing `yaw`. `surface` maps a world point to the water height.
func moor(at: Vector3, yaw: float, surface: Callable) -> void:
	_surface = surface
	_base_y = _water(at)
	global_position = Vector3(at.x, _base_y, at.z)
	rotation.y = yaw
	_sailing = false
	_speed = 0.0


## Sail through `points` (world metres), the first being where it already is.
func sail(points: Array[Vector3]) -> void:
	_points = points
	_next = 1
	_speed = 0.0
	_sailing = true


func is_sailing() -> bool:
	return _sailing


func surface() -> Callable:
	return _surface


## A seat's world position.
func seat(local: Vector3) -> Vector3:
	return global_transform * local


func _ready() -> void:
	var mount := get_node_or_null("Model") as Node3D
	if mount != null and GeneratedVisual.attach(mount, VISUAL) == null:
		GeneratedVisual.mark_missing(mount, VISUAL)


func _physics_process(delta: float) -> void:
	_clock += delta
	if _sailing:
		_steer(delta)
	var swell: float = sin(_clock * BOB_RATE)
	position.y = _base_y + swell * BOB_HEIGHT
	rotation.z = sin(_clock * BOB_RATE * 0.7) * ROLL


func _steer(delta: float) -> void:
	var last: bool = _next >= _points.size() - 1
	var target: Vector3 = _points[mini(_next, _points.size() - 1)]
	var to := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var dist: float = to.length()
	if dist > 0.001:
		var want: float = atan2(to.x, to.z)
		rotation.y += clampf(wrapf(want - rotation.y, -PI, PI), -TURN_RATE * delta, TURN_RATE * delta)
	var cruise: float = IslandRoute.CRUISE
	## Slow to a stop over the last stretch (`aBT_calc_speed`).
	var want_speed: float = cruise
	if last:
		want_speed = minf(cruise, sqrt(2.0 * SLOW_STEP * 4.0 * maxf(dist, 0.0)))
	_speed = move_toward(_speed, want_speed, ACCEL * delta)
	var step: float = minf(_speed * delta, dist)
	if dist > 0.001:
		global_position += to / dist * step
	_base_y = _water(global_position)
	var reached: bool = dist <= 0.12 or (not last and dist <= 1.0)
	if reached:
		if last:
			_sailing = false
			_speed = 0.0
			arrived.emit()
		else:
			_next += 1


## `world.position.y = 1.0 + water height` (`aBT_actor_ct`): a GX above the surface.
func _water(at: Vector3) -> float:
	if _surface.is_valid():
		return float(_surface.call(at)) + 1.0 * IslandRoute.METERS_PER_GX
	return 0.0
