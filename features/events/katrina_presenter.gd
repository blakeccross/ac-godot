extends EventPresenter

## `gypsy_start`: Katrina's fortune tent (`FORTUNE_TENT`, `ac_buggy`, `obj_s_uranai`) on an
## empty house lot (`make_FG_somewhere_lot4sale`); she is inside (`SCENE_BUGGY`).


func start() -> bool:
	var cell: Vector2i = mgr.place_once(id, 0, func() -> Vector2i: return mgr.free_lot(absi(String(id).hash()) % 97))
	if cell.x < 0:
		return false
	mgr.spawn_structure(id, &"obj_s_uranai", cell, &"buggy", "Katrina's Tent")
	return true
