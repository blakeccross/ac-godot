class_name VillagerMotor
extends RefCounted

## Walk / linger motor. FIELD roam targets a goal acre; local waits are between cells.

const ARRIVE := 0.4
const TURN_SPEED := 4.0
const WAIT_MIN := 2.0
const WAIT_MAX := 5.5

var walk_speed: float = 1.6
var wander_radius: float = 6.0
var home: Vector3 = Vector3.ZERO
var facing: float = 0.0
var wait_left: float = 0.5
var target: Vector3 = Vector3.ZERO
var has_target: bool = false


func reset(p_home: Vector3, yaw: float = 0.0) -> void:
	home = p_home
	facing = yaw
	target = p_home
	has_target = false
	wait_left = 0.4


func configure(personality: VillagerPersonality) -> void:
	if personality == null:
		return
	walk_speed = personality.walk_speed
	wander_radius = personality.wander_radius


func needs_new_target() -> bool:
	return not has_target and wait_left <= 0.0


func set_target(world_pos: Vector3) -> void:
	target = world_pos
	has_target = true
	wait_left = 0.0


func arrive() -> void:
	has_target = false
	wait_left = randf_range(WAIT_MIN, WAIT_MAX)


func random_offset() -> Vector3:
	var angle: float = randf() * TAU
	var radius: float = sqrt(randf()) * wander_radius
	return Vector3(sin(angle) * radius, 0.0, cos(angle) * radius)


func tick(delta: float, from: Vector3, next: Vector3, moving: bool) -> Vector3:
	if not moving:
		has_target = false
		return Vector3.ZERO
	if wait_left > 0.0:
		wait_left = maxf(0.0, wait_left - delta)
		return Vector3.ZERO
	if not has_target:
		return Vector3.ZERO
	var aim: Vector3 = next
	var to_next: Vector3 = next - from
	to_next.y = 0.0
	var to_target: Vector3 = target - from
	to_target.y = 0.0
	## Nav next-point can sit under the actor (flat mesh at y=0.05 vs heightfield).
	if to_next.length() <= ARRIVE and to_target.length() > ARRIVE:
		aim = target
	var to: Vector3 = aim - from
	to.y = 0.0
	if to.length() <= ARRIVE:
		arrive()
		return Vector3.ZERO
	var yaw: float = atan2(to.x, to.z)
	facing = lerp_angle(facing, yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))
	return Vector3(sin(facing), 0.0, cos(facing)) * walk_speed
