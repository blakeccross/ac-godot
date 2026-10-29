extends NpcEventPresenter

## `soncho_start` (a free unit in the wishing-well acre, two units in from the edge),
## `sonchohalloween_start` (the same, in the pumpkin head) and `sonchowandar_start`
## (a random acre) for the holidays Tortimer attends on his own, and his January / February
## vacations (`soncho_start`; `aES2_wait` drops him once the lighthouse job is out).

const WANDER_EVENTS: Array[StringName] = [
	&"soncho_fishing_tourney_1", &"soncho_fishing_tourney_2", &"soncho_fireworks_show",
]


func _init() -> void:
	scene_path = "res://features/events/actors/tortimer_holiday.tscn"


func start() -> bool:
	if TortimerHoliday.is_vacation(TortimerHoliday.event_index(id)) and Game != null:
		if Game.foreigner or Game.lighthouse.talk_after_check(EventDates.ordinal(Clock.year, Clock.month, Clock.day)):
			return false
	return super.start()


func pick_cell() -> Vector2i:
	if id in WANDER_EVENTS:
		return mgr.search_free_unit(id, place_seed(), 1)
	var block: Vector2i = mgr.block_of("shrine")
	if block.x < 0:
		return Vector2i(-1, -1)
	var unit: Vector2i = mgr.random_unit_in_block(block, 2)
	return EventManager.block_unit_to_cell(block, unit) if unit.x >= 0 else Vector2i(-1, -1)


func configure(node: Node3D) -> void:
	if node == null:
		return
	node.set("holiday", TortimerHoliday.event_index(id))
	if id == &"soncho_halloween":
		node.set("species", &"pkn")
