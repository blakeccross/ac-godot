class_name VillagerMotor
extends RefCounted

## Walk / linger motor. FIELD roam targets a goal acre; local wait/walk/run
## matches `aNPC_think_wander_decide_next`.
## Dest vs avoid mirrors `dst_pos` / `avoid_pos`: a wall hop must not end the walk.
## Motion matches `aNPC_act_move` + `aNPC_position_move`: face `avoid_pos`, walk
## along facing (not cell-step pathfinding).

const ARRIVE := 0.45
## Walk turn add `0x0200` → 2.8125°/frame @ 30 Hz → ~84.4°/s.
const WALK_TURN := 1.473
## Run turn add `0x0400` → 5.625°/frame → ~168.8°/s (`setup_data` run rows).
const RUN_TURN := 2.945
## Turn-in-place add `0x0800` → 11.25°/frame → ~337.5°/s.
const SPIN_TURN := 5.89
## Dest more than 90° behind → turn first (`aNPC_think_wander_check_ones_way`).
const TURN_ONLY := 1.5708
## Field NPC `aNPC_spd_data`: walk 1.0 GX/frame, run 3.0. Accel/decel ×0.5 in chase.
## 40 GX = 2 m at 30 Hz → 1.5 / 4.5 m/s. Accel 0.05 GX/frame² → 2.25 m/s².
const RUN_SCALE := 3.0
const WALK_SPEED := 1.5
const WALK_ACCEL := 2.25
const WALK_DECEL := 4.5
const RUN_ACCEL := 6.75
const RUN_DECEL := 13.5

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
## `movement.avoid_direction`: 0 = fresh dest, 1/2 = preferred avoid side.
var avoid_direction: int = 0
## Ones-way: spin in place before the walk (`aNPC_ACT_TURN`).
var turn_only: bool = false
var gait: StringName = VillagerWalk.ACT_WAIT
var arrive_radius: float = ARRIVE
var _speed: float = 0.0


func reset(p_home: Vector3, yaw: float = 0.0) -> void:
	home = p_home
	facing = yaw
	target = p_home
	steer = p_home
	has_target = false
	avoid_direction = 0
	turn_only = false
	wait_left = 0.0
	gait = VillagerWalk.ACT_WAIT
	arrive_radius = ARRIVE
	_speed = 0.0


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
	p_arrive: float = ARRIVE,
	from: Vector3 = Vector3.INF,
	yaw: float = INF
) -> void:
	## `aNPC_set_dst_pos` also resets avoid to the same point (`avoid_direction` 0).
	target = world_pos
	steer = world_pos
	has_target = true
	avoid_direction = 0
	wait_left = 0.0
	gait = next_gait
	arrive_radius = p_arrive
	turn_only = false
	if from != Vector3.INF and yaw != INF and next_gait != VillagerWalk.ACT_WAIT:
		var to: Vector3 = world_pos - from
		to.y = 0.0
		if to.length_squared() > 0.0001:
			var want: float = atan2(to.x, to.z)
			turn_only = absf(angle_difference(yaw, want)) > TURN_ONLY


func set_avoid(world_pos: Vector3, side: int = 0, turn_first: bool = false) -> void:
	## `aNPC_set_avoid_pos` — keep `dst_pos`, steer around the wall.
	## `turn_first` matches `aNPC_ACT_TURN` / `aNPC_turn_to_backward` (front hops).
	if not has_target:
		set_target(world_pos)
		return
	steer = world_pos
	wait_left = 0.0
	## `avoid_direction` is always written (front hops keep 0; wall hops set 1/2).
	avoid_direction = side
	turn_only = turn_first
	if gait == VillagerWalk.ACT_WAIT:
		gait = VillagerWalk.ACT_WALK
	if turn_first:
		_speed = 0.0


func wait_in_place(seconds: float = VillagerWalk.WAIT_SECONDS) -> void:
	has_target = false
	steer = target
	avoid_direction = 0
	turn_only = false
	gait = VillagerWalk.ACT_WAIT
	wait_left = seconds
	_speed = 0.0


func pause(seconds: float = VillagerWalk.WAIT_SECONDS) -> void:
	## Brief stop without abandoning the rim dest (avoid failed / turn).
	wait_left = seconds
	_speed = 0.0


func arrive() -> void:
	has_target = false
	steer = target
	turn_only = false
	wait_left = 0.0
	gait = VillagerWalk.ACT_WAIT
	_speed = 0.0


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
	_chase_facing(yaw, SPIN_TURN * delta)


func tick(delta: float, from: Vector3, _next: Vector3, moving: bool) -> Vector3:
	## Decomp frame order: move along *current* facing, then chase `mv_angl` after think.
	if not moving:
		has_target = false
		_speed = 0.0
		return Vector3.ZERO
	if wait_left > 0.0:
		wait_left = maxf(0.0, wait_left - delta)
		_speed = 0.0
		return Vector3.ZERO
	if not has_target:
		_speed = 0.0
		return Vector3.ZERO
	## `aNPC_check_arrive_destination`: near avoid_pos. If avoid ≠ dst, resume dst.
	var to_steer: Vector3 = steer - from
	to_steer.y = 0.0
	if to_steer.length() <= arrive_radius:
		if not is_avoiding():
			arrive()
			return Vector3.ZERO
		steer = target
		avoid_direction = 0
		to_steer = steer - from
		to_steer.y = 0.0
	if to_steer.length_squared() < 0.0001:
		return Vector3.ZERO
	var yaw: float = atan2(to_steer.x, to_steer.z)
	if turn_only:
		_chase_facing(yaw, SPIN_TURN * delta)
		if absf(angle_difference(facing, yaw)) <= deg_to_rad(2.0):
			turn_only = false
		_speed = 0.0
		return Vector3.ZERO
	## Move on this frame's facing first (`aNPC_position_move` before `aNPC_angle_calc`).
	_chase_speed(delta)
	var step := Vector3(sin(facing), 0.0, cos(facing)) * _speed
	_chase_facing(yaw, _move_turn_rate() * delta)
	return step


func _move_turn_rate() -> float:
	## Walk actions `0x0200`, run `0x0400` in `aNPC_setupAction`.
	if gait == VillagerWalk.ACT_RUN:
		return RUN_TURN
	return WALK_TURN


func _chase_facing(yaw: float, max_step: float) -> void:
	var diff: float = angle_difference(facing, yaw)
	facing = facing + clampf(diff, -max_step, max_step)


func _chase_speed(delta: float) -> void:
	## `chase_f(speed, max, accel*0.5)` each frame @ 30 Hz.
	var max_spd: float = speed_now()
	var rate: float = WALK_ACCEL if gait != VillagerWalk.ACT_RUN else RUN_ACCEL
	if _speed > max_spd:
		rate = WALK_DECEL if gait != VillagerWalk.ACT_RUN else RUN_DECEL
	var step: float = rate * delta
	if absf(max_spd - _speed) <= step:
		_speed = max_spd
	elif _speed < max_spd:
		_speed += step
	else:
		_speed -= step
