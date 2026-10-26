extends NpcEventPresenter

## `christmas_start`: Jingle in a free acre (`make_actor_in_free_block`).


func _init() -> void:
	scene_path = "res://features/events/actors/jingle.tscn"
	placement = "free"
