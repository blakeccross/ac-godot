class_name VillagerMover
extends Node

## How a villager gets about: steering toward the activity's goal or round its wander
## circle (`VillagerWalk`), sliding off walls and other actors, and the acre-by-acre
## walk across town (`ac_set_npc_manager`). A child of the `Villager`; it reads the
## villager's motor and AI directly.

## Enter a new acre this many units past the shared edge (`aNPC_think_in_block` ~120 GX).
const ACRE_ENTRY_DEPTH := 2
## Give up on a goal acre after this long stuck in one acre mid-relocation.
const RELOCATE_GIVEUP := 14.0

## Time spent in one acre while still relocating toward `_goal_block`.
var _relocate_time: float = 0.0

## The Villager this belongs to (the parent), found on first use: tests build scenes
## without adding them to the tree.
var _villager: Villager:
	get:
		if _villager == null:
			_villager = get_parent() as Villager
		return _villager


func steer_ai() -> void:
	if _villager.ai.is_wandering() and _villager._tick_chase():
		return
	if _villager.ai.is_wandering() and _villager._tick_fortune():
		return
	if _villager.ai.is_wandering():
		if _villager._travel_stand != Vector3.INF:
			## Relocating: walk to the next acre's entry unit (walk row, no circle clamp).
			_steer_to(_villager._travel_stand)
			return
		## `aNPC_check_fatigue` in `chk_interrupt` interrupts a walk mid-stride, not just
		## the next `decide_next`; drop the target so `_steer_wander` rolls a WAIT.
		if (_villager._resting or _villager._is_sleepy()) and _villager._motor.has_target and _villager._motor.wait_left <= 0.0:
			_villager._motor.arrive()
		## Boxed in against a structure for too long: abandon the rim dest and re-roll,
		## like the decomp's `avoid_wall` → `turn_to_backward` → `decide_next` → WAIT.
		if _villager._wall_time > VillagerWalk.STUCK_SECONDS and _villager._motor.has_target:
			_villager._motor.arrive()
			_villager._wall_time = 0.0
		_steer_wander(true)
		return
	if _villager.ai.wants_move():
		_steer_to(_villager.ai.destination())
		return
	_steer_wander(false)


func _steer_wander(wandering: bool) -> void:
	if not wandering:
		if _villager._agent != null and nav_ready():
			_villager._agent.target_position = _villager.global_position
		return
	if not _villager._motor.needs_new_target():
		return
	## `aNPC_think_wander_decide_next`: fatigue or a sleepy mood forces a rest wait.
	var act: StringName = VillagerWalk.pick_act(_villager._looks())
	if _villager._resting or _villager._is_sleepy():
		act = VillagerWalk.ACT_WAIT
	if act == VillagerWalk.ACT_WAIT:
		_villager._motor.wait_in_place()
		return
	var dest: Vector3 = _roam_point()
	var delta: Vector3 = dest - _villager.global_position
	delta.y = 0.0
	if delta.length() < VillagerWalk.MIN_STEP:
		_villager._motor.wait_in_place()
		return
	_villager._avoid_cool = 0.0
	_villager._motor.set_target(dest, act, VillagerWalk.WANDER_ARRIVE, _villager.global_position, _villager._motor.facing)
	if _villager._agent != null and nav_ready():
		_villager._agent.target_position = dest


func _steer_to(world_pos: Vector3) -> void:
	if _villager._motor.wait_left > 0.0:
		return
	var dest: Vector3 = _walkable_near(world_pos)
	if _villager._motor.has_target:
		var to_goal: float = _villager._motor.target.distance_to(dest)
		var to_here: Vector3 = _villager._motor.target - _villager.global_position
		to_here.y = 0.0
		if to_goal > 0.35 and to_here.length() > VillagerWalk.WANDER_ARRIVE:
			return
	_villager._avoid_cool = 0.0
	_villager._motor.set_target(
		dest, VillagerWalk.ACT_WALK, VillagerMotor.ARRIVE, _villager.global_position, _villager._motor.facing
	)
	if _villager._agent != null and nav_ready():
		_villager._agent.target_position = dest


func nav_ready() -> bool:
	if _villager._agent == null or not is_inside_tree():
		return false
	var map: RID = _villager._agent.get_navigation_map()
	return NavigationServer3D.map_get_iteration_id(map) > 0


func _walkable_near(world_pos: Vector3) -> Vector3:
	var bg: Array = _villager._bg()
	if bg.size() != 2:
		return world_pos
	var pos: Vector3 = VillagerWalk.snap_standable(bg[0] as WorldData, world_pos)
	pos.y = world_pos.y
	return pos


func collision_flags(before: Vector3, planar: Vector3, delta: float) -> int:
	## `aNPC_BGcheck` then `aNPC_forward_check` OR into `collision_flag`.
	var flags: int = 0
	var intended := Vector3(sin(_villager._motor.facing), 0.0, cos(_villager._motor.facing))
	var speed_xz := Vector2(planar.x, planar.z).length()
	if speed_xz > Villager.IDLE_SPEED and delta > 0.0:
		var moved: Vector3 = _villager.global_position - before
		moved.y = 0.0
		var expected: float = speed_xz * delta
		if moved.dot(intended) < expected * Villager.STUCK_FRAC:
			## Front wall from BG revise — same as hit_wall FRONT|WALL (= 3).
			flags = VillagerWalk.HIT_WALL | VillagerWalk.HIT_WALL_FRONT
	if _villager.get_slide_collision_count() > 0 and _slide_is_front(planar):
		flags = VillagerWalk.HIT_WALL | VillagerWalk.HIT_WALL_FRONT
	## Lateral half-unit probes (`aNPC_forward_check`) — not a forward ray.
	## Only against the roam circle while actually wandering it (`range_type` CIRCLE).
	if (
		_villager.ai.is_wandering()
		and _villager._travel_stand == Vector3.INF
		and in_wander_block()
		and speed_xz > Villager.IDLE_SPEED
	):
		var bg: Array = _villager._bg()
		if bg.size() == 2:
			flags |= VillagerWalk.forward_check_flags(
				bg[0] as WorldData,
				_villager._wander_block,
				before,
				_villager._motor.facing,
				before.y,
				bg[1] as WorldGrid
			)
	return flags


func _slide_is_front(planar: Vector3) -> bool:
	var move_dir := Vector3(sin(_villager._motor.facing), 0.0, cos(_villager._motor.facing))
	if planar.length_squared() > 0.0001:
		move_dir = Vector3(planar.x, 0.0, planar.z).normalized()
	for i: int in _villager.get_slide_collision_count():
		var col: KinematicCollision3D = _villager.get_slide_collision(i)
		if col == null:
			continue
		var n: Vector3 = col.get_normal()
		n.y = 0.0
		if n.length_squared() < 0.0001:
			continue
		if move_dir.dot(n.normalized()) < -0.15:
			return true
	return false


func steer_around_wall(flags: int) -> void:
	## `aNPC_avoid_obstacle`: a side hit (1/2) veers around it on the committed side
	## (`aNPC_avoid_wall`, keeps `dst_pos`); a front hit (3) turns ~112.5° away and
	## re-rolls the wander dest (`aNPC_turn_to_backward` → `decide_next` → WAIT/move_next).
	## Don't stack a fresh hop while still turning into the last one.
	if _villager._motor.turn_only:
		return
	var bg: Array = _villager._bg()
	if bg.size() != 2:
		_villager._motor.pause()
		return
	var world_data: WorldData = bg[0] as WorldData
	var grid: WorldGrid = bg[1] as WorldGrid
	var here: Vector2i = VillagerWalk.block_from_cell(grid.world_to_cell(_villager.global_position))
	if not VillagerWalk.is_fg_block(here):
		here = _villager._wander_block

	if flags == VillagerWalk.HIT_WALL or flags == VillagerWalk.HIT_WALL_FRONT:
		## Right rise → veer left (prefer_side 2, −angles); left rise → veer right (1).
		var pref: int = 2 if flags == VillagerWalk.HIT_WALL else 1
		var side: int = _villager._motor.avoid_direction
		if side != 1 and side != 2:
			side = pref
			_villager._motor.avoid_tier = 0
		var tier: int = _villager._motor.avoid_tier
		var around: Vector3 = VillagerWalk.avoid_around(
			world_data, _villager.global_position, _villager._motor.facing, here, side, tier
		)
		if (around - _villager.global_position).length() > 0.05:
			## n == 0 keeps walking (`set_avoid_pos`); n > 0 is an `ACT_TURN` first.
			_villager._motor.set_avoid(around, side, tier > 0)
			_villager._motor.avoid_tier = mini(tier + 1, VillagerWalk.AVOID_TIERS - 1)
			_villager._avoid_cool = 0.35
			return
	## Front+wall, or a side veer that had nowhere to go → retreat and re-roll.
	var retreat: Vector3 = VillagerWalk.retreat_hop(
		world_data, _villager.global_position, _villager._motor.facing, here
	)
	_villager._motor.set_target(
		retreat, VillagerWalk.ACT_WALK, VillagerMotor.ARRIVE, _villager.global_position, _villager._motor.facing
	)
	_villager._motor.avoid_tier = 0
	_villager._avoid_cool = 0.4


func _roam_point() -> Vector3:
	## `aNPC_think_wander_move_next`: a rim point on the circle around the *current*
	## acre centre — never the goal acre (goal is reached by `_tick_acre_travel`).
	var bg: Array = _villager._bg()
	if bg.size() == 2:
		return VillagerWalk.wander_in_block(
			bg[0] as WorldData, _villager._wander_block, _villager.global_position, null, bg[1] as WorldGrid
		)
	if _villager.brain.goal_stand != Vector3.INF and _villager.brain.goal_stand != Vector3.ZERO:
		return _villager.brain.goal_stand + _villager._motor.random_offset()
	return _villager._motor.home + _villager._motor.random_offset()


func tick_acre_travel(delta: float) -> void:
	## `ac_set_npc_manager`: a culled walker steps one acre at a time toward its
	## `goal_block`, skips acres already holding 3+ villagers, and once it arrives
	## lingers before `mNpcW` hands it a fresh goal. The visible actor does the same
	## walk for real — one path-checked hop per acre at the walk row — so it never
	## straight-lines across town through a house or off a cliff.
	var here: Vector2i = _villager._current_block()
	if here != _villager._wander_block and VillagerWalk.is_fg_block(here):
		## Crossed into a new acre — re-centre the wander circle, re-plan at once.
		_villager._wander_block = here
		_villager._motor.arrive()
		_villager._travel_stand = Vector3.INF
		_villager.brain.travel_beat = VillagerBrain.TRAVEL_REPLAN
		_relocate_time = 0.0
	if here == _villager.brain.goal_block or not VillagerWalk.is_fg_block(_villager.brain.goal_block):
		## Arrived (`aSNMgr_check_set_arrive`): linger, then `mNpcW` hands a new goal.
		_villager._travel_stand = Vector3.INF
		_relocate_time = 0.0
		_villager.brain.stay_elapsed += delta
		if _villager.brain.stay_elapsed >= ActivityKind.STAY_SECONDS:
			_villager.brain.stay_elapsed = 0.0
			_villager.brain.refresh_goal()
		return
	## Relocating. Bound the whole trip: if this acre won't yield to a goal-ward hop
	## for a while, give up and let `_refresh_goal` pick a reachable goal.
	_relocate_time += delta
	if _relocate_time >= RELOCATE_GIVEUP:
		_relocate_time = 0.0
		_villager.brain.stay_elapsed = 0.0
		_villager._travel_stand = Vector3.INF
		_villager.brain.refresh_goal()
		return
	_villager.brain.travel_beat += delta
	if _villager._travel_stand != Vector3.INF and not _reached(_villager._travel_stand):
		_villager.brain.stay_elapsed = 0.0
		return
	if _villager.brain.travel_beat < VillagerBrain.TRAVEL_REPLAN:
		return
	_villager.brain.travel_beat = 0.0
	_plan_next_acre_step(here)
	_villager.brain.stay_elapsed = 0.0


func _plan_next_acre_step(here: Vector2i) -> void:
	var next: Vector2i = VillagerWalk.step_block_toward(here, _villager.brain.goal_block)
	if next == here or not VillagerWalk.is_fg_block(next):
		_villager._travel_stand = Vector3.INF
		return
	if _villagers_in_block(next) >= 3:
		## `aSNMgr_check_into_block_npc_sum` — STAY_IN_BLOCK, wander here instead.
		_villager._travel_stand = Vector3.INF
		return
	var bg: Array = _villager._bg()
	if bg.size() != 2:
		_villager._travel_stand = Vector3.INF
		return
	_villager._travel_stand = VillagerWalk.acre_entry_stand(
		bg[0] as WorldData, _villager.global_position, here, next, bg[1] as WorldGrid, ACRE_ENTRY_DEPTH
	)


func unstick_spawn() -> void:
	## `aNPC_field_schedule` leaves the house to open ground before wandering; our
	## `_yard_cell` spawn can land in a pocket at the door. Lift out of it once.
	var bg: Array = _villager._bg()
	if bg.size() != 2:
		return
	_villager._spawn_unstuck = true
	var block: Vector2i = _villager._current_block()
	var open: Vector3 = VillagerWalk.open_spawn_near(
		bg[0] as WorldData, bg[1] as WorldGrid, _villager.global_position, block
	)
	if open != _villager.global_position:
		_villager.global_position = open
		_villager._motor.reset(_villager.global_position, _villager._motor.facing)
		_villager._wander_block = _villager._current_block()


func in_wander_block() -> bool:
	var bg: Array = _villager._bg()
	if bg.size() != 2:
		return true
	return VillagerWalk.is_in_block(bg[0] as WorldData, _villager._wander_block, _villager.global_position)


func _reached(world_pos: Vector3) -> bool:
	var to: Vector3 = world_pos - _villager.global_position
	to.y = 0.0
	return to.length() <= VillagerMotor.ARRIVE + 0.2


func _villagers_in_block(block: Vector2i) -> int:
	var bg: Array = _villager._bg()
	if get_tree() == null or bg.size() != 2:
		return 0
	var grid: WorldGrid = bg[1] as WorldGrid
	var n: int = 0
	for node: Node in get_tree().get_nodes_in_group("villagers"):
		if node == _villager or not (node is Node3D) or not (node as Node3D).visible:
			continue
		if VillagerWalk.block_from_cell(grid.world_to_cell((node as Node3D).global_position)) == block:
			n += 1
	return n
