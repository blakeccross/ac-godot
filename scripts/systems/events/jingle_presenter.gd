extends NpcEventPresenter

## `christmas_start`: Jingle in a free acre (`make_actor_in_free_block`).


func _init() -> void:
	scene_path = "res://scenes/world/events/jingle.tscn"
	placement = "free"
