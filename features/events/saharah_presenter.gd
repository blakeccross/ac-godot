extends NpcEventPresenter

## `arabian_start`: Saharah in a random acre (`make_actor_in_free_block`, adjust 1). A new
## visit clears her trade count (`init_sp_arabian`).


func start() -> bool:
	var area: Dictionary = Game.events.area(&"carpet_peddler")
	var stamp: int = int(Game.events.special_dates.get("special1", 0))
	if int(area.get("stamp", -1)) != stamp:
		area.clear()
		area["stamp"] = stamp
		area["used"] = 0
	return super.start()
