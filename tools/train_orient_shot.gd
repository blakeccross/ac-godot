extends SceneTree

const OUT := "res://.tmp_kk_debug/train_fix"

func _init() -> void:
	# Autoloads available when project loads
	pass

func _initialize() -> void:
	call_deferred("go")

func go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var root3 := Node3D.new()
	root.add_child(root3)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.72, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.85)
	world.environment = env
	root3.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.3
	root3.add_child(sun)
	# track hint
	var track := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(20, 0.05, 0.8)
	track.mesh = box
	track.position = Vector3(0, 0, 0)
	root3.add_child(track)

	var cases: Array = [
		{"id": &"obj_train1_1", "yaw": 0.0, "tag": "loco_yaw0"},
		{"id": &"obj_train1_1", "yaw": PI * 0.5, "tag": "loco_yaw90"},
		{"id": &"obj_train1_1", "yaw": 0.0, "vis_roll": -PI * 0.5, "tag": "loco_vis_roll-90"},
		{"id": &"obj_train1_1", "yaw": 0.0, "vis_pitch": -PI * 0.5, "tag": "loco_vis_pitch-90"},
		{"id": &"obj_train1_3", "yaw": PI * 0.5, "tag": "cab_yaw90"},
		{"id": &"obj_train1_3", "yaw": 0.0, "tag": "cab_yaw0"},
		{"id": &"obj_train1_2", "yaw": 0.0, "tag": "mid_yaw0"},
		{"id": &"obj_train1_1", "yaw": 0.0, "noskin": false, "tag": "loco_WITH_skin"},
	]
	for c in cases:
		await _one(root3, c)
	print("DONE")
	quit()

func _one(root3: Node3D, c: Dictionary) -> void:
	for child in root3.get_children():
		if String(child.name).begins_with("Car") or child is Camera3D:
			child.queue_free()
	await process_frame

	var host := Node3D.new()
	host.name = "Car"
	root3.add_child(host)
	var pivot: Node3D
	if c.get("noskin", true) == false:
		# raw instance without prepare
		pivot = Node3D.new()
		pivot.name = "GeneratedVisual"
		var packed: PackedScene = load("res://assets/generated/environment/%s.glb" % String(c["id"]))
		pivot.add_child(packed.instantiate())
		host.add_child(pivot)
		GeneratedVisual.apply_actor_scale(pivot, c["id"])
	else:
		pivot = GeneratedVisual.attach(host, c["id"])
	if pivot == null:
		print("FAIL attach ", c["tag"])
		return
	pivot.rotation = Vector3(float(c.get("vis_pitch", 0.0)), 0.0, float(c.get("vis_roll", 0.0)))
	host.rotation = Vector3(0.0, float(c["yaw"]), 0.0)

	var mis = pivot.find_children("*", "MeshInstance3D", true, false)
	var mi: MeshInstance3D = mis[0] if not mis.is_empty() else null
	if mi:
		print(c["tag"], " skin=", mi.skin != null, " aabb=", mi.get_aabb().size)

	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.current = true
	root3.add_child(cam)
	cam.global_position = Vector3(8, 6, 12)
	cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)

	DisplayServer.window_set_size(Vector2i(960, 540))
	for i in 5:
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT, c["tag"]]
	img.save_png(ProjectSettings.globalize_path(path))
	print("wrote ", path)
