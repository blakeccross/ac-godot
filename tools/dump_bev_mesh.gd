extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := "res://assets/generated/characters/bev_1.glb"
	print("exists=", ResourceLoader.exists(path))
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("load failed")
		quit(1)
		return
	var root: Node = packed.instantiate()
	print("root=", root.name, " class=", root.get_class())
	_walk(root, 0)
	quit(0)

func _walk(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	print(pad, n.name, " [", n.get_class(), "]")
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			print(pad, "  surface_count=", mi.mesh.get_surface_count())
			print(pad, "  aabb=", mi.mesh.get_aabb())
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i)
				var active := mi.get_active_material(i)
				print(pad, "  surf", i, " mat=", mat, " active=", active)
				if active is StandardMaterial3D:
					var s := active as StandardMaterial3D
					print(pad, "    cull=", s.cull_mode, " transp=", s.transparency,
						" albedo_tex=", s.albedo_texture, " albedo_color=", s.albedo_color,
						" ds_hint name=", s.resource_name)
	for c in n.get_children():
		_walk(c, depth + 1)
