extends Node3D

## Renders every player-house floor at every size and saves PNGs for visual audit.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/dev/capture_player_house_rooms.tscn
##
## Output: `res://recordings/player_house_rooms/*.png`

const OUT_DIR := "res://recordings/player_house_rooms"
const INTERIOR := preload("res://scenes/world/interior.tscn")

## `[label, size_tier, has_basement, room_id]`
const SHOTS: Array = [
	["s_main", 0, false, &"player_main"],
	["m_main", 1, true, &"player_main"],
	["l_main", 2, true, &"player_main"],
	["ll1_main", 3, true, &"player_main"],
	["ll2_upper", 3, true, &"player_upper"],
	["basement_l", 2, true, &"player_basement"],
]


func _ready() -> void:
	Clock.paused = true
	get_viewport().size = Vector2i(960, 540)
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for shot: Array in SHOTS:
		Game.reset_session()
		Clock.apply_snapshot({"year": 2001, "month": 7, "day": 15, "hour": 12, "minute": 0})
		var house: House = Game.interiors.player_house()
		house.size_tier = int(shot[1]) as House.SizeTier
		house.next_size_tier = house.size_tier
		house.has_basement = bool(shot[2])
		Game.interiors.refresh_player_rooms()
		Game.current_room_id = shot[3] as StringName
		Game.has_interior_spawn = false
		Game.spawn_at_room_door = true
		var room: Node = INTERIOR.instantiate()
		add_child(room)
		for _i: int in 8:
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, shot[0]]))
		print("wrote ", shot[0])
		remove_child(room)
		room.free()
		await get_tree().process_frame
	Game.reset_session()
	get_tree().quit()
