extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://assets/generated/characters/bev_1.glb") as PackedScene
	var root: Node = packed.instantiate()
	var sk: Skeleton3D = root.get_node("Skeleton3D") as Skeleton3D
	print("bone_count=", sk.get_bone_count())
	# head bone
	for i in sk.get_bone_count():
		var name := sk.get_bone_name(i)
		if "head" in name or i == 24:
			var rest := sk.get_bone_rest(i)
			var pose := sk.get_bone_pose(i)
			var glob := sk.get_bone_global_pose(i)
			print("bone ", i, " ", name)
			print("  rest origin=", rest.origin, " basis=", rest.basis)
			print("  pose origin=", pose.origin)
			print("  global origin=", glob.origin)
	# Force update and sample mesh AABB per surface if possible
	var mi: MeshInstance3D = sk.get_node("bev_1") as MeshInstance3D
	print("mesh aabb=", mi.get_aabb())
	print("global aabb=", mi.global_transform * mi.get_aabb())
	# Get surface arrays for face plate (surf 10) and eyes (11)
	for si in [1, 10, 11]:
		var arrs = mi.mesh.surface_get_arrays(si)
		var pos: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrs[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrs[Mesh.ARRAY_WEIGHTS]
		var mn := Vector3(INF, INF, INF)
		var mx := Vector3(-INF, -INF, -INF)
		for p in pos:
			mn = mn.min(p)
			mx = mx.max(p)
		print("surf", si, " mat=", mi.mesh.surface_get_material(si).resource_name if mi.mesh.surface_get_material(si) else "?",
			" nV=", pos.size(), " aabb=", mn, "..", mx)
		# skin first 3 verts manually
		for vi in mini(3, pos.size()):
			var p := pos[vi]
			var skinned := Vector3.ZERO
			for k in 4:
				var bi := bones[vi * 4 + k]
				var w := weights[vi * 4 + k]
				if w == 0.0:
					continue
				var bone_xf := sk.get_bone_global_pose(bi)
				# IBM is in skin; approximate as inverse rest chain — use Skeleton3D API
				# Godot stores pose including rest. For bind-pose mesh:
				# skinned = global_pose * inverse_rest_global * vertex — actually
				# Mesh is in bind pose; Skeleton3D applies skin internally.
				skinned += w * (bone_xf * p)  # WRONG without IBM
			print("  v", vi, " bind=", p, " bones0=", bones[vi*4], " w0=", weights[vi*4])
	quit(0)
