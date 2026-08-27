extends Node3D

func _ready() -> void:
	var packed: PackedScene = load("res://assets/generated/characters/bev_1.glb") as PackedScene
	var inst: Node = packed.instantiate()
	$Anchor.add_child(inst)
	# Disable animation so we see bind pose
	var ap := inst.find_child("AnimationPlayer", true, false)
	if ap:
		ap.active = false
	_frame(inst)
	# Wait a few frames then capture
	for i in 8:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out_path := "res://assets/generated/characters/_bev_preview.png"
	# user:// is more reliable for write
	out_path = OS.get_user_data_dir().path_join("bev_preview.png")
	img.save_png(out_path)
	print("WROTE ", out_path, " size=", img.get_width(), "x", img.get_height())
	get_tree().quit()

func _frame(root: Node) -> void:
	var aabb := _aabb(root)
	var cam: Camera3D = $Camera3D
	var center := aabb.get_center()
	# Aim at head center (upper half)
	center.y = aabb.position.y + aabb.size.y * 0.72
	var radius: float = maxf(aabb.size.length() * 0.35, 0.5)
	cam.look_at_from_position(center + Vector3(0.0, 0.05, radius), center, Vector3.UP)
	cam.fov = 35.0

func _aabb(n: Node) -> AABB:
	var merged := AABB()
	var started := false
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			merged = mi.global_transform * mi.mesh.get_aabb()
			started = true
	for c in n.get_children():
		var a := _aabb(c)
		if a.size != Vector3.ZERO:
			if started:
				merged = merged.merge(a)
			else:
				merged = a
				started = true
	return merged
