extends Node3D

## Renders the Able Sisters interior (shell + `add_needlework_set`) so Sable's
## facing / the sewing machine / mannequins can be eyeballed.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . --import
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/dev/capture_needlework.tscn
##
## Output: res://recordings/needlework/*.png

const OUT_DIR := "res://recordings/needlework"

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	Clock.paused = true
	Game.reset_session()
	get_viewport().size = Vector2i(1100, 620)
	get_tree().root.size = Vector2i(1100, 620)
	call_deferred("_run")


func _run() -> void:
	var room: Room = InteriorCatalog.room_template(&"needlework")
	var session := Interior.new()
	session.bind(room)
	var host := Node3D.new()
	add_child(host)
	var shell := GeneratedVisual.attach_interior(
		host, room.shell_ids, room.wall_id, room.floor_id,
		AABB(session.grid.origin, Vector3(32, 3, 32))
	)
	GeneratedVisual.layout_authored_interior(shell, room, session.grid, 3.0)
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	add_child(furniture)
	InteriorBuilder.new().add_needlework_set(furniture, session)
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	InteriorBuilder.new()._add_shell_collision(
		terrain, room, session.grid, InteriorBuilder.new().shell_door_gaps(room, session.grid)
	)

	## marker at the decomp enter spawn
	var spawn_pos: Vector3 = MuseumDisplay.gx_to_world(session.grid, InteriorCatalog.ABLE_SPAWN_GX)
	var marker := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.25
	cap.height = 1.4
	marker.mesh = cap
	marker.position = spawn_pos + Vector3(0, 0.8, 0)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1, 0.2, 0.2)
	marker.material_override = mm
	add_child(marker)
	print("spawn marker at ", spawn_pos)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.15, 0.18)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.2
	env.environment = e
	add_child(env)

	_camera.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await get_tree().process_frame
	await get_tree().process_frame

	var machine: Node3D = furniture.get_node_or_null("SewingMachine")
	var sable: Node3D = furniture.get_node_or_null("Sable")
	print("machine world: ", machine.global_position if machine else "nil")
	print("sable world: ", sable.global_position if sable else "nil", "  yaw: ",
		sable.rotation.y if sable else 0.0)

	var shots := [
		{"name": "entrance", "pos": Vector3(-6.0, 3.5, 6.0), "look": Vector3(-6.0, 0.3, -6.0)},
		{"name": "room_wide", "pos": Vector3(-6.0, 4.5, 2.5), "look": Vector3(-8.0, 0.5, -8.0)},
		{"name": "displays", "pos": Vector3(-4.0, 5.5, -2.0), "look": Vector3(-4.0, 0.4, -9.0)},
	]
	for shot in shots:
		_camera.position = shot["pos"]
		_camera.look_at(shot["look"])
		await _save("%s/%s.png" % [OUT_DIR, shot["name"]])
		print("  wrote ", shot["name"])
	get_tree().quit()


func _save(path: String) -> void:
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	img.save_png(path)
