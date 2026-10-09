extends NpcEventPresenter

## `mEv_EVENT_SONCHO_BRIDGE_MAKE`: Tortimer in today's river acre (`bridge_man_start` →
## `make_actor_in_select_block(…, 2)`), two units in from its edge.


func _init() -> void:
	scene_path = "res://scenes/world/events/tortimer_bridge.tscn"


func pick_cell() -> Vector2i:
	var world: World = World.find(mgr.get_tree())
	var block: Vector2i = SecondBridge.tortimer_block(world.layout if world != null else null)
	if block.x < 0:
		return Vector2i(-1, -1)
	var unit: Vector2i = mgr.random_unit_in_block(block, 2)
	return EventManager.block_unit_to_cell(block, unit) if unit.x >= 0 else Vector2i(-1, -1)
