extends Node

## Measure kab bench alignment vs rom_train_in seat geometry.


func _ready() -> void:
	var host := Node3D.new()
	add_child(host)
	var car_host := Node3D.new()
	add_child(car_host)
	var car: Node3D = GeneratedVisual.attach(car_host, &"rom_train_in")
	if car != null:
		GeneratedVisual.fit_train_car_shell(car)
	var kab_host := Node3D.new()
	add_child(kab_host)
	kab_host.global_position = IntroTrainStage.gx_to_meters(IntroTrainSleepNpc.SPAWN_GX)
	kab_host.rotation.y = IntroTrainSleepNpc.spawn_yaw()
	var vis: Node3D = GeneratedVisual.attach_villager(kab_host, &"kab", false)
	if vis != null:
		GeneratedVisual.apply_actor_scale(vis)
		var anim: AnimationPlayer = GeneratedVisual.find_animation_player(kab_host)
		if anim != null:
			var clip: String = IntroTrainStage.resolve_rover_clip(anim, IntroTrainSleepNpc.ANIM_KOKKURI_D1)
			if not clip.is_empty():
				anim.play(clip)
				anim.advance(0.0)
		GeneratedVisual.align_actor_world_min_to_height_gx(vis, IntroTrainSleepNpc.BENCH_FLOOR_Y_GX)
		print("after_align vis_y_gx=", vis.global_position.y / FieldCatalog.GX_TO_METERS)
		var aabb := _world_aabb(vis)
		print(
			"kab_aabb_y_gx=",
			aabb.position.y / FieldCatalog.GX_TO_METERS,
			" to ",
			(aabb.position.y + aabb.size.y) / FieldCatalog.GX_TO_METERS
		)
	if car != null:
		var seat := GeneratedVisual.local_aabb(car)
		print("car_full_aabb local=", seat)
		var seat_world := _world_aabb(car)
		print(
			"car_world_y_gx=",
			seat_world.position.y / FieldCatalog.GX_TO_METERS,
			" to ",
			(seat_world.position.y + seat_world.size.y) / FieldCatalog.GX_TO_METERS
		)
		var spawn := IntroTrainSleepNpc.SPAWN_GX
		var top_y := _seat_top_near(car, spawn.x, spawn.z)
		print("seat_top_near_spawn_gx=", top_y)
	get_tree().quit()


func _seat_top_near(car: Node3D, gx_x: float, gx_z: float) -> float:
	var target := Vector3(gx_x, 0.0, gx_z) * FieldCatalog.GX_TO_METERS
	var best_y := -INF
	_scan_seat(car, car.global_transform, target, best_y)
	return best_y / FieldCatalog.GX_TO_METERS if best_y > -INF else -1.0


func _scan_seat(node: Node, xf: Transform3D, target: Vector3, best_y: float) -> float:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and String(mi.name).to_lower().contains("seat"):
			var arrays: Array = mi.mesh.surface_get_arrays(0)
			if arrays.size() > Mesh.ARRAY_VERTEX:
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v: Vector3 in verts:
					var w: Vector3 = xf * v
					var dx: float = w.x - target.x
					var dz: float = w.z - target.z
					if dx * dx + dz * dz < 6.0 and w.y > best_y:
						best_y = w.y
	for child: Node in node.get_children():
		if child is Node3D:
			best_y = _scan_seat(child, xf * (child as Node3D).transform, target, best_y)
	return best_y


func _world_aabb(root: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect(root, root.global_transform, boxes)
	var merged := AABB()
	for box: AABB in boxes:
		if merged.size == Vector3.ZERO:
			merged = box
		else:
			merged = merged.merge(box)
	return merged


func _collect(node: Node, xf: Transform3D, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			boxes.append(xf * mi.mesh.get_aabb())
	for child: Node in node.get_children():
		if child is Node3D:
			_collect(child, xf * (child as Node3D).transform, boxes)
