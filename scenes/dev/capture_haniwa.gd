extends Node3D

## Builds a real generated town (seed 4242) through `WorldBuilder` and screenshots each house
## plot's gyroid (`player_haniwa`, `player_haniwa_1`–`3`) beside its house and mailbox, from
## the actual placed node positions. The .tscn's ambient (`ambient_light_source = 2`, color
## `(0.31, 0.31, 0.59)`) intentionally mirrors `scenes/world/world.tscn`'s real
## WorldEnvironment — keep this in sync with world.tscn.
##
## The camera angle mirrors `scenes/world/follow_camera.gd`'s `DEFAULT_OFFSET` (north of
## the target, looking south, 45° down).
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/dev/capture_haniwa.tscn
##
## Output: `res://recordings/haniwa/*.png`

const OUT_DIR := "res://recordings/haniwa"
const SEED := 4242
const ISO := 0.70710678

const PAIRS: Array[Dictionary] = [
	{ "name": "plot0", "house": &"player_house", "mailbox": &"player_haniwa" },
	{ "name": "plot1", "house": &"player_house_1", "mailbox": &"player_haniwa_1" },
	{ "name": "plot2", "house": &"player_house_2", "mailbox": &"player_haniwa_2" },
]

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	Clock.paused = true
	Clock.month = 6
	Game.reset_session()
	get_viewport().size = Vector2i(960, 540)
	get_tree().root.size = Vector2i(960, 540)
	call_deferred("_run")


func _shell() -> Node3D:
	var world := Node3D.new()
	world.name = "World"
	for n: String in ["Terrain", "Objects", "Buildings", "Characters"]:
		var child := Node3D.new()
		child.name = n
		world.add_child(child)
	add_child(world)
	return world


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	print("=== HANIWA CAPTURE (real WorldBuilder) ===")
	_camera.current = true
	var world := _shell()
	var data: WorldData = WorldGenerator.generate(SEED)
	var grid := WorldGrid.new()
	WorldBuilder.new().build(world, data, grid)
	await get_tree().process_frame
	await get_tree().process_frame

	for pair: Dictionary in PAIRS:
		var house: Node3D = world.get_node_or_null("Buildings/%s" % String(pair["house"])) as Node3D
		var mailbox: Node3D = world.get_node_or_null("Objects/%s" % String(pair["mailbox"])) as Node3D
		if house == null or mailbox == null:
			print("MISSING for ", pair["name"], " house=", house, " mailbox=", mailbox)
			continue
		var name_: String = String(pair["name"])
		print(name_, " house_pos=", house.global_position, " mailbox_pos=", mailbox.global_position)
		var center: Vector3 = (house.global_position + mailbox.global_position) * 0.5
		center.y = mailbox.global_position.y + 1.0
		_camera.position = center + Vector3(0.0, 6.0 * ISO, 6.0 * ISO)
		_camera.look_at(center)
		await _save("%s/%s_iso.png" % [OUT_DIR, name_])
		_camera.position = center + Vector3(0.0, 12.0, 0.001)
		_camera.look_at(center, Vector3.FORWARD)
		await _save("%s/%s_top.png" % [OUT_DIR, name_])
		var close: Vector3 = mailbox.global_position + Vector3(0.0, 0.8, 0.0)
		_camera.position = close + Vector3(0.0, 1.6, 3.2)
		_camera.look_at(close)
		await _save("%s/%s_close.png" % [OUT_DIR, name_])

	print("shots in ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _save(path: String) -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		push_error("No viewport texture for %s" % path)
		return
	var img := tex.get_image()
	if img == null:
		push_error("No image for %s" % path)
		return
	var err := img.save_png(path)
	if err != OK:
		push_error("save_png failed (%s): %s" % [err, path])
	print("  wrote ", path)
