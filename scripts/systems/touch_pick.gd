class_name TouchPick
extends RefCounted

## Screen point → the ground under it, for touch. The ray from the camera meets the plane at
## `ref_y`, then is refined three times against the field's height under it
## (`FieldCollision.ground_y_at`); the camera looks down at about 45°, so that settles at once.
## Indoors (no field) the floor is the plane at `ref_y`.


## `{hit, pos}`: `pos` the ground point in world metres.
static func ground(cam: Camera3D, screen: Vector2, ref_y: float, bg: Array = []) -> Dictionary:
	if cam == null:
		return {"hit": false, "pos": Vector3.ZERO}
	var origin: Vector3 = cam.project_ray_origin(screen)
	var dir: Vector3 = cam.project_ray_normal(screen)
	if dir.y > -0.0001:
		return {"hit": false, "pos": Vector3.ZERO}
	var y: float = ref_y
	var pos := Vector3.ZERO
	for _i: int in 4:
		pos = origin + dir * ((y - origin.y) / dir.y)
		if bg.size() != 2:
			break
		var g: float = FieldCollision.ground_y_at(bg[0] as WorldData, bg[1] as WorldGrid, pos)
		if not FieldCollision.has_floor(g):
			break
		y = g
	return {"hit": true, "pos": pos}


## The flat world direction `dir` as a stick vector for `cam` (`Input.get_vector` convention):
## the inverse of `Player._camera_wish`.
static func stick_for(cam: Camera3D, dir: Vector3) -> Vector2:
	var look := Vector3.FORWARD
	var right := Vector3.RIGHT
	if cam != null:
		look = -cam.global_transform.basis.z
		right = cam.global_transform.basis.x
	look.y = 0.0
	right.y = 0.0
	if look.length_squared() < 0.0001 or right.length_squared() < 0.0001:
		return Vector2.ZERO
	look = look.normalized()
	right = right.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.000001:
		return Vector2.ZERO
	flat = flat.normalized()
	return Vector2(flat.dot(right), -flat.dot(look))
