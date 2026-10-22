class_name TouchPick
extends RefCounted

## Screen point → the ground (or the interact volume) under it, for touch. The ray from the camera meets the plane at
## `ref_y`, then is refined three times against the field's height under it
## (`FieldCollision.ground_y_at`); the camera looks down at about 45°, so that settles at once.
## Indoors (no field) the floor is the plane at `ref_y`.

## The interact layer's bit (`InteractVolume`), and how far a pick ray reaches.
const INTERACT_LAYER := 8
const RAY_METERS := 200.0


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


## The interact volume under a screen point (`InteractVolume`s sit on layer 8), or null. A
## miss tries a ring of eight points `ring_px` round the tap and takes the hit whose host
## shows nearest the tap, so a finger slightly off a weed still gets it.
static func object(cam: Camera3D, screen: Vector2, ring_px: float = 24.0) -> InteractVolume:
	if cam == null or not cam.is_inside_tree():
		return null
	var hit: InteractVolume = _ray(cam, screen)
	if hit != null:
		return hit
	var best: InteractVolume = null
	var best_d := INF
	for i: int in 8:
		var angle: float = TAU * float(i) / 8.0
		var near: InteractVolume = _ray(cam, screen + Vector2(cos(angle), sin(angle)) * ring_px)
		if near == null or cam.is_position_behind(near.global_position):
			continue
		var d: float = cam.unproject_position(near.global_position).distance_squared_to(screen)
		if d < best_d:
			best_d = d
			best = near
	return best


static func _ray(cam: Camera3D, screen: Vector2) -> InteractVolume:
	var origin: Vector3 = cam.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + cam.project_ray_normal(screen) * RAY_METERS, INTERACT_LAYER
	)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = cam.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") as InteractVolume if not hit.is_empty() else null
