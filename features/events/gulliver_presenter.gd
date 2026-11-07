extends NpcEventPresenter

## `downing_start`: Gulliver on a beach acre at the waves (`make_actor_in_seaside_block`),
## face-down towards the land. Not at all once his gift is given this week, nor after a
## wake-up on an earlier load of the field (`aEDZ_actor_ct`). `yaw` is PI: he lies facing up
## the beach (`set_dst_pos_proc(x, z - 10)`).


func start() -> bool:
	if Game.events.dozaemon_completed:
		return true
	var area: Dictionary = Game.events.area(&"dozaemon")
	if bool(area.get("wakeup", false)):
		return true
	return super.start()
