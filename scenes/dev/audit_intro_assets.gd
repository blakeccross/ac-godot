extends Node

## Dump intro scene transforms for audit against decomp GX landmarks.


func _ready() -> void:
	Clock.paused = true
	Game.reset_session()
	var intro: Node3D = load("res://scenes/ui/intro_train.tscn").instantiate() as Node3D
	intro.preview_seated_daylight = true
	intro.preview_dialogue_text = "Thanks again!"
	add_child(intro)
	await get_tree().create_timer(3.0).timeout
	_print_audit(intro)
	get_tree().quit()


func _print_audit(intro: Node3D) -> void:
	print("=== INTRO ASSET AUDIT ===")
	print(
		"GX_TO_METERS=",
		FieldCatalog.GX_TO_METERS,
		" actor_scale=",
		FieldCatalog.actor_uniform_scale(),
		" acre_scale=",
		FieldCatalog.acre_uniform_scale(),
		" window_scale=",
		FieldCatalog.train_window_uniform_scale()
	)
	var rover: Node3D = intro.get_node("%Rover") as Node3D
	var sleep: Node3D = intro.get_node("%SleepPassenger") as Node3D
	var door: Node3D = intro.get_node("%TrainDoor") as Node3D
	var cam: Camera3D = intro.get_node("%IntroCamera") as Camera3D
	var lamp: OmniLight3D = intro.get_node("%CarLamp") as OmniLight3D
	var keitai: Node3D = intro.get_node("%Keitai") as Node3D
	var train: Node3D = intro.get_node("%TrainCar") as Node3D
	_print_node("rover_host", rover, IntroTrainStage.ROVER_SIT_GX)
	_print_vis("rover_vis", rover)
	_print_node("sleep_host", sleep, IntroTrainSleepNpc.SPAWN_GX)
	_print_vis("sleep_vis", sleep)
	print(
		"sleep_yaw_deg=",
		rad_to_deg(sleep.rotation.y),
		" expected=",
		rad_to_deg(IntroTrainSleepNpc.spawn_yaw())
	)
	_print_node("door_host", door, IntroTrainStage.DOOR_GATE_GX)
	var door_vis: Node3D = door.get_node_or_null("GeneratedVisual") as Node3D
	if door_vis != null:
		var panel_gx: Vector3 = GeneratedVisual.train_door_panel_center_gx(door, door_vis)
		print(
			"door_panel_center_gx=(",
			snappedf(panel_gx.x, 0.1),
			",",
			snappedf(panel_gx.y, 0.1),
			",",
			snappedf(panel_gx.z, 0.1),
			") expected=(",
			IntroTrainStage.DOOR_GATE_GX.x,
			",",
			IntroTrainStage.DOOR_GATE_GX.y,
			",",
			IntroTrainStage.DOOR_GATE_GX.z,
			")"
		)
	_print_node("cam", cam, IntroTrainStage.CAM_EYE_GX)
	print("cam_rot_deg=", cam.global_rotation_degrees)
	_print_node("lamp", lamp, Vector3(80.0, 120.0, 510.0))
	print("lamp_range_m=", lamp.omni_range)
	_print_node("keitai", keitai, Vector3.ZERO, false)
	var car_vis: Node3D = train.get_node_or_null("GeneratedVisual") as Node3D
	if car_vis != null:
		print("train_car_vis scale=", car_vis.scale, " pos=", car_vis.position)
	var win: Node3D = train.get_node_or_null("WindowScenery/GeneratedVisual") as Node3D
	if win != null:
		print("window_vis scale=", win.scale, " pos=", win.position)


func _print_node(
	label: String, node: Node3D, expected_gx: Vector3, check_yaw: bool = true
) -> void:
	var m: Vector3 = node.global_position / FieldCatalog.GX_TO_METERS
	print(
		label,
		" gx=(",
		snappedf(m.x, 0.1),
		",",
		snappedf(m.y, 0.1),
		",",
		snappedf(m.z, 0.1),
		") expected=(",
		expected_gx.x,
		",",
		expected_gx.y,
		",",
		expected_gx.z,
		")"
	)
	if check_yaw:
		print(label, "_yaw_deg=", rad_to_deg(node.rotation.y))


func _print_vis(label: String, host: Node3D) -> void:
	var vis: Node3D = host.get_node_or_null("GeneratedVisual") as Node3D
	if vis == null:
		print(label, " MISSING")
		return
	var aabb: AABB = GeneratedVisual.local_aabb(vis)
	var foot_y: float = (aabb.position.y * vis.scale.y + vis.position.y) / FieldCatalog.GX_TO_METERS
	print(
		label,
		" scale=",
		vis.scale,
		" local_pos=",
		vis.position,
		" foot_y_gx=",
		snappedf(foot_y, 0.1)
	)
