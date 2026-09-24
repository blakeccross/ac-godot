class_name VisualTrain
extends RefCounted
## Train car shell fit, door materials, door placement and the closed-door snap.


static func fit_train_car_shell(pivot: Node3D) -> void:
	## `rom_train_in` BG DLs use 16× acre verts + `Matrix_scale(0.0625)` (`ac_field_draw`).
	var s: float = FieldCatalog.acre_uniform_scale()
	pivot.scale = Vector3.ONE * s
	var aabb: AABB = VisualFit.local_aabb(pivot)
	if aabb.size.y > 0.001:
		pivot.position = Vector3(0.0, -aabb.position.y * s, 0.0)
	else:
		pivot.position = Vector3(0.0, FieldCatalog.interior_ground_y_offset(&"rom_train_in"), 0.0)


static func fit_train_window_shell(pivot: Node3D, car_pivot: Node3D = null) -> void:
	## `rom_train_out` uses raw GX verts + `Matrix_scale(0.05)` (`ac_train_window`) → world GX,
	## then `GX_TO_METERS` like actors / acre shells.
	## Decomp draws car BG and window actor at the same translate(0,0,0). Reuse the car's
	## floor snap so we do not independently raise scenery ~20 GX into the panes.
	var s: float = FieldCatalog.train_window_uniform_scale()
	pivot.scale = Vector3.ONE * s
	if car_pivot != null:
		pivot.position = Vector3(0.0, car_pivot.position.y, 0.0)
	else:
		pivot.position = Vector3.ZERO


static func apply_train_door_materials(node: Node) -> void:
	## Match `rom_train_in` OPA + glass rules so the vestibule door reads like the car shell.
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			return
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var node_label := String(mesh_instance.name).to_lower()
		for i: int in mesh_instance.mesh.get_surface_count():
			var mat: Material = mesh_instance.get_active_material(i)
			if not mat is StandardMaterial3D:
				continue
			var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			## Mesh is often `obj_romtrain_door`; glass is the surface / material name.
			var label := VisualSurface.surface_label(mesh_instance, i, mat).to_lower()
			if label.is_empty():
				label = node_label
			if "glass" in label:
				IntroTrainPresentation._apply_glass_surface(std)
			else:
				std.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				std.roughness = 1.0
				std.metallic = 0.0
				std.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				std.emission_enabled = false
				if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
					std.alpha_scissor_threshold = maxf(std.alpha_scissor_threshold, 0.5)
			mesh_instance.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		apply_train_door_materials(child)


static func place_train_door_at_gateway(
	host: Node3D,
	pivot: Node3D,
	gateway_gx: Vector3,
	car_pivot: Node3D = null,
	panel_z_bias_gx: float = 0.0
) -> void:
	## `obj_romtrain_door` is an actor — `gateway_gx` is the decomp spawn origin. When
	## `car_pivot` is set, nudge Z so the closed door frame lines up with `rom_train_in`'s
	## vestibule jambs; `panel_z_bias_gx` recesses toward the deck (negative = smaller Z).
	if host == null or pivot == null:
		return
	host.global_transform = Transform3D.IDENTITY
	host.global_position = gateway_gx * FieldCatalog.GX_TO_METERS
	if car_pivot == null:
		return
	var opening_z: float = train_vestibule_opening_z_gx(car_pivot)
	if opening_z <= 0.0:
		return
	var panel_z: float = train_door_panel_center_gx(host, pivot).z
	host.global_position.z += (opening_z + panel_z_bias_gx - panel_z) * FieldCatalog.GX_TO_METERS


static func train_vestibule_opening_z_gx(car_pivot: Node3D) -> float:
	## Mid-Z of `rom_train_in` verts in the vestibule cutout near aisle x=140.
	if car_pivot == null:
		return 0.0
	var zs: Array[float] = []
	_collect_train_vestibule_z(car_pivot, car_pivot.global_transform, zs)
	if zs.is_empty():
		return 0.0
	zs.sort()
	return zs[zs.size() / 2] / FieldCatalog.GX_TO_METERS


static func _collect_train_vestibule_z(node: Node, xf: Transform3D, zs: Array[float]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			return
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			return
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			var w: Vector3 = xf * v
			var x_gx: float = w.x / FieldCatalog.GX_TO_METERS
			if x_gx < 115.0 or x_gx > 165.0:
				continue
			var z_gx: float = w.z / FieldCatalog.GX_TO_METERS
			if z_gx < 118.0 or z_gx > 132.0:
				continue
			var y_gx: float = w.y / FieldCatalog.GX_TO_METERS
			if y_gx < 10.0 or y_gx > 75.0:
				continue
			zs.append(w.z)
	for child: Node in node.get_children():
		if child is Node3D:
			_collect_train_vestibule_z(child, xf * (child as Node3D).transform, zs)


static func train_door_panel_center_gx(host: Node3D, pivot: Node3D) -> Vector3:
	if pivot == null:
		return Vector3.ZERO
	var panel: AABB = VisualFit.world_aabb_named(pivot, "door")
	if panel.size == Vector3.ZERO:
		panel = VisualFit.world_aabb_named(pivot, "")
	if panel.size == Vector3.ZERO:
		return Vector3.ZERO
	return panel.get_center() / FieldCatalog.GX_TO_METERS


static func prepare_outdoor_train(node: Node) -> void:
	## Trains bake anim-bind (+ joint-0 rest) with `ckf_basis` — upright, long on +X.
	## Stop autoplay so wheel/door clips do not run until the stage asks; strip
	## `joint_0` tracks so those clips cannot shove the whole car off the rails.
	## Keep skinning so caboose door open can deform the door joints.
	## `*_close` frame 1 is open (clip runs open→closed); snap doors shut for approach.
	VisualAnimation.stop_autoplay_keep_rest(node)
	var anim: AnimationPlayer = VisualAnimation.find_animation_player(node)
	VisualAnimation.strip_named_joint_tracks(anim, "joint_0")
	snap_train_doors_closed(anim)


static func center_train_visual(host: Node3D, center_gx: Vector3) -> void:
	## Keep the actor origin on the decomp track point; shift only the mesh so the
	## car body sits on the rails (pipeline AABBs are off-origin).
	if host == null:
		return
	var vis: Node3D = host.get_node_or_null("GeneratedVisual") as Node3D
	if vis == null:
		return
	var s: float = vis.scale.x if vis.scale.x > 0.0 else FieldCatalog.actor_uniform_scale()
	vis.position.x = -center_gx.x * s
	vis.position.z = -center_gx.z * s


static func snap_train_doors_open(anim_player: AnimationPlayer) -> void:
	## Decomp action 5 (`mTRC_ACTION_WAIT_STOPPED`): `obj_train1_3_close` held at frame 1,
	## speed 0 — the first frame of the close clip is the open pose.
	if anim_player == null:
		return
	for name: String in ["obj_train1_3_close", "close"]:
		if not anim_player.has_animation(name):
			continue
		var animation: Animation = anim_player.get_animation(name)
		if animation != null:
			animation.loop_mode = Animation.LOOP_NONE
		anim_player.speed_scale = 1.0
		anim_player.play(name)
		anim_player.seek(0.0, true)
		anim_player.speed_scale = 0.0
		return


static func snap_train_doors_closed(anim_player: AnimationPlayer) -> void:
	## Decomp actions 0–3: `obj_train1_3_open` frozen at frame 1 (closed), speed 0.
	## Prefer open@0 over close@end — same pose, matches `aTR1_setupAction`.
	## Keep the clip "playing" at speed 0 so the seeked pose sticks (pause/stop clears it).
	if anim_player == null:
		return
	for name: String in ["obj_train1_3_open", "open"]:
		if not anim_player.has_animation(name):
			continue
		var animation: Animation = anim_player.get_animation(name)
		if animation != null:
			animation.loop_mode = Animation.LOOP_NONE
		anim_player.play(name)
		anim_player.seek(0.0, true)
		anim_player.speed_scale = 0.0
		return
	for name: String in ["obj_train1_3_close", "close"]:
		if not anim_player.has_animation(name):
			continue
		var animation: Animation = anim_player.get_animation(name)
		if animation == null:
			return
		animation.loop_mode = Animation.LOOP_NONE
		anim_player.play(name)
		anim_player.seek(animation.length, true)
		anim_player.speed_scale = 0.0
		return
