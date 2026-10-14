extends EventPresenter

## `designer_start`: Gracie's car (`DESIGNER_CAR`, `obj_s_car`) on an empty house lot
## (`make_FG_somewhere_lot4sale`) and Gracie beside it. A new visit forgets the wash
## results and the shirts given.


func start() -> bool:
	if Game == null or Game.events == null:
		return false
	var area: Dictionary = Game.events.area(&"designer")
	var stamp: int = int(Game.events.special_dates.get("special1", 0))
	if int(area.get("stamp", -1)) != stamp:
		area.clear()
		area["stamp"] = stamp
	var cell: Vector2i = mgr.place_once(id, 0, func() -> Vector2i: return mgr.free_lot(absi(String(id).hash()) % 97))
	if cell.x < 0:
		return false
	var car: Node3D = mgr.spawn_structure(id, &"obj_s_car", cell, &"", "Car")
	var gracie: Node3D = mgr.spawn(id, "res://scenes/world/events/gracie.tscn", cell + Vector2i(1, 2), 0.0, 1)
	if gracie != null and car != null:
		gracie.set("car_position", car.global_position)
	return true
