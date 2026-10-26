class_name VillagerTextures
extends RefCounted

## A villager's own body sheets on its species GLB. Every `npc_draw_data_tbl` entry draws a
## shared species skeleton (`cKF_bs_r_bul_1`) with its own `tex_data` bank (`bul_2_tmem_txt`
## + `bul_2_pal` for Stu), and the GLB bakes only the skeleton's own set. The pipeline
## (`--kind villager-textures`) re-walks the model with each other set bound and writes the
## body images under their GLB material names (`seg_0B_300.png`); this swaps them in.
## Eyes and mouths are per-set frames too — see `NpcFace.bind(…, texture_set)`.

const DIR := "res://assets/generated/characters/villagers/textures"


static func sheet_path(texture_set: StringName, material_name: String) -> String:
	return "%s/%s/%s.png" % [DIR, texture_set, material_name]


static func has_set(texture_set: StringName) -> bool:
	return texture_set != &"" and ResourceLoader.exists(sheet_path(texture_set, "seg_0B"))


## Swaps every body material that has a sheet for `texture_set`. Returns how many surfaces
## changed; 0 when the set is the GLB's own (or was never exported).
static func apply(visual: Node, texture_set: StringName) -> int:
	if visual == null or not has_set(texture_set):
		return 0
	return _apply_node(visual, texture_set)


static func _apply_node(node: Node, texture_set: StringName) -> int:
	var changed: int = 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_instance := node as MeshInstance3D
		for i: int in mesh_instance.mesh.get_surface_count():
			var mat := mesh_instance.get_active_material(i) as StandardMaterial3D
			if mat == null or String(mat.resource_name).is_empty():
				continue
			var path := sheet_path(texture_set, String(mat.resource_name))
			if not ResourceLoader.exists(path):
				continue
			## `VisualMaterials.apply` already gave this instance its own copy; make sure.
			if mesh_instance.get_surface_override_material(i) != mat:
				mat = mat.duplicate() as StandardMaterial3D
				mesh_instance.set_surface_override_material(i, mat)
			mat.albedo_texture = load(path) as Texture2D
			changed += 1
	for child: Node in node.get_children():
		changed += _apply_node(child, texture_set)
	return changed
