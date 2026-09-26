class_name TestVillagerTextures
extends GdUnitTestSuite

## Per-villager `npc_draw_data` texture sets on shared species GLBs.


func test_villagers_wear_their_own_texture_set() -> void:
	## `npc_draw_data_tbl`: Stu draws the `bul_1` skeleton with `bul_2_tmem_txt` / `bul_2_pal`.
	var stu: VillagerData = load("res://data/villagers/stu.tres") as VillagerData
	assert_str(String(stu.texture_set)).is_equal("bul_2")
	if not VillagerTextures.has_set(stu.texture_set):
		return
	var host := Node3D.new()
	auto_free(host)
	var vis: Node3D = GeneratedVisual.attach_villager(host, stu.species, false)
	assert_that(vis).is_not_null()
	var before: Dictionary = _albedo_by_material(vis)
	assert_int(VillagerTextures.apply(vis, stu.texture_set)).is_greater(0)
	var after: Dictionary = _albedo_by_material(vis)
	assert_str(after.get("seg_0B", "")).contains("textures/bul_2/")
	assert_str(after.get("seg_0B", "")).is_not_equal(before.get("seg_0B", ""))
	## The GLB's own set (`bul_1`) has no sheets: nothing to swap.
	assert_int(VillagerTextures.apply(vis, &"bul_1")).is_equal(0)
	## Faces follow the set too.
	assert_bool(ResourceLoader.exists(NpcFace.frame_path(stu.texture_set, "eye", 0))).is_true()


func _albedo_by_material(root: Node) -> Dictionary:
	var out: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat != null and mat.albedo_texture != null:
				out[String(mat.resource_name)] = mat.albedo_texture.resource_path
	return out


func test_npc_glbs_carry_their_draw_scale() -> void:
	## `aNPC_draw_data_c.scale` is baked as a root node over the flat actor scale: cubs are
	## 0.0065 (0.65×), bulls 0.0125 (1.25×). Skip when the local GLBs are missing.
	if FieldCatalog.villager_path(&"cub").is_empty() or FieldCatalog.villager_path(&"bull").is_empty():
		return
	assert_float(_skeleton_scale(&"cub")).is_equal_approx(0.65, 1e-4)
	assert_float(_skeleton_scale(&"bull")).is_equal_approx(1.25, 1e-4)


## Skeleton scale relative to the fitted pivot.
func _skeleton_scale(species: StringName) -> float:
	var host := Node3D.new()
	auto_free(host)
	add_child(host)
	var vis: Node3D = GeneratedVisual.attach_villager(host, species)
	var skel := vis.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	return skel.global_transform.basis.get_scale().x / vis.global_transform.basis.get_scale().x
