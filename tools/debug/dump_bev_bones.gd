extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var root = (load("res://assets/generated/characters/bev_1.glb") as PackedScene).instantiate()
	var sk: Skeleton3D = root.get_node("Skeleton3D")
	for i in sk.get_bone_count():
		var rest = sk.get_bone_rest(i)
		var sx = rest.basis.get_scale()
		if sx.x < 0.9 or sx.y < 0.9 or sx.z < 0.9 or abs(sx.x-1)>0.01:
			print("bone ", i, " ", sk.get_bone_name(i), " scale=", sx, " origin=", rest.origin)
	print("all bone scales ok or listed above")
	# Check if mesh has blend shapes / lod
	var mi: MeshInstance3D = sk.get_node("bev_1")
	print("extra_cull_margin=", mi.extra_cull_margin)
	print("cast_shadow=", mi.cast_shadow)
	print("skin=", mi.skin)
	if mi.skin:
		print("skin binds=", mi.skin.get_bind_count())
		# IBM for bone 24
		var ibm = mi.skin.get_bind_pose(24)
		print("ibm24 origin=", ibm.origin)
		print("ibm24 basis=", ibm.basis)
	quit(0)
