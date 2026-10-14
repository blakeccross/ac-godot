extends NpcEventPresenter

## `downing_start`: Gulliver on a beach acre at the waves (`make_actor_in_seaside_block`),
## face-down towards the land. Not at all once his gift is given this week, nor after a
## wake-up on an earlier load of the field (`aEDZ_actor_ct`).


func _init() -> void:
	scene_path = "res://scenes/world/events/gulliver.tscn"
	placement = "seaside"
	## `set_dst_pos_proc(x, z - 10)`: he lies facing up the beach.
	yaw = PI


func start() -> bool:
	if Game != null and Game.events != null:
		if Game.events.dozaemon_completed:
			return true
		var area: Dictionary = Game.events.area(&"dozaemon")
		if bool(area.get("wakeup", false)):
			return true
	return super.start()
