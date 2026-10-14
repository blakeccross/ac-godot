extends NpcEventPresenter

## `soncho_start` (a free unit in the wishing-well acre, two units in from the edge),
## `sonchohalloween_start` (the same, in the pumpkin head) and `sonchowandar_start`
## (a random acre, wandering) for the holidays Tortimer attends on his own.

const WANDER_EVENTS: Array[StringName] = [
	&"soncho_fishing_tourney_1", &"soncho_fishing_tourney_2", &"soncho_fireworks_show",
]


func _init() -> void:
	scene_path = "res://scenes/world/events/tortimer_holiday.tscn"


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
	node.set("wander", id in WANDER_EVENTS)
	if id == &"soncho_halloween":
		node.set("species", &"pkn")
