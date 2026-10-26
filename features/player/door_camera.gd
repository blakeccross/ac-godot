class_name DoorCamera
extends RefCounted

## `CAMERA2_PROCESS_DOOR` helpers: frame the player's eye from 350 GX at 20.3°.


## `morph` for going in (`flags & 1`, 140 ticks); coming out snaps.
static func begin(center: Vector3, tree: SceneTree = null, morph: bool = true) -> void:
	var cam: FollowCamera = FollowCamera.find(tree)
	if cam != null:
		cam.begin_door(center, morph)


static func end(tree: SceneTree = null) -> void:
	var cam: FollowCamera = FollowCamera.find(tree)
	if cam != null:
		cam.end_door()
