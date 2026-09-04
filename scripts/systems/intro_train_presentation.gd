class_name IntroTrainPresentation
extends RefCounted

## Train car materials and WorldEnvironment tuning for the intro scene.
## Lighting follows `mEnv_CalcSetLight_train` / `sunlight_flag` → `sun_percent`.

const LAMP_COLOR := Color(1.0, 1.0, 0.59)
## Authored `CarLamp` energy while `sunlight_flag` is clear (`ef_lamp_light` on).
const CAR_LAMP_ENERGY := 3.2
const CAR_AMBIENT := Color(140.0 / 255.0, 92.0 / 255.0, 58.0 / 255.0)
const CAR_AMBIENT_ENERGY := 0.46
## `mEnv_CalcSetLight_train` ambient lift while `sun_percent < 1`: (35, 30, 40).
const TUNNEL_AMBIENT_LIFT := Color(35.0 / 255.0, 30.0 / 255.0, 40.0 / 255.0)
const DAYLIGHT_AMBIENT_ENERGY := 0.54
const TUNNEL_BG := Color(0.05, 0.04, 0.04)
const DAYLIGHT_BG := Color(0.28, 0.22, 0.38)
## `rom_train_out_bgcloud_modelT` ENV (127,127,100) — RGB from combiner, not I4.
const CLOUD_ENV := Color(127.0 / 255.0, 127.0 / 255.0, 100.0 / 255.0, 1.0)
## `add_calc(&sun_percent, …, 1−√0.5, 0.1, 0.005)` once per game frame (~30 Hz).
const _SUN_FRAME_HZ := 30.0
const _SUN_FRACTION := 0.29289321881
const _SUN_MAX_STEP := 0.1
const _SUN_MIN_STEP := 0.005

## 0 in tunnel → 1 after Rover finishes sitdown (`aNGD_sitdown` sets `sunlight_flag`).
static var sun_percent: float = 0.0
static var _sun_target: float = 0.0


static func apply_tunnel(world_env: WorldEnvironment, train_car: Node) -> void:
	sun_percent = 0.0
	_sun_target = 0.0
	if train_car != null and train_car.has_method("apply_daylight"):
		train_car.call("apply_daylight", false)
	_apply_environment(world_env, sun_percent)
	_apply_car_lamp(train_car)


## Begin the tunnel→daylight ramp (`sunlight_flag = TRUE` when sitdown finishes).
static func apply_daylight(world_env: WorldEnvironment, train_car: Node) -> void:
	_sun_target = 1.0
	if train_car != null and train_car.has_method("apply_daylight"):
		train_car.call("apply_daylight", true)
	_apply_environment(world_env, sun_percent)
	_apply_car_lamp(train_car)


## Instant daylight (seated preview / capture helpers).
static func snap_daylight(world_env: WorldEnvironment, train_car: Node) -> void:
	sun_percent = 1.0
	_sun_target = 1.0
	if train_car != null and train_car.has_method("apply_daylight"):
		train_car.call("apply_daylight", true)
	_apply_environment(world_env, sun_percent)
	_apply_car_lamp(train_car)


## Advance `sun_percent` toward the target and refresh ambient. Returns true while moving.
static func tick_sunlight(delta: float, world_env: WorldEnvironment) -> bool:
	if is_equal_approx(sun_percent, _sun_target):
		return false
	var frames: float = delta * _SUN_FRAME_HZ
	frames = minf(frames, 4.0)
	for _i: int in int(ceilf(frames)):
		_step_sun_percent()
		if is_equal_approx(sun_percent, _sun_target):
			break
	_apply_environment(world_env, sun_percent)
	return not is_equal_approx(sun_percent, _sun_target)


static func _step_sun_percent() -> void:
	var diff: float = _sun_target - sun_percent
	if absf(diff) <= _SUN_MIN_STEP:
		sun_percent = _sun_target
		return
	var step: float = diff * _SUN_FRACTION
	if absf(step) > _SUN_MAX_STEP:
		step = _SUN_MAX_STEP * signf(step)
	if absf(step) < _SUN_MIN_STEP:
		sun_percent = _sun_target
	else:
		sun_percent += step


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


static func _apply_environment(world_env: WorldEnvironment, sun: float) -> void:
	if world_env == null:
		return
	var env: Environment = world_env.environment
	if env == null:
		return
	var t: float = clampf(sun, 0.0, 1.0)
	## Tunnel lift fades as `1 − sun_percent` (`mEnv_CalcSetLight_train`).
	var lift: float = 1.0 - t
	var ambient := Color(
		minf(CAR_AMBIENT.r + TUNNEL_AMBIENT_LIFT.r * lift, 1.0),
		minf(CAR_AMBIENT.g + TUNNEL_AMBIENT_LIFT.g * lift, 1.0),
		minf(CAR_AMBIENT.b + TUNNEL_AMBIENT_LIFT.b * lift, 1.0)
	)
	env.ambient_light_color = ambient
	env.ambient_light_energy = lerpf(CAR_AMBIENT_ENERGY, DAYLIGHT_AMBIENT_ENERGY, t)
	env.background_color = TUNNEL_BG.lerp(DAYLIGHT_BG, t)
	env.tonemap_exposure = 1.0
	env.glow_enabled = false


## `ef_lamp_light` / `eLL_get_light_sw_start_demo`: off as soon as `sunlight_flag` is set.
static func _apply_car_lamp(train_car: Node) -> void:
	if train_car == null:
		return
	var lamp: OmniLight3D = train_car.get_node_or_null("%CarLamp") as OmniLight3D
	if lamp == null:
		return
	lamp.light_energy = 0.0 if _sun_target >= 1.0 else CAR_LAMP_ENERGY


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
			var label := _surface_label(mesh_instance, i, mat)
			## Glass / lamp XLU live on `rom_train_in_modelT` in the decomp but often share
			## the OPA mesh in the converted GLB — leave them for `_apply_car_glass_inner`.
			if "glass" in label or "shine" in label:
				continue
			if _is_window_light_spill_surface(label):
				continue
			if "light" in label and "highlight" not in label and "flight" not in label:
				continue
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
			std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mesh_instance.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		_apply_car_opa_surfaces_inner(child)


static func _apply_car_glass_inner(node: Node, daylight: bool) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			return
		var node_label := String(mesh_instance.name).to_lower()
		var is_xlu_mesh: bool = node_label.contains("modelt")
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
			elif _is_window_light_spill_surface(label):
				_apply_window_light_spill_surface(std)
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
			elif is_xlu_mesh and std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
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
				_apply_cloud_scenery_surface(std)
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
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	std.roughness = 1.0
	std.metallic = 0.0
	std.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	std.emission_enabled = false
	## Embedded GLB textures may still carry chromakey A=0; ignore it when opaque.
	if std.albedo_color.a < 1.0:
		std.albedo_color.a = 1.0


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


## Interior `rom_train_in_modelT` second pass — soft I4 window spill (`rom_train_light_tex`).
## Not the ceiling lamp fixture; treating it as opaque makes a solid yellow cube.
static func _is_window_light_spill_surface(label: String) -> bool:
	if _is_light_ray_surface(label):
		return false
	return (
		"rom_train_light" in label
		or "light_tex" in label
		or label.ends_with("_light")
	)


static func _is_lamp_cone_surface(label: String, std: StandardMaterial3D) -> bool:
	if _is_light_ray_surface(label) or _is_window_light_spill_surface(label):
		return false
	return (
		"modelt" in label
		and std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		and ("light" in label or "lamp" in label)
	)


static func _is_train_lamp_surface(label: String, _std: StandardMaterial3D) -> bool:
	if _is_light_ray_surface(label) or _is_window_light_spill_surface(label):
		return false
	## Fixture geometry only — do not match soft `*_light_tex` spill quads.
	if "light_model" in label or "lightt_model" in label or "lamp" in label:
		return true
	return false


static func _is_train_glass_surface(label: String, std: StandardMaterial3D) -> bool:
	if "shineglass" in label or "shine_glass" in label:
		return true
	if "glass" in label:
		return true
	return std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and "modelt" in label


static func _apply_light_ray_surface(std: StandardMaterial3D, daylight: bool) -> void:
	## Outside `shineglass` sheen uses the dual glass/shine I4; keep it as XLU glass, not a lamp beam.
	_apply_glass_surface(std)
	if daylight:
		std.albedo_color.a = minf(std.albedo_color.a + 0.08, 0.55)


static func _apply_window_light_spill_surface(std: StandardMaterial3D) -> void:
	## `rom_train_in_modelT` light pass: `G_CC_BLENDPEDECALA` + ENV (255,255,120), I4 → alpha.
	## Soft circular glow on the window — must stay XLU or the quad reads as a solid cube.
	var tint := Color(1.0, 1.0, 120.0 / 255.0, 1.0)
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.render_priority = 2
	## Soft I4 — bilinear keeps the circle from stair-stepping into blocks.
	std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if std.albedo_texture != null:
		std.albedo_texture = _glass_intensity_as_alpha(std.albedo_texture)
	std.albedo_color = Color(tint.r, tint.g, tint.b, 0.9)
	std.emission_enabled = true
	std.emission = tint
	std.emission_energy_multiplier = 1.1


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


## `rom_train_out_bgcloud_modelT`: RGB = PRIM/ENV, A = I×PRIM. I4 must not stay opaque black.
static func _apply_cloud_scenery_surface(std: StandardMaterial3D) -> void:
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.render_priority = -1
	## Combiner ignores SHADE; baked vertex gray would darken the ENV tint.
	std.vertex_color_use_as_albedo = false
	if std.albedo_texture != null:
		std.albedo_texture = _glass_intensity_as_alpha(std.albedo_texture)
	std.albedo_color = CLOUD_ENV


static func _apply_lamp_surface(std: StandardMaterial3D) -> void:
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	std.albedo_color = LAMP_COLOR
	std.emission_enabled = true
	std.emission = LAMP_COLOR
	std.emission_energy_multiplier = 2.4


static func _apply_glass_surface(std: StandardMaterial3D) -> void:
	## `rom_train_in_modelT`: XLU, ENV (100,230,255), `(PRIM−ENV)×I+ENV` / `I×PRIM`.
	## Converted GLBs often bake the I4 as opaque RGB — put intensity into alpha so scenery shows through.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	std.render_priority = 1
	std.roughness = 0.08
	std.metallic = 0.0
	std.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	std.emission_enabled = false
	var tint := Color(100.0 / 255.0, 230.0 / 255.0, 255.0 / 255.0, 1.0)
	if std.albedo_texture != null:
		std.albedo_texture = _glass_intensity_as_alpha(std.albedo_texture)
	var src_a: float = std.albedo_color.a
	if src_a >= 0.95:
		## PRIM scale for `I×PRIM` — keep some body so the cyan tint reads.
		src_a = 0.55
	else:
		src_a = clampf(src_a, 0.35, 0.7)
	std.albedo_color = Color(tint.r, tint.g, tint.b, src_a)


## Rebuild an opaque I4-as-RGB glass tex so luminance drives alpha (`I×PRIM`).
static func _glass_intensity_as_alpha(tex: Texture2D) -> Texture2D:
	if tex == null:
		return tex
	var meta_key := &"intro_train_glass_alpha"
	if tex.has_meta(meta_key):
		var cached: Variant = tex.get_meta(meta_key)
		if cached is Texture2D:
			return cached as Texture2D
	var img: Image = tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	if img.is_compressed():
		var err: Error = img.decompress()
		if err != OK:
			return tex
	img.convert(Image.FORMAT_RGBA8)
	var opaque_alpha := true
	for y: int in img.get_height():
		for x: int in img.get_width():
			if img.get_pixel(x, y).a < 0.98:
				opaque_alpha = false
				break
		if not opaque_alpha:
			break
	if not opaque_alpha:
		tex.set_meta(meta_key, tex)
		return tex
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			var intensity: float = (c.r + c.g + c.b) / 3.0
			## Keep a faint RGB so ENV cyan still reads; alpha carries the I4.
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, intensity))
	var out := ImageTexture.create_from_image(img)
	tex.set_meta(meta_key, out)
	return out
