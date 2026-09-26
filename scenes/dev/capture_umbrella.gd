extends Node3D

## Live umbrella check in the real field, raining: equip one from the pockets (take-out +
## open), stand, walk, twirl, put away. Prints the rain loop id at each beat.
##
##   $GODOT_BIN --path . res://scenes/dev/capture_umbrella.tscn
##
## Output: `res://recordings/umbrella/*.png`

const OUT_DIR := "res://recordings/umbrella"


func _ready() -> void:
	get_viewport().size = Vector2i(960, 540)
	get_tree().root.size = Vector2i(960, 540)
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	Clock.paused = true
	Game.world_mode = WorldData.Mode.GENERATED
	Game.world_seed = 4242
	Game.weather = &"rain"
	Game.weather_intensity = int(Weather.Intensity.NORMAL)
	add_child(load("res://scenes/world/world.tscn").instantiate())
	for _i in 30:
		await get_tree().process_frame
	var player := Player.find(get_tree())
	print("UMB rain id before=", Audio.syslev_id())
	Game.inventory.add(ItemCatalog.get_item(&"berry_umbrella"), 1)
	Game.inventory.equip_slot(Game.inventory.slot_at(0).is_empty() and 1 or 0)
	for i in 6:
		await get_tree().create_timer(0.15).timeout
		await _shot("open_%d" % i)
	await get_tree().create_timer(1.0).timeout
	print("UMB open=", player.is_umbrella_open(), " rain id=", Audio.syslev_id())
	await _shot("hold_wait")
	## Walk south a little (scripted walk).
	player.begin_demo_walk(player.global_position + Vector3(6, 0, 0), 3.0, 0.1)
	await get_tree().create_timer(0.8).timeout
	await _shot("hold_walk")
	player.end_demo_walk()
	await get_tree().create_timer(1.2).timeout
	await _shot("hold_wait_east")
	## Twirl (A with nothing to interact with).
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.35).timeout
	await _shot("twirl")
	await get_tree().create_timer(1.2).timeout
	Game.inventory.unequip()
	await get_tree().create_timer(0.4).timeout
	await _shot("close")
	await get_tree().create_timer(1.5).timeout
	print("UMB after put-away open=", player.is_umbrella_open(), " rain id=", Audio.syslev_id())
	get_tree().quit()


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [OUT_DIR, tag])
