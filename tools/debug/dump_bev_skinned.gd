extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var root := (load("res://assets/generated/characters/bev_1.glb") as PackedScene).instantiate()
	# Must be in tree for global transforms
	get_root().add_child(root)
	await process_frame
	await process_frame
	var sk: Skeleton3D = root.get_node("Skeleton3D")
	var mi: MeshInstance3D = sk.get_node("bev_1")
	sk.reset_bone_poses()
	# Force skeleton update
	for i in 3:
		await process_frame

	print("skeleton global=", sk.global_transform.origin)
	print("mesh global=", mi.global_transform.origin)
	print("bone24 global pose origin=", sk.get_bone_global_pose(24).origin)

	# Compute skinned AABB for surfaces 10 (face) and 11 (eyes) and 1 (shell)
	var skin: Skin = mi.skin
	for si in [1, 10, 11]:
		var arrs = mi.mesh.surface_get_arrays(si)
		var pos: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrs[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrs[Mesh.ARRAY_WEIGHTS]
		var mn := Vector3(INF, INF, INF)
		var mx := Vector3(-INF, -INF, -INF)
		for vi in pos.size():
			var p := pos[vi]
			var skinned := Vector3.ZERO
			for k in 4:
				var w := weights[vi * 4 + k]
				if w == 0.0:
					continue
				var bi := bones[vi * 4 + k]
				var bind := skin.get_bind_pose(bi)  # IBM
				var bone_global := sk.global_transform * sk.get_bone_global_pose(bi)
				skinned += w * (bone_global * (bind * p))
			mn = mn.min(skinned)
			mx = mx.max(skinned)
		var mat = mi.mesh.surface_get_material(si)
		print("surf", si, " ", mat.resource_name if mat else "?", " skinned aabb=", mn, "..", mx)
		# also unskinned
		var umn := Vector3(INF, INF, INF)
		var umx := Vector3(-INF, -INF, -INF)
		for p in pos:
			umn = umn.min(p)
			umx = umx.max(p)
		print("  bind aabb=", umn, "..", umx)

	# Render screenshot via SubViewport
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	get_root().add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	var light := DirectionalLight3D.new()
	vp.add_child(light)
	light.rotation_degrees = Vector3(-40, 30, 0)
	# Move character under viewport world - actually need to reparent or duplicate
	# Simpler: put camera in main scene
	var main_cam := Camera3D.new()
	get_root().add_child(main_cam)
	main_cam.current = true
	var center := Vector3(0, 3.6, 0)
	main_cam.look_at_from_position(center + Vector3(0, 0.1, 4.5), center, Vector3.UP)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.45, 0.48)
	env.environment = e
	get_root().add_child(env)
	var dl := DirectionalLight3D.new()
	dl.rotation_degrees = Vector3(-45, 35, 0)
	get_root().add_child(dl)

	for i in 10:
		await process_frame

	var img := get_root().get_texture().get_image() if false else null
	# Use viewport of main window - headless may have dummy
	var tex := get_root().get_viewport().get_texture()
	if tex:
		img = tex.get_image()
	if img:
		var path := OS.get_user_data_dir().path_join("bev_godot_skin.png")
		img.save_png(path)
		print("WROTE ", path, " ", img.get_width(), "x", img.get_height())
	else:
		print("NO IMAGE")
	quit(0)
