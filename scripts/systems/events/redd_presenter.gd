extends EventPresenter

## `broker_start`: Redd's tent (`BROKER_TENT`, `obj_s_yamishop`) on an empty house lot
## (`make_FG_somewhere_lot4sale`), Redd two units in front. A new visit rolls the stock
## (`init_sp_broker`, keyed to the visit's start date).


func start() -> bool:
	if Game == null or Game.events == null:
		return false
	var area: Dictionary = Game.events.area(&"broker_sale")
	var stamp: int = int(Game.events.special_dates.get("special1", 0))
	if int(area.get("stamp", -1)) != stamp or not area.has("items"):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		ReddStock.roll(area, rng)
		area["stamp"] = stamp
	var cell: Vector2i = mgr.place_once(id, 0, func() -> Vector2i: return mgr.free_lot(absi(String(id).hash()) % 97))
	if cell.x < 0:
		return false
	mgr.spawn_structure(id, &"obj_s_yamishop", cell, &"broker_shop", "Redd's Tent")
	mgr.spawn(id, "res://scenes/world/events/redd.tscn", cell + Vector2i(0, 2), 0.0, 1)
	return true
