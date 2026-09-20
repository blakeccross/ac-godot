extends Node3D

## Boots a generated town and photographs the FG props (community / map / tune boards, fences,
## lotus, statue) from the south so placement and scale can be audited by eye.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/dev/capture_world_props.tscn
##
## Output: `res://recordings/world_props/*.png`

const OUT_DIR := "res://recordings/world_props"
const WORLD := preload("res://scenes/world/world.tscn")
const SEED := 12345
## Node-name prefix → shot label. First match per prefix.
const TARGETS: Array = [
	["notice_board", "notice_board"],
	["map_board", "map_board"],
	["music_board", "music_board"],
	["fence_", "fence"],
	["lotus", "lotus"],
]

var _camera: Camera3D


func _ready() -> void:
	Clock.paused = true
	get_viewport().size = Vector2i(960, 540)
	call_deferred("_run")


func _run() -> void:
	Game.reset_session()
	Game.world_mode = WorldData.Mode.GENERATED
	Game.world_seed = SEED
	Game.grass_pattern = WorldGenerator.decide_grass_pattern(SEED)
	Clock.apply_snapshot({"year": 2001, "month": 7, "day": 15, "hour": 12, "minute": 0})
	var world: Node3D = WORLD.instantiate()
	add_child(world)
	for _i: int in 10:
		await get_tree().process_frame
	_camera = Camera3D.new()
	_camera.fov = 50.0
	add_child(_camera)
	_camera.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var objects: Node = world.get_node("Objects")
	for target: Array in TARGETS:
		var node: Node3D = null
		for child: Node in objects.get_children():
			if child.name.begins_with(String(target[0])) and child is Node3D:
				node = child as Node3D
				break
		if node == null:
			print("missing ", target[0])
			continue
		var focus: Vector3 = node.global_position + Vector3(0.0, 1.2, 0.0)
		_camera.global_position = focus + Vector3(0.0, 2.2, 6.5) if target[1] != "lotus" else focus + Vector3(0.0, 4.0, 3.0)
		_camera.look_at(focus)
		for _i: int in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [OUT_DIR, target[1]]
		img.save_png(path)
		print("wrote ", target[1], " at ", node.global_position, " (", node.name, ")")
	get_tree().quit()

