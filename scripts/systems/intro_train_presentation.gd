class_name IntroTrainPresentation
extends RefCounted

## Train car materials and WorldEnvironment tuning for the intro scene.

const LIGHT_RAY_TUNNEL_ALPHA := 0.10
const LIGHT_RAY_DAYLIGHT_ALPHA := 0.28
const LAMP_COLOR := Color(1.0, 1.0, 0.59)
const CAR_AMBIENT := Color(140.0 / 255.0, 92.0 / 255.0, 58.0 / 255.0)
const CAR_AMBIENT_ENERGY := 0.46
const TUNNEL_AMBIENT_LIFT := Color(35.0 / 255.0, 30.0 / 255.0, 40.0 / 255.0)
const DAYLIGHT_AMBIENT_ENERGY := 0.54
const TUNNEL_BG := Color(0.05, 0.04, 0.04)
const DAYLIGHT_BG := Color(0.28, 0.22, 0.38)


static func apply_tunnel(world_env: WorldEnvironment, train_car: Node) -> void:
	if train_car != null and train_car.has_method("apply_daylight"):
		train_car.call("apply_daylight", false)
	_apply_environment(world_env, false)


static func apply_daylight(world_env: WorldEnvironment, train_car: Node) -> void:
	if train_car != null and train_car.has_method("apply_daylight"):
		train_car.call("apply_daylight", true)
	_apply_environment(world_env, true)


static func apply_car_surfaces(root: Node3D) -> void:
	if root == null:
		return
	_apply_car_opa_surfaces_inner(root)
	apply_car_glass(root, false)


static func apply_car_glass(root: Node3D, daylight: bool) -> void:
	if root == null:
		return
	_apply_car_glass_inner(root, daylight)


static func apply_window_scenery(
	root: Node3D,
	daylight: bool,
	cloud_mats: Array[StandardMaterial3D],
	tree_mats: Array[StandardMaterial3D]
) -> void:
	if root == null:
		return
	_apply_window_scenery_inner(root, daylight, cloud_mats, tree_mats)


static func _apply_environment(world_env: WorldEnvironment, daylight: bool) -> void:
	if world_env == null:
		return
	var env: Environment = world_env.environment
	if env == null:
		return
	var ambient := CAR_AMBIENT
	if not daylight:
		ambient = Color(
			minf(ambient.r + TUNNEL_AMBIENT_LIFT.r, 1.0),
			minf(ambient.g + TUNNEL_AMBIENT_LIFT.g, 1.0),
			minf(ambient.b + TUNNEL_AMBIENT_LIFT.b, 1.0)
		)
	env.ambient_light_color = ambient
	env.ambient_light_energy = DAYLIGHT_AMBIENT_ENERGY if daylight else CAR_AMBIENT_ENERGY
	env.background_color = DAYLIGHT_BG if daylight else TUNNEL_BG
	env.tonemap_exposure = 1.0
	env.glow_enabled = false


static func _apply_car_opa_surfaces_inner(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			return
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if String(mesh_instance.name).to_lower().contains("modelt"):
			return
		for i: int in mesh_instance.mesh.get_surface_count():
			var mat: Material = mesh_instance.get_active_material(i)
			var std: StandardMaterial3D
			if mat is StandardMaterial3D:
				std = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				std = StandardMaterial3D.new()
			std.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			std.disable_ambient_light = false
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			std.roughness = 1.0
			std.metallic = 0.0
			std.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			std.emission_enabled = false
			mesh_instance.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		_apply_car_opa_surfaces_inner(child)


static func _apply_car_glass_inner(node: Node, daylight: bool) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			return
		var node_label := String(mesh_instance.name).to_lower()
		if not node_label.contains("modelt"):
			return
		for i: int in mesh_instance.mesh.get_surface_count():
			var mat: Material = mesh_instance.get_active_material(i)
			if not mat is StandardMaterial3D:
				continue
			var label := _surface_label(mesh_instance, i, mat)
			var src := mat as StandardMaterial3D
			var std := src.duplicate() as StandardMaterial3D
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			if _is_light_ray_surface(label):
				_apply_light_ray_surface(std, daylight)
				mesh_instance.set_surface_override_material(i, std)
			elif _is_lamp_cone_surface(label, std):
				_apply_lamp_cone_surface(std)
				mesh_instance.set_surface_override_material(i, std)
			elif _is_train_lamp_surface(label, std):
				_apply_lamp_surface(std)
				mesh_instance.set_surface_override_material(i, std)
			elif _is_train_glass_surface(label, std):
				_apply_glass_surface(std)
				mesh_instance.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		_apply_car_glass_inner(child, daylight)


static func _apply_window_scenery_inner(
	node: Node,
	daylight: bool,
	cloud_mats: Array[StandardMaterial3D],
	tree_mats: Array[StandardMaterial3D]
) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.sorting_offset = -1.0
		if mesh_instance.mesh == null:
			return
		for i: int in mesh_instance.mesh.get_surface_count():
			var mat: Material = mesh_instance.get_active_material(i)
			if not mat is StandardMaterial3D:
				continue
			var label := _surface_label(mesh_instance, i, mat)
			var src := mat as StandardMaterial3D
			var std := src.duplicate() as StandardMaterial3D
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			std.uv1_offset = Vector3.ZERO
			if _is_window_tunnel_surface(label):
				_apply_window_opa_surface(std)
				## Tunnel walls stay for the exit scroll; dim once daylight hits.
				if daylight:
					std.albedo_color = Color(
						std.albedo_color.r * 0.35,
						std.albedo_color.g * 0.35,
						std.albedo_color.b * 0.35,
						std.albedo_color.a
					)
			elif _is_window_sky_surface(label):
				_apply_window_opa_surface(std)
			elif _is_light_ray_surface(label):
				_apply_light_ray_surface(std, daylight)
			elif _is_window_cloud_surface(label):
				_apply_xlu_scenery_surface(std)
				cloud_mats.append(std)
			elif _is_window_tree_surface(label):
				_apply_xlu_scenery_surface(std)
				tree_mats.append(std)
			else:
				_apply_xlu_scenery_surface(std)
			mesh_instance.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		_apply_window_scenery_inner(child, daylight, cloud_mats, tree_mats)


static func _is_window_tunnel_surface(label: String) -> bool:
	return "tunnel" in label


static func _is_window_sky_surface(label: String) -> bool:
	return "bgsky" in label or "sky" in label


static func _is_window_cloud_surface(label: String) -> bool:
	return "bgcloud" in label or "cloud" in label


static func _is_window_tree_surface(label: String) -> bool:
	return "bgtree" in label or ("tree" in label and "tunnel" not in label)


static func _apply_window_opa_surface(std: StandardMaterial3D) -> void:
	std.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	std.roughness = 1.0
	std.metallic = 0.0
	std.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	std.emission_enabled = false


static func _surface_label(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> String:
	var bits: PackedStringArray = PackedStringArray()
	if mat != null:
		bits.append(String(mat.resource_name).to_lower())
		if mat is StandardMaterial3D:
			var std := mat as StandardMaterial3D
			if std.albedo_texture != null:
				bits.append(std.albedo_texture.resource_path.get_file().to_lower())
	if mesh_instance.mesh is ArrayMesh:
		bits.append((mesh_instance.mesh as ArrayMesh).surface_get_name(surface).to_lower())
	bits.append(String(mesh_instance.name).to_lower())
	return " ".join(bits)


static func _is_light_ray_surface(label: String) -> bool:
	return (
		"shineglass" in label
		or "shine_glass" in label
		or "lightray" in label
		or "light_ray" in label
	)


static func _is_lamp_cone_surface(label: String, std: StandardMaterial3D) -> bool:
	if _is_light_ray_surface(label):
		return false
	return (
		"modelt" in label
		and std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		and ("light" in label or "lamp" in label)
	)


static func _is_train_lamp_surface(label: String, std: StandardMaterial3D) -> bool:
	if _is_light_ray_surface(label):
		return false
	if "light_model" in label or "lightt_model" in label or "lamp" in label:
		return true
	if "light" in label and "highlight" not in label and "flight" not in label:
		return true
	return std.emission_enabled or std.emission_energy_multiplier > 0.05


static func _is_train_glass_surface(label: String, std: StandardMaterial3D) -> bool:
	if "glass" in label:
		return true
	return std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and "modelt" in label


static func _apply_light_ray_surface(std: StandardMaterial3D, daylight: bool) -> void:
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	std.cull_mode = BaseMaterial3D.CULL_DISABLED
	std.render_priority = 1
	var alpha: float = LIGHT_RAY_DAYLIGHT_ALPHA if daylight else LIGHT_RAY_TUNNEL_ALPHA
	std.albedo_color = Color(1.0, 0.96, 0.82, alpha)
	if std.albedo_texture == null:
		std.emission_enabled = true
		std.emission = Color(1.0, 0.94, 0.76)
		std.emission_energy_multiplier = 0.35 if daylight else 0.18


static func _apply_lamp_cone_surface(std: StandardMaterial3D) -> void:
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	std.render_priority = 1
	std.albedo_color = Color(LAMP_COLOR, 0.32)
	std.emission_enabled = true
	std.emission = LAMP_COLOR
	std.emission_energy_multiplier = 0.65


static func _apply_xlu_scenery_surface(std: StandardMaterial3D) -> void:
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	std.render_priority = -1
	if std.albedo_color.a <= 0.01:
		std.albedo_color.a = 0.95


static func _apply_lamp_surface(std: StandardMaterial3D) -> void:
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	std.albedo_color = LAMP_COLOR
	std.emission_enabled = true
	std.emission = LAMP_COLOR
	std.emission_energy_multiplier = 2.4


static func _apply_glass_surface(std: StandardMaterial3D) -> void:
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	std.render_priority = 1
	std.albedo_color.a = minf(maxf(std.albedo_color.a, 0.2), 0.35)
	std.roughness = 0.05
	std.metallic = 0.0
