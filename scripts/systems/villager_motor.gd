class_name VillagerMotor
extends RefCounted

## Walk / linger motor. FIELD roam targets a goal acre; local wait/walk/run
## matches `aNPC_think_wander_decide_next`.

const ARRIVE := 0.4
const TURN_SPEED := 4.0
## NPC run is 4.0 GX/frame vs walk 1.0.
const RUN_SCALE := 4.0

var walk_speed: float = 1.5
var wander_radius: float = 14.0
var home: Vector3 = Vector3.ZERO
var facing: float = 0.0
var wait_left: float = 0.0
var target: Vector3 = Vector3.ZERO
var has_target: bool = false
var gait: StringName = VillagerWalk.ACT_WAIT


func reset(p_home: Vector3, yaw: float = 0.0) -> void:
	home = p_home
	facing = yaw
	target = p_home
	has_target = false
	wait_left = 0.0
	gait = VillagerWalk.ACT_WAIT


func configure(personality: VillagerPersonality) -> void:
	if personality == null:
		return
	walk_speed = personality.walk_speed
	wander_radius = personality.wander_radius


func needs_new_target() -> bool:
	return not has_target and wait_left <= 0.0


func set_target(world_pos: Vector3, next_gait: StringName = VillagerWalk.ACT_WALK) -> void:
	target = world_pos
	has_target = true
	wait_left = 0.0
	gait = next_gait


func wait_in_place(seconds: float = VillagerWalk.WAIT_SECONDS) -> void:
	has_target = false
	gait = VillagerWalk.ACT_WAIT
	wait_left = seconds


func arrive() -> void:
	has_target = false
	wait_left = 0.0
	gait = VillagerWalk.ACT_WAIT


func random_offset() -> Vector3:
	var angle: float = randf() * TAU
	var radius: float = sqrt(randf()) * wander_radius
	return Vector3(sin(angle) * radius, 0.0, cos(angle) * radius)


func speed_now() -> float:
	if gait == VillagerWalk.ACT_RUN:
		return walk_speed * RUN_SCALE
	return walk_speed


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
	return Vector3(sin(facing), 0.0, cos(facing)) * speed_now()
