class_name VillagerMotor
extends RefCounted

## Walk / linger motor. FIELD roam targets a goal acre; local wait/walk/run
## matches `aNPC_think_wander_decide_next`.

const ARRIVE := 0.4
const TURN_SPEED := 4.0
## Dest more than 90° behind → turn in place (`aNPC_think_wander_check_ones_way`).
const TURN_ONLY := 1.5708
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
var arrive_radius: float = ARRIVE


func reset(p_home: Vector3, yaw: float = 0.0) -> void:
	home = p_home
	facing = yaw
	target = p_home
	has_target = false
	wait_left = 0.0
	gait = VillagerWalk.ACT_WAIT
	arrive_radius = ARRIVE


func configure(personality: VillagerPersonality) -> void:
	if personality == null:
		return
	walk_speed = personality.walk_speed
	wander_radius = personality.wander_radius


func needs_new_target() -> bool:
	return not has_target and wait_left <= 0.0


func set_target(
	world_pos: Vector3,
	next_gait: StringName = VillagerWalk.ACT_WALK,
	p_arrive: float = ARRIVE
) -> void:
	target = world_pos
	has_target = true
	wait_left = 0.0
	gait = next_gait
	arrive_radius = p_arrive


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
	var to_target: Vector3 = target - from
	to_target.y = 0.0
	if to_target.length() <= arrive_radius:
		arrive()
		return Vector3.ZERO
	var to: Vector3 = next - from
	to.y = 0.0
	## Boxed: no open step. Do not abort just because the next cell center is close —
	## that ended a walk after one unit. Keep the dest until `arrive_radius`.
	if to.length() <= 0.001:
		arrive()
		return Vector3.ZERO
	var yaw: float = atan2(to.x, to.z)
	var diff: float = absf(angle_difference(facing, yaw))
	facing = lerp_angle(facing, yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))
	if diff > TURN_ONLY:
		return Vector3.ZERO
	## Move toward the open step, not along facing, so a run gait cannot orbit.
	return to.normalized() * speed_now()
