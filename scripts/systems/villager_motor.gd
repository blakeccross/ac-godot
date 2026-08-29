class_name VillagerMotor
extends RefCounted

## Walk / linger motor. FIELD roam targets a goal acre; local wait/walk/run
## matches `aNPC_think_wander_decide_next`.
## Dest vs avoid mirrors `dst_pos` / `avoid_pos`: a wall hop must not end the walk.

const ARRIVE := 0.4
const TURN_SPEED := 4.0
## Dest more than 90° behind → turn in place (`aNPC_think_wander_check_ones_way`).
const TURN_ONLY := 1.5708
## Field NPC `aNPC_spd_data`: walk 1.0 GX/frame, run 3.0. Shop/special NPCs
## override to 4.0 GX; villagers do not. 40 GX = 2 m at 30 Hz → 1.5 / 4.5 m/s.
const RUN_SCALE := 3.0
const WALK_SPEED := 1.5

var walk_speed: float = WALK_SPEED
var wander_radius: float = 14.0
var home: Vector3 = Vector3.ZERO
var facing: float = 0.0
var wait_left: float = 0.0
## Rim / walk goal (`dst_pos`). Arrive ends the wander step only here.
var target: Vector3 = Vector3.ZERO
## Current steer point (`avoid_pos`). Wall avoid updates this; dest stays.
var steer: Vector3 = Vector3.ZERO
var has_target: bool = false
var gait: StringName = VillagerWalk.ACT_WAIT
var arrive_radius: float = ARRIVE


func reset(p_home: Vector3, yaw: float = 0.0) -> void:
	home = p_home
	facing = yaw
	target = p_home
	steer = p_home
	has_target = false
	wait_left = 0.0
	gait = VillagerWalk.ACT_WAIT
	arrive_radius = ARRIVE


func configure(personality: VillagerPersonality) -> void:
	if personality == null:
		return
	## Looks change wait/walk/run *odds*, not max speed (`aNPC_spd_data` is shared).
	walk_speed = personality.walk_speed if personality.walk_speed > 0.0 else WALK_SPEED
	wander_radius = personality.wander_radius
	if wander_radius < VillagerWalk.RANGE_RADIUS * 0.5:
		wander_radius = VillagerWalk.RANGE_RADIUS


func needs_new_target() -> bool:
	return not has_target and wait_left <= 0.0


func set_target(
	world_pos: Vector3,
	next_gait: StringName = VillagerWalk.ACT_WALK,
	p_arrive: float = ARRIVE
) -> void:
	## `aNPC_set_dst_pos` also resets avoid to the same point.
	target = world_pos
	steer = world_pos
	has_target = true
	wait_left = 0.0
	gait = next_gait
	arrive_radius = p_arrive


func set_avoid(world_pos: Vector3) -> void:
	## `aNPC_set_avoid_pos` — keep `dst_pos`, steer around the wall.
	if not has_target:
		set_target(world_pos)
		return
	steer = world_pos
	wait_left = 0.0
	if gait == VillagerWalk.ACT_WAIT:
		gait = VillagerWalk.ACT_WALK


func wait_in_place(seconds: float = VillagerWalk.WAIT_SECONDS) -> void:
	has_target = false
	steer = target
	gait = VillagerWalk.ACT_WAIT
	wait_left = seconds


func pause(seconds: float = VillagerWalk.WAIT_SECONDS) -> void:
	## Brief stop without abandoning the rim dest (avoid failed / turn).
	wait_left = seconds


func arrive() -> void:
	has_target = false
	steer = target
	wait_left = 0.0
	gait = VillagerWalk.ACT_WAIT


func is_avoiding() -> bool:
	if not has_target:
		return false
	var delta: Vector3 = steer - target
	delta.y = 0.0
	return delta.length() > arrive_radius


func random_offset() -> Vector3:
	var angle: float = randf() * TAU
	var radius: float = sqrt(randf()) * wander_radius
	return Vector3(sin(angle) * radius, 0.0, cos(angle) * radius)


func speed_now() -> float:
	if gait == VillagerWalk.ACT_RUN:
		return walk_speed * RUN_SCALE
	return walk_speed


func turn_toward(delta: float, from: Vector3, look_at: Vector3) -> void:
	var to: Vector3 = look_at - from
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	var yaw: float = atan2(to.x, to.z)
	facing = lerp_angle(facing, yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))


func tick(delta: float, from: Vector3, next: Vector3, moving: bool) -> Vector3:
	if not moving:
		has_target = false
		return Vector3.ZERO
	if wait_left > 0.0:
		wait_left = maxf(0.0, wait_left - delta)
		return Vector3.ZERO
	if not has_target:
		return Vector3.ZERO
	## `aNPC_check_arrive_destination`: near avoid_pos. If avoid ≠ dst, resume dst.
	var to_steer: Vector3 = steer - from
	to_steer.y = 0.0
	if to_steer.length() <= arrive_radius:
		if not is_avoiding():
			arrive()
			return Vector3.ZERO
		steer = target
	var to: Vector3 = next - from
	to.y = 0.0
	## No open step this frame. Keep the dest — `aNPC_avoid_wall` steers; do not
	## end the walk because the next cell center is underfoot.
	if to.length() <= 0.001:
		return Vector3.ZERO
	var yaw: float = atan2(to.x, to.z)
	var diff: float = absf(angle_difference(facing, yaw))
	facing = lerp_angle(facing, yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))
	if diff > TURN_ONLY:
		return Vector3.ZERO
	## Move toward the open step / steer point, not along facing.
	return to.normalized() * speed_now()
