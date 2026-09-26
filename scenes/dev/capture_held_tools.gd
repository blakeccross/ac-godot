extends Node3D

## How the player carries each tool in the real field: equip it, shoot standing, then shoot
## mid-walk. Close camera to the player's front-right.
##
##   $GODOT_BIN --path . res://scenes/dev/capture_held_tools.tscn
##
## Output: `res://recordings/held_tools/*.png`

const OUT_DIR := "res://recordings/held_tools"
const TOOLS: Array[StringName] = [&"axe", &"shovel", &"net", &"fishing_rod", &"berry_umbrella"]


func _ready() -> void:
	get_viewport().size = Vector2i(640, 480)
	get_tree().root.size = Vector2i(640, 480)
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	Clock.paused = true
	Clock.hour = 12
	Game.world_mode = WorldData.Mode.GENERATED
	Game.world_seed = 4242
	add_child(load("res://scenes/world/world.tscn").instantiate())
	for _i in 30:
		await get_tree().process_frame
	var player := Player.find(get_tree())
	var cam := Camera3D.new()
	add_child(cam)
	for tool: StringName in TOOLS:
		Game.inventory.clear()
		Game.inventory.add(ItemCatalog.get_item(tool), 1)
		Game.inventory.equip_slot(0)
		player.set_facing(0.0)
		await get_tree().create_timer(1.6).timeout
		cam.current = true
		var at: Vector3 = player.global_position
		cam.global_position = at + Vector3(-2.2, 1.6, 2.6)
		cam.look_at(at + Vector3(0.0, 0.8, 0.0))
		await _shot("%s_idle" % tool)
		player.begin_demo_walk(at + Vector3(8.0, 0.0, 0.0), 3.0, 0.1)
		await get_tree().create_timer(0.7).timeout
		var at2: Vector3 = player.global_position
		cam.global_position = at2 + Vector3(2.4, 1.6, 2.4)
		cam.look_at(at2 + Vector3(0.0, 0.8, 0.0))
		await _shot("%s_walk" % tool)
		player.end_demo_walk()
		await get_tree().create_timer(0.8).timeout
		player.global_position = at
	get_tree().quit()


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [OUT_DIR, tag])
