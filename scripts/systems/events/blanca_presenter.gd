extends NpcEventPresenter

## `mEv_EVENT_MASK_NPC`: Blanca in a random acre (`make_actor_in_free_block`) while her face
## lasts (`MaskCat.check_birth`).


func _init() -> void:
	scene_path = "res://scenes/world/events/blanca.tscn"
	placement = "free"
	adjust = 1
