extends NpcEventPresenter

## `staffroll_start`: K.K. in front of the station (`make_actor_in_fixed_block_checkless`,
## the station acre, unit 7,7), facing south towards the audience.


func _init() -> void:
	scene_path = "res://scenes/world/events/kk_slider.tscn"
	placement = "fixed"
	block_kind = "station"
	unit = Vector2i(7, 7)


func pick_cell() -> Vector2i:
	var block: Vector2i = mgr.block_of("station")
	if block.x < 0:
		return Vector2i(-1, -1)
	return mgr.fixed_cell(block, unit, false)
