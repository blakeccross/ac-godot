class_name VillagerPlan
extends RefCounted

## Builds a queue of reusable actions from the looks schedule type.
## Field roam uses `mNpcW` goal acres (shrine / home / alone / my_home), not waypoint graphs.


static func build(
	schedule_type: StringName, previous: StringName, hints: Dictionary
) -> Array[VillagerAction]:
	var home: Vector3 = hints.get("home", Vector3.ZERO) as Vector3
	var outdoors: bool = bool(hints.get("outdoors", false))
	match schedule_type:
		VillagerActivity.SLEEP:
			return _sleep_plan(previous, outdoors, home)
		VillagerActivity.IN_HOUSE:
			return _house_plan(previous, outdoors, home)
		VillagerActivity.STAND:
			return [VillagerAction.make(ActivityKind.SIT, home, ActivityKind.SIT_SECONDS)]
		_:
			return _field_plan(previous, outdoors, hints)


static func pick_perform(hints: Dictionary) -> VillagerAction:
	var home: Vector3 = hints.get("home", Vector3.ZERO) as Vector3
	var wanted: Array[StringName] = _wanted(hints)
	var shop: Vector3 = hints.get("shop", Vector3.INF) as Vector3
	var water: Vector3 = hints.get("water", Vector3.INF) as Vector3
	var sit_at: Vector3 = hints.get("sit", home) as Vector3
	var shop_open: bool = bool(hints.get("shop_open", false))
	if ActivityKind.SHOP in wanted and shop_open and shop != Vector3.INF:
		return VillagerAction.make(ActivityKind.SHOP, shop, ActivityKind.SHOP_SECONDS)
	if ActivityKind.FISH in wanted and water != Vector3.INF:
		return VillagerAction.make(ActivityKind.FISH, water, ActivityKind.FISH_SECONDS)
	if ActivityKind.SIT in wanted:
		return VillagerAction.make(ActivityKind.SIT, sit_at, ActivityKind.SIT_SECONDS)
	return _wander_at(hints, home)


static func nearest_water_stand(data: WorldData, from: Vector2i, radius: int = 18) -> Vector2i:
	if data == null:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_d: int = 1_000_000
	for z: int in range(from.y - radius, from.y + radius + 1):
		for x: int in range(from.x - radius, from.x + radius + 1):
			var cell := Vector2i(x, z)
			if not data.is_in_bounds(cell):
				continue
			if data.terrain_at(cell) != WorldGrid.Terrain.WATER:
				continue
			var dist: int = absi(cell.x - from.x) + absi(cell.y - from.y)
			if dist < best_d:
				best = cell
				best_d = dist
	if best == Vector2i(-1, -1):
		return best
	var neighbors: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)
	]
	for off: Vector2i in neighbors:
		var stand: Vector2i = best + off
		if data.is_in_bounds(stand) and data.terrain_at(stand) != WorldGrid.Terrain.WATER:
			return stand
	return best


static func _field_plan(
	previous: StringName, outdoors: bool, hints: Dictionary
) -> Array[VillagerAction]:
	var home: Vector3 = hints.get("home", Vector3.ZERO) as Vector3
	var goal: Vector3 = _goal_of(hints, home)
	var leaving: bool = (
		not outdoors
		or previous == &""
		or previous == VillagerActivity.SLEEP
		or previous == VillagerActivity.IN_HOUSE
	)
	var out: Array[VillagerAction] = []
	if leaving:
		out.append(VillagerAction.make(ActivityKind.LEAVE_HOME, home + ActivityKind.YARD_OFFSET))
		var perform: VillagerAction = pick_perform(hints)
		if perform.kind != ActivityKind.WANDER:
			out.append(VillagerAction.make(ActivityKind.WALK_TO, perform.target))
			out.append(perform)
			out.append(VillagerAction.make(ActivityKind.TALK, perform.target, ActivityKind.TALK_SECONDS))
	if goal.distance_to(home) > 0.75:
		out.append(VillagerAction.make(ActivityKind.WALK_TO, goal))
	out.append(VillagerAction.make(ActivityKind.WANDER, goal, ActivityKind.STAY_SECONDS))
	return out


static func _wander_at(hints: Dictionary, home: Vector3) -> VillagerAction:
	return VillagerAction.make(ActivityKind.WANDER, _goal_of(hints, home), ActivityKind.STAY_SECONDS)


static func _goal_of(hints: Dictionary, home: Vector3) -> Vector3:
	var goal: Vector3 = hints.get("goal", home) as Vector3
	if goal == Vector3.INF:
		return home
	return goal


static func _sleep_plan(
	previous: StringName, outdoors: bool, home: Vector3
) -> Array[VillagerAction]:
	var out: Array[VillagerAction] = []
	if outdoors and previous != &"" and VillagerActivity.is_present(previous):
		out.append(VillagerAction.make(ActivityKind.GO_HOME, home))
	out.append(VillagerAction.make(ActivityKind.SLEEP, home))
	return out


static func _house_plan(
	previous: StringName, outdoors: bool, home: Vector3
) -> Array[VillagerAction]:
	if previous == VillagerActivity.SLEEP or previous == &"" or not outdoors:
		return [VillagerAction.make(ActivityKind.WAKE, home)]
	return [VillagerAction.make(ActivityKind.GO_HOME, home)]


static func _wanted(hints: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var raw: Variant = hints.get("field_actions", [])
	if typeof(raw) == TYPE_ARRAY:
		for entry: Variant in raw:
			out.append(StringName(str(entry)))
	if out.is_empty():
		out.append(ActivityKind.WANDER)
	return out
