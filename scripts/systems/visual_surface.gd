class_name VisualSurface
extends RefCounted
## Read-only surface identity: label and glTF extras for a mesh surface's material.


static func surface_label(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> String:
	var bits: PackedStringArray = PackedStringArray()
	bits.append(resource_label(mat))
	if mat is StandardMaterial3D:
		bits.append(resource_label((mat as StandardMaterial3D).albedo_texture))
	if mesh_instance.mesh is ArrayMesh:
		bits.append((mesh_instance.mesh as ArrayMesh).surface_get_name(surface).to_lower())
	bits.append(String(mesh_instance.name).to_lower())
	return " ".join(bits)


static func resource_label(res: Resource) -> String:
	if res == null:
		return ""
	return "%s %s" % [String(res.resource_name), res.resource_path.get_file()]


static func gltf_extras(mat: Material) -> Dictionary:
	if mat == null:
		return {}
	for key: String in ["extras", "gltf_extras"]:
		if mat.has_meta(key):
			var extras: Variant = mat.get_meta(key)
			if extras is Dictionary:
				return extras as Dictionary
	return {}
