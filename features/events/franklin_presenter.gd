extends NpcEventPresenter

## `harvestfestival_turkey_start`: Franklin in an ordinary acre (`make_actor_in_free_block_hide`).
## Needs the shrine acre, where the feast is.


func start() -> bool:
	if mgr.block_of(EventManager.BlockKind.SHRINE).x < 0:
		return false
	return super.start()
