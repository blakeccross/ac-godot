class_name VillagerBrain
extends Node

## Where a villager means to be: following the schedule's activity changes
## (`VillagerSchedule`, `VillagerAI`), the hints the AI picks a goal from (home, shop,
## water, a seat, the field activities) and the stand it walks to for that goal. A child of
## the `Villager`; it reads the villager's state and AI directly.

## Cross-acre relocation: re-evaluate the next acre hop this often while travelling.
const TRAVEL_REPLAN := 1.0

var goal_stand: Vector3 = Vector3.ZERO
var goal_block: Vector2i = Vector2i.ZERO
var _goal_kind: StringName = VillagerWalk.GOAL_MY_HOME
var travel_beat: float = 0.0
var stay_elapsed: float = 0.0

## The Villager this belongs to (the parent), found on first use: tests build scenes
## without adding them to the tree.
var _villager: Villager:
	get:
		if _villager == null:
			_villager = get_parent() as Villager
		return _villager


func on_action_changed(kind: StringName) -> void:
	if kind == ActivityKind.LEAVE_HOME:
		_villager._set_is_home(false)
		if not _villager.visible:
			## Appear at the door and let `_steer_ai`/`wants_move` walk the short
			## `YARD_OFFSET` leg (`aNPC_act_leave_house_out_of_door`), instead of
			## popping straight to the yard target. `reset()` re-anchors
			## `_motor.home` to whatever position is passed — snapping to the
			## unshifted `_motor.home` here (not `home + YARD_OFFSET`) also stops
			## that anchor from drifting a little further from the house every
			## time a villager leaves it.
			_villager.global_position = _villager._motor.home
			_villager._motor.reset(_villager.global_position, _villager._motor.facing)
	if kind == ActivityKind.TALK:
		_villager._motor.arrive()
	if kind == ActivityKind.WANDER:
		_villager._motor.arrive()
		stay_elapsed = 0.0
		_villager._travel_stand = Vector3.INF
		travel_beat = TRAVEL_REPLAN
		_villager._wander_block = _villager._current_block()
	if kind == ActivityKind.WAKE or kind == ActivityKind.SLEEP:
		_villager._set_is_home(true)
		if kind == ActivityKind.SLEEP and _villager.state != null:
			_villager.state.mood = VillagerState.Mood.SLEEPY
	if (
		kind == ActivityKind.GO_HOME
		or kind == ActivityKind.SLEEP
		or kind == ActivityKind.WAKE
	) and _villager.data != null:
		VillagerWalk.release(_villager.data.id)


func on_schedule_changed(previous: StringName, now: StringName) -> void:
	## `aNPC_sleep_schedule_chg_schedule`: whatever mood a villager went to sleep
	## with — SLEEPY, or anything a talk/gift left them in — clears back to
	## NORMAL the moment the schedule leaves SLEEP, whatever it heads into next
	## (`IN_HOUSE` via `WAKE`, or straight back to `FIELD` via `LEAVE_HOME`).
	## Moods aren't timed; sleep is what resets them.
	if previous == VillagerActivity.SLEEP and now != VillagerActivity.SLEEP and _villager.state != null:
		_villager.state.mood = VillagerState.Mood.NORMAL


func hints() -> Dictionary:
	if _villager.ai.current == null:
		refresh_goal()
	var field_actions: Array[StringName] = []
	if _villager.data != null:
		field_actions = _villager.data.field_activity_ids()
	return {
		"home": _villager._motor.home,
		"goal": goal_stand,
		"shop": _building_stand(&"acre_shop"),
		"water": _water_stand(),
		"sit": _furniture_stand(),
		"shop_open": Clock.in_hour_window(9, 22),
		"field_actions": field_actions,
		"outdoors": _villager.visible and not ActivityKind.hides_actor(_villager.ai.kind()),
		"is_home": _villager.state != null and _villager.state.is_home,
	}


func fish_pairs() -> Array:
	var out: Array = []
	var spawner: FishSpawner = FishSpawner.find(get_tree())
	var school: FishSchool = spawner.school() if spawner != null else null
	if school == null:
		return out
	for shadow: FishShadow in school.shadows:
		if shadow != null and not shadow.finished:
			out.append([shadow, shadow.position])
	return out


func bug_pairs() -> Array:
	var out: Array = []
	var spawner: BugSpawner = BugSpawner.find(get_tree())
	var field: BugField = spawner.field() if spawner != null else null
	if field == null:
		return out
	for bug: BugActor in field.actors:
		if bug != null:
			out.append([bug, bug.position])
	return out


func refresh_goal() -> void:
	var looks: VillagerPersonality.Looks = _villager._looks()
	var now: int = Clock.now_sec()
	var want_town: bool = VillagerWalk.can_town_walk(looks, now)
	var who: StringName = _villager.data.id if _villager.data else &""
	var claimed: bool = VillagerWalk.claim(who, want_town, _field_count())
	if not claimed:
		_goal_kind = VillagerWalk.GOAL_MY_HOME
	else:
		_goal_kind = VillagerWalk.pick_kind(looks, now)
	var bg: Array = _villager._bg()
	var world_data: WorldData = bg[0] as WorldData if bg.size() == 2 else null
	var home_block: Vector2i = VillagerWalk.block_from_cell(_home_cell())
	var shrine: Vector2i = VillagerWalk.shrine_block(world_data)
	var homes: Array[Vector2i] = VillagerWalk.house_blocks(world_data)
	var occupied: Array[Vector2i] = _occupied_blocks()
	goal_block = VillagerWalk.resolve_block(
		_goal_kind, home_block, shrine, homes, occupied
	)
	if world_data != null:
		goal_stand = VillagerWalk.stand_in_block(world_data, goal_block)
	else:
		goal_stand = _villager._motor.home


func _home_cell() -> Vector2i:
	var bg: Array = _villager._bg()
	if bg.size() != 2:
		return Vector2i.ZERO
	return (bg[1] as WorldGrid).world_to_cell(_villager._motor.home)


func _occupied_blocks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if get_tree() == null:
		return out
	for node: Node in get_tree().get_nodes_in_group("villagers"):
		if not (node is Node3D) or not (node as Node3D).visible:
			continue
		var block: Vector2i = VillagerWalk.block_from_cell(_home_cell_of(node as Node3D))
		if not out.has(block):
			out.append(block)
	return out


func _home_cell_of(node: Node3D) -> Vector2i:
	var bg: Array = _villager._bg()
	if bg.size() != 2:
		return Vector2i.ZERO
	return (bg[1] as WorldGrid).world_to_cell(node.global_position)


func _field_count() -> int:
	if get_tree() == null:
		return 1
	var n: int = 0
	for node: Node in get_tree().get_nodes_in_group("villagers"):
		if node is Villager and (node as Villager).visible:
			n += 1
	return maxi(n, 1)


func _building_stand(building_id: StringName) -> Vector3:
	var bg: Array = _villager._bg()
	if bg.size() != 2:
		return Vector3.INF
	var world_data: WorldData = bg[0] as WorldData
	var grid: WorldGrid = bg[1] as WorldGrid
	for b: BuildingPlacement in world_data.buildings:
		if b == null or b.id != building_id:
			continue
		var cell := Vector2i(b.cell.x + b.footprint.x / 2, b.cell.y + b.footprint.y)
		return grid.cell_to_world(cell)
	return Vector3.INF


func _furniture_stand() -> Vector3:
	var bg: Array = _villager._bg()
	if bg.size() != 2:
		return _villager._motor.home
	var world_data: WorldData = bg[0] as WorldData
	var grid: WorldGrid = bg[1] as WorldGrid
	for o: ObjectPlacement in world_data.objects:
		if o != null and o.kind == &"furniture":
			return grid.cell_to_world(o.cell)
	return _villager._motor.home


func _water_stand() -> Vector3:
	var bg: Array = _villager._bg()
	if bg.size() != 2:
		return Vector3.INF
	var world_data: WorldData = bg[0] as WorldData
	var grid: WorldGrid = bg[1] as WorldGrid
	var from: Vector2i = grid.world_to_cell(_villager._motor.home)
	var stand: Vector2i = VillagerPlan.nearest_water_stand(world_data, from)
	if stand == Vector2i(-1, -1):
		return Vector3.INF
	return grid.cell_to_world(stand)
