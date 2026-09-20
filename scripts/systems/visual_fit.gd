class_name VisualFit
extends RefCounted
## Placement and scale of an attached visual (acre, actor, decal, interior shell) plus AABB helpers.


static func apply_actor_scale(pivot: Node3D, visual_id: StringName = &"") -> void:
	## GX→meter scale without standing foot snap (sleep / sit poses).
	if pivot == null:
		return
	var s: float = FieldCatalog.actor_uniform_scale_for(visual_id)
	pivot.scale = Vector3.ONE * s


static func fit(pivot: Node3D, visual_id: StringName) -> void:
	if VisualStructureMaterials.is_light_shaft_visual(visual_id):
		## Skylight shafts are authored in acre space alongside the museum shell.
		fit_acre(pivot)
		return
	if FieldCatalog.is_acre(visual_id) or visual_id == &"obj_museum5":
		## `obj_museum5` draws with field `Matrix_scale(0.0625)` and no translate —
		## verts share the acre datum with `rom_museum5` (floor at authored Y=40 GX).
		fit_acre(pivot)
		return
	if FieldCatalog.is_ground_decal(visual_id):
		_fit_ground_decal(pivot)
		return
	fit_actor(pivot, visual_id)


static func fit_acre(pivot: Node3D) -> void:
	## Same scale and origin for every `grd_*` so neighbors share edges and the land datum.
	if pivot == null:
		return
	var s: float = FieldCatalog.acre_uniform_scale()
	pivot.scale = Vector3.ONE * s
	pivot.position = Vector3(0.0, FieldCatalog.acre_ground_y_offset(), 0.0)


static func align_actor_to_height_gx(pivot: Node3D, height_gx: float) -> void:
	## Place the model's lowest rest-pose vertex on a GX height (standing feet, etc.).
	if pivot == null:
		return
	var aabb: AABB = local_aabb(pivot)
	if aabb.size == Vector3.ZERO:
		return
	var s: float = pivot.scale.y
	pivot.position.y = height_gx * FieldCatalog.GX_TO_METERS - aabb.position.y * s


static func align_actor_world_min_to_height_gx(pivot: Node3D, height_gx: float) -> void:
	## Snap the posed world-space mesh min-Y onto a GX height. Use for clips whose rest
	## AABB spikes (sleep poses) would lift the body off the bench.
	if pivot == null:
		return
	var box: AABB = world_aabb_named(pivot, "")
	if box.size == Vector3.ZERO:
		return
	pivot.position.y += height_gx * FieldCatalog.GX_TO_METERS - box.position.y


static func local_aabb(node: Node) -> AABB:
	return _local_aabb_named(node, "")


static func fit_actor(pivot: Node3D, visual_id: StringName = &"") -> void:
	## Same GX→meter factor as acres. Authored origin is actor world pos
	## (`m_actor.c` / `aMR_UnitNumber2Position`). Only micro-ground when feet
	## sit near Y=0 — do not AABB-snap deep spikes (piano pedals at −7650 vtx).
	## `aFTR_PROFILE.scale` is 0.1 for a few items (modern chair `int_ari_isu01`).
	var s: float = FieldCatalog.actor_uniform_scale_for(visual_id)
	pivot.scale = Vector3.ONE * s
	var aabb: AABB = local_aabb(pivot)
	if aabb.size == Vector3.ZERO:
		return
	var min_y: float = aabb.position.y
	## Snap the mesh rest onto the host origin. Museum art hosts sit at
	## `aMP_DrawOneArt` Y=40 GX, so this puts the frame bottom on the hang line
	## (pipeline verts start ~10 GX above local 0).
	if min_y > -0.5 and min_y < 2.0:
		pivot.position.y = -min_y * s


static func _fit_ground_decal(pivot: Node3D) -> void:
	## Keep authored Y. AABB-snapping a coplanar fan onto the acre z-fights with grass.
	pivot.scale = Vector3.ONE * FieldCatalog.actor_uniform_scale()


static func fit_interior(pivot: Node3D, target: AABB, visual_id: StringName) -> void:
	## `room01` verts are raw GX (max Z 320 = 8 units). Place at the field origin
	## with GX→meter scale so FG cells (1,1)–(6,6) sit on the floor. Do not AABB-fit.
	## Acre-style shells (`rom_*`, `police_indoor`, `grd_post_office`) stay at acre scale
	## (40 GX = 2 m). Homes translate the floor min-corner onto the walkable rect.
	## Museum / Nook / post / police keep the 16×16 acre origin so FG ut / RSV / door GX
	## match `cell_to_world` — only Y is snapped to the floor.
	if not FieldCatalog.interior_uses_acre_verts(visual_id):
		var gx: float = FieldCatalog.interior_uniform_scale(visual_id)
		pivot.scale = Vector3.ONE * gx
		pivot.position = Vector3(
			target.position.x, FieldCatalog.interior_ground_y_offset(visual_id), target.position.z
		)
		return
	var s: float = FieldCatalog.acre_uniform_scale()
	pivot.scale = Vector3.ONE * s
	var aabb: AABB = _local_aabb_named(pivot, "floor")
	if aabb.size.x <= 0.001 or aabb.size.z <= 0.001:
		aabb = local_aabb(pivot)
	if aabb.size.x <= 0.001 or aabb.size.z <= 0.001:
		pivot.position = Vector3(0.0, FieldCatalog.interior_ground_y_offset(visual_id), 0.0)
		return
	if shell_keeps_acre_origin(visual_id):
		pivot.position = Vector3(target.position.x, -aabb.position.y * s, target.position.z)
		return
	pivot.position = Vector3(
		target.position.x - aabb.position.x * s,
		-aabb.position.y * s,
		target.position.z - aabb.position.z * s
	)


static func shell_keeps_acre_origin(visual_id: StringName) -> bool:
	var id := String(visual_id)
	return (
		id.begins_with("rom_museum")
		or id.begins_with("rom_shop")
		or id == "rom_tailor"
		or id == "police_indoor"
		or id == "grd_post_office"
	)


static func interior_keeps_acre_origin(visual_id: StringName, room: Room) -> bool:
	return room.kind == Room.Kind.MUSEUM or shell_keeps_acre_origin(visual_id)


static func disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		disable_shadows(child)


static func world_aabb_named(root: Node3D, needle: String) -> AABB:
	var boxes: Array[AABB] = []
	_collect_world_mesh_aabbs(root, needle.to_lower(), boxes)
	var merged := AABB()
	for box: AABB in boxes:
		if merged.size == Vector3.ZERO:
			merged = box
		else:
			merged = merged.merge(box)
	return merged


static func _collect_world_mesh_aabbs(node: Node, needle: String, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			if needle.is_empty() or String(node.name).to_lower().contains(needle):
				boxes.append(mi.global_transform * mi.mesh.get_aabb())
	for child: Node in node.get_children():
		if child is Node3D:
			_collect_world_mesh_aabbs(child, needle, boxes)


static func _local_aabb_named(node: Node, needle: String) -> AABB:
	## Empty needle → every mesh. Otherwise meshes under a matching name
	## (`rom_myhome2_floor`, …) or surfaces whose material contains the needle
	## (combined shells like `rom_museum1` with `*_floorA_tex`).
	return _local_aabb_named_inner(node, needle.to_lower(), needle.is_empty())


static func _local_aabb_named_inner(node: Node, needle: String, under_match: bool) -> AABB:
	var match := under_match or String(node.name).to_lower().contains(needle)
	var merged := AABB()
	var started := false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var mesh_aabb := AABB()
			if match:
				mesh_aabb = mi.mesh.get_aabb()
			elif not needle.is_empty():
				mesh_aabb = _mesh_surface_aabb_named(mi.mesh, needle)
			if mesh_aabb.size != Vector3.ZERO:
				merged = mi.transform * mesh_aabb
				started = true
	for child in node.get_children():
		var child_aabb := _local_aabb_named_inner(child, needle, match)
		if child_aabb.size == Vector3.ZERO:
			continue
		if child is Node3D:
			child_aabb = (child as Node3D).transform * child_aabb
		if started:
			merged = merged.merge(child_aabb)
		else:
			merged = child_aabb
			started = true
	return merged


static func _mesh_surface_aabb_named(mesh: Mesh, needle: String) -> AABB:
	## Surfaces whose baked material / albedo name contains `needle`.
	var merged := AABB()
	var started := false
	for i: int in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(i)
		var label := VisualSurface.resource_label(mat).to_lower()
		if mat is StandardMaterial3D:
			label += " " + VisualSurface.resource_label((mat as StandardMaterial3D).albedo_texture).to_lower()
		if not label.contains(needle):
			continue
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if typeof(verts) != TYPE_PACKED_VECTOR3_ARRAY:
			continue
		var points: PackedVector3Array = verts
		if points.is_empty():
			continue
		var surface_aabb := AABB(points[0], Vector3.ZERO)
		for p: Vector3 in points:
			surface_aabb = surface_aabb.expand(p)
		if started:
			merged = merged.merge(surface_aabb)
		else:
			merged = surface_aabb
			started = true
	return merged
