class_name GeneratedVisual
extends RefCounted
## Loads a pipeline GLB (or baked acre scene) onto a host and hides placeholder meshes.
## Missing files are expected until `python3 tools/build_assets.py` has been run.
## Everything else — fit, materials, seasons, animation — lives in the `Visual*` classes.


static func refresh(host: Node3D, visual_id: StringName) -> Node3D:
	## Detach and re-attach so mesh remaps and season albedo swaps run again. A baked
	## acre whose scene is unchanged only needs its season-role materials re-pointed.
	if host == null or visual_id == &"":
		return null
	if _is_acre_scene_visual(visual_id):
		var acre: Acre = _find_acre(host)
		if acre != null and acre.scene_file_path == FieldCatalog.acre_scene_path(visual_id):
			acre.apply_season()
			return acre.get_parent() as Node3D
	detach(host)
	return attach(host, visual_id)


static func _find_acre(host: Node3D) -> Acre:
	var pivot: Node = host.get_node_or_null("GeneratedVisual")
	if pivot == null:
		return null
	for child: Node in pivot.get_children():
		if child is Acre:
			return child as Acre
	return null


static func detach(host: Node3D) -> void:
	if host == null:
		return
	var vis: Node = host.get_node_or_null("GeneratedVisual")
	if vis == null:
		for child in host.get_children():
			vis = child.get_node_or_null("GeneratedVisual")
			if vis != null:
				break
	if vis != null:
		## Immediate free so a same-frame re-attach (season swap) does not stack two pivots.
		vis.free()
	var blob: Node = host.get_node_or_null("BlobShadow")
	if blob != null:
		blob.free()


static func attach(host: Node3D, visual_id: StringName) -> Node3D:
	if host == null or visual_id == &"":
		return null
	if _is_acre_scene_visual(visual_id):
		return _attach_acre_scene(host, visual_id)
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual_id)
	if paths.is_empty():
		return null
	var pivot := Node3D.new()
	pivot.name = "GeneratedVisual"
	for path: String in paths:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		if inst is Node3D:
			pivot.add_child(inst)
		else:
			inst.queue_free()
	if pivot.get_child_count() == 0:
		pivot.free()
		return null
	_hide_placeholder_meshes(host)
	host.add_child(pivot)
	if String(visual_id).begins_with("obj_train1_"):
		## Stop wheel/door autoplay; strip root tracks (keep skinning for door).
		VisualTrain.prepare_outdoor_train(pivot)
	else:
		VisualAnimation.stop_autoplay(pivot)
	VisualMaterials.apply(pivot, FieldCatalog.is_ground_decal(visual_id), visual_id)
	VisualFit.fit(pivot, visual_id)
	## Swap field/tree albedos from the seasons pack (autumn grass, winter snow).
	VisualSeasons.apply(pivot)
	VisualBlobShadow.attach(host, visual_id)
	return pivot


## Field acres exist only as baked scenes; there is no GLB path for them.
static func _is_acre_scene_visual(visual_id: StringName) -> bool:
	return FieldCatalog.is_acre(visual_id) and not FieldCatalog.is_interior_shell_visual(visual_id)


## Baked acres arrive with materials, water shaders and grid already in the scene; only
## the current season's textures are applied here. Null when the pipeline has not baked it.
static func _attach_acre_scene(host: Node3D, visual_id: StringName) -> Node3D:
	var scene_path: String = FieldCatalog.acre_scene_path(visual_id)
	if scene_path.is_empty():
		push_warning("No baked acre scene for %s — run the asset pipeline (tools/build_assets.py)" % visual_id)
		return null
	var packed: PackedScene = load(scene_path) as PackedScene
	var acre: Acre = packed.instantiate() as Acre if packed != null else null
	if acre == null:
		return null
	var pivot := Node3D.new()
	pivot.name = "GeneratedVisual"
	pivot.add_child(acre)
	_hide_placeholder_meshes(host)
	host.add_child(pivot)
	acre.apply_season()
	VisualFit.fit(pivot, visual_id)
	VisualBlobShadow.attach(host, visual_id)
	return pivot


## Attach an actor model at the host origin with the decomp draw scale and **no** floor
## snap — the model's own Y is authored against the room datum (`obj_myhome_step_down`
## dips below the floor). `mirror_x` is the `Matrix_scale(-0.01, …)` the decomp uses for
## the mirrored upstairs / basement steps (`aMI_scale_x_table`).
static func attach_datum(host: Node3D, visual_id: StringName, mirror_x: bool = false) -> Node3D:
	if host == null or visual_id == &"":
		return null
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual_id)
	if paths.is_empty():
		return null
	var pivot := Node3D.new()
	pivot.name = "GeneratedVisual"
	for path: String in paths:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		if inst is Node3D:
			pivot.add_child(inst)
		else:
			inst.queue_free()
	if pivot.get_child_count() == 0:
		pivot.free()
		return null
	host.add_child(pivot)
	VisualAnimation.stop_autoplay(pivot)
	VisualMaterials.apply(pivot, false, visual_id)
	var s: float = FieldCatalog.actor_uniform_scale_for(visual_id)
	pivot.scale = Vector3(-s if mirror_x else s, s, s)
	return pivot


## Load a pipeline GLB with preview materials, but no host, ground-fit, or extra scale.
## Held tools inherit actor GX scale from the player visual they parent under.
static func instantiate_raw(visual_id: StringName) -> Node3D:
	if visual_id == &"":
		return null
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual_id)
	if paths.is_empty():
		return null
	var pivot := Node3D.new()
	pivot.name = "HeldToolMesh"
	for path: String in paths:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		if inst is Node3D:
			pivot.add_child(inst)
		else:
			inst.queue_free()
	if pivot.get_child_count() == 0:
		pivot.free()
		return null
	VisualMaterials.apply(pivot)
	return pivot


static func apply_preview_materials(node: Node) -> void:
	VisualMaterials.apply(node)


static func apply_authored_interior(pivot: Node3D) -> void:
	## Scene-tree museum / train shells: materials + no shadows. Scale/origin stay in the tscn.
	if pivot == null:
		return
	VisualMaterials.apply(pivot)
	VisualFit.disable_shadows(pivot)


static func layout_authored_interior(
	pivot: Node3D, room: Room, grid: WorldGrid, wall_height: float = 3.0
) -> void:
	## Authored GLB children under `Shell/GeneratedVisual`: materials, room textures, fit.
	## Museum wings keep editor transforms (apply materials only).
	if pivot == null or room == null or grid == null:
		return
	VisualMaterials.apply(pivot)
	VisualRoomPaint.paint_room_surfaces(pivot, room.wall_id, room.floor_id)
	VisualWindowLight.mark_shell_room_prim(pivot)
	VisualWindowLight.refresh_room_prim(pivot)
	VisualFit.disable_shadows(pivot)
	if room.kind == Room.Kind.MUSEUM:
		return
	var visual_id: StringName = &""
	if not room.shell_ids.is_empty():
		visual_id = StringName(room.shell_ids[0])
	elif pivot.get_child_count() > 0:
		visual_id = StringName(pivot.get_child(0).name)
	if visual_id == &"":
		return
	var target := (
		AABB(
			grid.origin,
			Vector3(float(grid.columns) * grid.cell_size, wall_height, float(grid.rows) * grid.cell_size)
		)
		if VisualFit.interior_keeps_acre_origin(visual_id, room)
		else _authored_shell_bounds(room, grid, wall_height)
	)
	VisualFit.fit_interior(pivot, target, visual_id)


static func _authored_shell_bounds(room: Room, grid: WorldGrid, wall_height: float) -> AABB:
	var nw: Vector3 = grid.cell_corner(room.inner_origin)
	var se: Vector3 = grid.cell_corner(room.inner_origin + room.inner_size)
	return AABB(Vector3(nw.x, 0.0, nw.z), Vector3(se.x - nw.x, wall_height, se.z - nw.z))


static func attach_villager(host: Node3D, species: StringName, fit_actor: bool = true) -> Node3D:
	## Species GLB (`squ_1`, `cat_1`, …) when the local pipeline has been run.
	if host == null or species == &"":
		return null
	var path: String = FieldCatalog.villager_path(species)
	if path.is_empty():
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	if not (inst is Node3D):
		inst.queue_free()
		return null
	var pivot := Node3D.new()
	pivot.name = "GeneratedVisual"
	pivot.add_child(inst)
	_hide_placeholder_meshes(host)
	VisualAnimation.stop_autoplay(pivot)
	host.add_child(pivot)
	VisualMaterials.apply(pivot)
	if fit_actor:
		VisualFit.fit_actor(pivot)
	return pivot


static func attach_interior(
	host: Node3D, shell_ids: PackedStringArray, wall_id: StringName, floor_id: StringName, target: AABB
) -> Node3D:
	if host == null or shell_ids.is_empty():
		return null
	var pivot := Node3D.new()
	pivot.name = "GeneratedVisual"
	for visual_id: String in shell_ids:
		var paths: PackedStringArray = FieldCatalog.mesh_paths(StringName(visual_id))
		for path: String in paths:
			var packed: PackedScene = load(path) as PackedScene
			if packed == null:
				continue
			var inst: Node = packed.instantiate()
			if inst is Node3D:
				pivot.add_child(inst)
			else:
				inst.queue_free()
	if pivot.get_child_count() == 0:
		pivot.free()
		return null
	_hide_placeholder_meshes(host)
	host.add_child(pivot)
	VisualMaterials.apply(pivot)
	VisualRoomPaint.paint_room_surfaces(pivot, wall_id, floor_id)
	VisualWindowLight.mark_shell_room_prim(pivot)
	VisualWindowLight.refresh_room_prim(pivot)
	VisualFit.fit_interior(pivot, target, StringName(shell_ids[0]))
	VisualFit.disable_shadows(pivot)
	return pivot


static func _hide_placeholder_meshes(host: Node) -> void:
	if host is MeshInstance3D:
		(host as MeshInstance3D).visible = false
	for child in host.get_children():
		if child.name == "GeneratedVisual" or child.name == "Stump":
			continue
		if child is CollisionShape3D or child is Area3D:
			continue
		_hide_placeholder_meshes(child)
