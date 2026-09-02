extends Node

## Capture entrance frame while Rover plays open_d1 (door close).


func _ready() -> void:
	Clock.paused = true
	Game.reset_session()
	var intro: Node3D = load("res://scenes/ui/intro_train.tscn").instantiate() as Node3D
	add_child(intro)
	await get_tree().create_timer(0.55).timeout
	_dump(intro)
	get_tree().quit()


func _dump(intro: Node3D) -> void:
	var rover: Node3D = intro.get_node("%Rover") as Node3D
	var door: Node3D = intro.get_node("%TrainDoor") as Node3D
	var vis: Node3D = rover.get_node_or_null("GeneratedVisual") as Node3D
	print("=== ENTRANCE AUDIT t~0.55s ===")
	_print_gx("rover_host", rover.global_position)
	if vis != null:
		_print_gx("rover_vis", vis.global_position)
		var aabb := _world_aabb(vis)
		print("rover_world_aabb gx z=", aabb.position.z / FieldCatalog.GX_TO_METERS, " to ", (aabb.position.z + aabb.size.z) / FieldCatalog.GX_TO_METERS)
	_print_gx("door_host", door.global_position)
	var door_vis: Node3D = door.get_node_or_null("GeneratedVisual") as Node3D
	if door_vis != null:
		var panel_gx: Vector3 = GeneratedVisual.train_door_panel_center_gx(door, door_vis)
		print("door_panel_center_gx=", panel_gx, " expected=", IntroTrainStage.DOOR_GATE_GX)
		_print_gx("door_vis", door_vis.global_position)
		print("door_vis scale=", door_vis.scale)
		var daabb := _world_aabb(door_vis)
		print("door_world_aabb min_gx=", daabb.position / FieldCatalog.GX_TO_METERS, " max_gx=", (daabb.position + daabb.size) / FieldCatalog.GX_TO_METERS)


func _print_gx(label: String, pos: Vector3, scale: Variant = null) -> void:
	var gx: Vector3 = pos / FieldCatalog.GX_TO_METERS
	if scale != null:
		print(label, " gx=", gx, " scale=", scale)
	else:
		print(label, " gx=", gx)


func _world_aabb(root: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect_aabb(root, root.global_transform, boxes)
	var merged := AABB()
	for box: AABB in boxes:
		if merged.size == Vector3.ZERO:
			merged = box
		else:
			merged = merged.merge(box)
	return merged


func _collect_aabb(node: Node, xf: Transform3D, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			boxes.append(xf * mi.mesh.get_aabb())
	for child: Node in node.get_children():
		if child is Node3D:
			_collect_aabb(child, xf * (child as Node3D).transform, boxes)
