class_name VisualBlobShadow
extends RefCounted
## Authored `*_shadow_v` companion mesh under a host (flat fan kept out of actor AABB fit).


static func attach(host: Node3D, visual_id: StringName) -> void:
	## Authored `*_shadow_v` companion. Separate from GeneratedVisual so actor AABB fit
	## ignores the flat fan. Characters use `actor_blob_shadow.tscn` instead.
	if host == null or visual_id == &"":
		return
	var existing: Node = host.get_node_or_null("BlobShadow")
	if existing != null:
		existing.free()
	var paths: PackedStringArray = FieldCatalog.blob_shadow_paths(visual_id)
	if paths.is_empty():
		return
	var pivot := Node3D.new()
	pivot.name = "BlobShadow"
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
		return
	host.add_child(pivot)
	pivot.scale = Vector3.ONE * FieldCatalog.actor_uniform_scale_for(visual_id)
	## Same 2 GX bias as footprints / the actor blob so the flat decal clears the
	## acre plane (and the raised `StructureOffset` apron) without z-fighting.
	pivot.position.y = FootprintMarks.GROUND_LIFT
	_apply_blob_shadow_materials(pivot)
	VisualFit.disable_shadows(pivot)


static func _apply_blob_shadow_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var surface_count: int = (
			mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		)
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_active_material(i)
			if not mat is StandardMaterial3D:
				continue
			var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			std.roughness = 1.0
			std.metallic = 0.0
			std.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			if std.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
				std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			## Clear of grass; under window spill / footprints.
			std.render_priority = 2
			mesh_instance.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		_apply_blob_shadow_materials(child)
