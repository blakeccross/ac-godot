extends NpcEventPresenter

## `staffroll_start`: K.K. in front of the station (`make_actor_in_fixed_block_checkless`,
## the station acre, unit 7,7), facing south towards the audience.


func pick_cell() -> Vector2i:
	var block: Vector2i = mgr.block_of(EventManager.BlockKind.STATION)
	if block.x < 0:
		return Vector2i(-1, -1)
	return mgr.fixed_cell(block, unit, false)
