extends NpcEventPresenter

## `turnipbuyer_start`: Joan in a random acre (`make_actor_in_free_block`, adjust 1).


func _init() -> void:
	scene_path = "res://scenes/world/events/joan.tscn"
	placement = "free"
	adjust = 1
