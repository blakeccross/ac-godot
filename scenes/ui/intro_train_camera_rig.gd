class_name IntroTrainCameraRig
extends Node3D

## Scene-owned intro camera landmarks and rig host.

@onready var camera: Camera3D = %IntroCamera


func eye_gx() -> Vector3:
	var marker: Marker3D = get_node_or_null("SeatedEye") as Marker3D
	if marker != null:
		return marker.global_position / FieldCatalog.GX_TO_METERS
	return IntroTrainStage.CAM_EYE_GX


func look_gx() -> Vector3:
	var marker: Marker3D = get_node_or_null("SeatedLook") as Marker3D
	if marker != null:
		return marker.global_position / FieldCatalog.GX_TO_METERS
	return IntroTrainStage.CAM_LOOK_GX
