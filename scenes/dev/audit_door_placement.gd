extends Node

## Quick door gateway placement check — no intro FSM.


func _ready() -> void:
	var car_host := Node3D.new()
	add_child(car_host)
	var car: Node3D = GeneratedVisual.attach(car_host, &"rom_train_in")
	if car != null:
		GeneratedVisual.fit_train_car_shell(car)
	var host := Node3D.new()
	add_child(host)
	var vis: Node3D = GeneratedVisual.attach(host, &"obj_romtrain_door")
	if vis == null:
		push_error("door GLB missing")
		get_tree().quit(1)
		return
	GeneratedVisual.place_train_door_at_gateway(
		host, vis, IntroTrainStage.DOOR_GATE_GX, car, IntroTrainStage.DOOR_PANEL_Z_BIAS_GX
	)
	var host_gx: Vector3 = host.global_position / FieldCatalog.GX_TO_METERS
	var panel_gx: Vector3 = GeneratedVisual.train_door_panel_center_gx(host, vis)
	var opening_z: float = 0.0
	if car != null:
		opening_z = GeneratedVisual.train_vestibule_opening_z_gx(car)
	print("door_host_gx=", host_gx)
	print("door_panel_center_gx=", panel_gx)
	print("car_opening_z_gx=", opening_z)
	print("panel_opening_delta_z=", panel_gx.z - opening_z)
	print("expected_host_nominal=", IntroTrainStage.DOOR_GATE_GX)
	var err: float = absf(panel_gx.z - (opening_z + IntroTrainStage.DOOR_PANEL_Z_BIAS_GX))
	print("fit_error_gx=", err)
	get_tree().quit(0 if err < 1.5 else 1)
