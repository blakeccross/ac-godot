extends NpcEventPresenter

## `harvestfestival_turkey_start`: Franklin in an ordinary acre (`make_actor_in_free_block_hide`).
## Needs the shrine acre, where the feast is.


func _init() -> void:
	scene_path = "res://scenes/world/events/franklin.tscn"
	placement = "free"
	adjust = 2


func start() -> bool:
	if mgr.block_of("shrine").x < 0:
		return false
	return super.start()
