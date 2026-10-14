extends NpcEventPresenter

## `artist_start`: Wendell in a random acre (`make_actor_in_free_block`, adjust 1). A new
## visit forgets who was given a wallpaper (`init_sp_artist`).


func _init() -> void:
	scene_path = "res://scenes/world/events/wendell.tscn"
	placement = "free"
	adjust = 1


func start() -> bool:
	if Game != null and Game.events != null:
		var area: Dictionary = Game.events.area(&"artist")
		var stamp: int = int(Game.events.special_dates.get("special1", 0))
		if int(area.get("stamp", -1)) != stamp:
			area.clear()
			area["stamp"] = stamp
	return super.start()
