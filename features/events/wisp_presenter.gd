extends NpcEventPresenter

## `ghost_start`: the Wisp at a free spot somewhere in town (`make_actor_in_free_block`),
## unless his spirits are back tonight or, not yet found, the town has fewer than eight
## weeds (`aEGH_actor_ct`).


func start() -> bool:
	if not WispEvent.shows_up(WispEvent.state(), WeedUse.count()):
		return true
	return super.start()
