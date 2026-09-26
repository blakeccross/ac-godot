class_name IntroTrainPresentation
extends RefCounted

## Train car materials and WorldEnvironment tuning for the intro scene.
## Lighting follows `mEnv_SetBaseLight` (`FIELD_DRAW_TYPE_TRAIN`): the outdoor
## `l_mEnv_normal_kcolor_data` palette for the current time, every RGB field scaled by
## `sun_percent`, plus the `mEnv_CalcSetLight_train` tunnel lift, the fixed car point
## light (`mEnv_GetNowRoomPointLightInfo`) and the `ef_lamp_light` down-light.

const LAMP_COLOR := Color(1.0, 1.0, 0.59)
## `mEnv_GetNowRoomPointLightInfo` TRAIN: pos (80,120,510), colour (255,255,160), power
## 1200. No light-switch index for the start demo → `point_light_percent` stays 1 all
## ride (it is *not* switched off with `sunlight_flag`).
const CAR_LAMP_ENERGY := 3.2
## `mEnv_CalcSetLight_train` ambient lift while `sun_percent < 1`: (35, 30, 40).
const TUNNEL_AMBIENT_LIFT := Color(35.0 / 255.0, 30.0 / 255.0, 40.0 / 255.0)
## `mEnv_ChangeDiffuseVctlSet` TRAIN / PLAYER_SELECT: dir (0,60,60) → sun (0, 90, 80),
## moon (0, −30, −40). Fixed — not the time-of-day arc.
const SUN_DIR := Vector3(0.0, 90.0, 80.0)
const MOON_DIR := Vector3(0.0, -30.0, -40.0)
## `ef_lamp_light`: `Light_diffuse_ct(…, 0, 0x50, 0, …)` — straight-down diffuse whose
## colour `chase_s` toward (200,200,150) while on (step 0.5·{16,16,8}) and toward 0
## while off (step 0.5·{2,2,1}). On in the tunnel; off once `sunlight_flag` is set.
const LAMP_LIGHT_DIR := Vector3(0.0, 80.0, 0.0)
const LAMP_LIGHT_ON := Vector3(200.0, 200.0, 150.0)
const LAMP_LIGHT_STEP_ON := Vector3(8.0, 8.0, 4.0)
const LAMP_LIGHT_STEP_OFF := Vector3(1.0, 1.0, 0.5)
## `add_calc(&sun_percent, …, 1−√0.5, 0.1, 0.005)` once per decomp frame (`mEnv_ChangeDiffuseLight`).
const _SUN_MAX_STEP := 0.1
const _SUN_MIN_STEP := 0.005

## 0 in tunnel → 1 after Rover finishes sitdown (`aNGD_sitdown` sets `sunlight_flag`).
static var sun_percent: float = 0.0
static var _sun_target: float = 0.0
static var _sun_steps := FrameStepper.new(DecompTime.TICK_HZ, 4.0)
## `ef_lamp_light` diffuse colour (0–255 per channel); starts black (`Light_diffuse_ct`).
static var lamp_light: Vector3 = Vector3.ZERO


static func apply_tunnel(world_env: WorldEnvironment, train_car: Node) -> void:
	sun_percent = 0.0
	_sun_target = 0.0
	_sun_steps.reset()
	lamp_light = Vector3.ZERO
	if train_car != null and train_car.has_method("apply_daylight"):
		train_car.call("apply_daylight", false)
	_apply_lighting(world_env, train_car)


## Begin the tunnel→daylight ramp (`sunlight_flag = TRUE` when sitdown finishes).
static func apply_daylight(world_env: WorldEnvironment, train_car: Node) -> void:
	_sun_target = 1.0
	if train_car != null and train_car.has_method("apply_daylight"):
		train_car.call("apply_daylight", true)
	_apply_lighting(world_env, train_car)


## Instant daylight (seated preview / capture helpers).
static func snap_daylight(world_env: WorldEnvironment, train_car: Node) -> void:
	sun_percent = 1.0
	_sun_target = 1.0
	lamp_light = Vector3.ZERO
	if train_car != null and train_car.has_method("apply_daylight"):
		train_car.call("apply_daylight", true)
	_apply_lighting(world_env, train_car)


## Per-frame kankyo update: `sun_percent` add_calc + `ef_lamp_light` chase, then relight.
## Returns true while `sun_percent` is still moving.
static func tick_sunlight(delta: float, world_env: WorldEnvironment, train_car: Node = null) -> bool:
	_sun_steps.add(delta)
	while _sun_steps.next():
		_step_sun_percent()
		_step_lamp_light()
	_apply_lighting(world_env, train_car)
	return not is_equal_approx(sun_percent, _sun_target)


static func _step_sun_percent() -> void:
	var diff: float = _sun_target - sun_percent
	if absf(diff) <= _SUN_MIN_STEP:
		sun_percent = _sun_target
		return
	var step: float = diff * MLib.HALF_FRACTION
	if absf(step) > _SUN_MAX_STEP:
		step = _SUN_MAX_STEP * signf(step)
	if absf(step) < _SUN_MIN_STEP:
		step = _SUN_MIN_STEP * signf(step)
	sun_percent += step


## `Ef_Lamp_Light_actor_move` / `eLL_get_light_sw_start_demo`: on until `sunlight_flag`.
static func _step_lamp_light() -> void:
	var on: bool = _sun_target < 1.0
	var goal: Vector3 = LAMP_LIGHT_ON if on else Vector3.ZERO
	var step: Vector3 = LAMP_LIGHT_STEP_ON if on else LAMP_LIGHT_STEP_OFF
	lamp_light = Vector3(
		move_toward(lamp_light.x, goal.x, step.x),
		move_toward(lamp_light.y, goal.y, step.y),
		move_toward(lamp_light.z, goal.z, step.z)
	)


## Decomp `BaseLight` for this frame: palette × `sun_percent` + tunnel lift.
static func current_light() -> Dictionary:
	var pal: Dictionary = Clock.outdoor_light()
	var t: float = clampf(sun_percent, 0.0, 1.0)
	var lift: float = 1.0 - t
	var amb: Color = pal["ambient"] as Color
	return {
		"ambient": Color(
			minf(amb.r * t + TUNNEL_AMBIENT_LIFT.r * lift, 1.0),
			minf(amb.g * t + TUNNEL_AMBIENT_LIFT.g * lift, 1.0),
			minf(amb.b * t + TUNNEL_AMBIENT_LIFT.b * lift, 1.0)
		),
		"sun": pal["sun"] as Color,
		## `base_light.sun_color` after `mEnv_ChangeRGBLight(…, sun_percent)`.
		"sun_scaled": Color((pal["sun"] as Color) * t, 1.0),
		"sun_energy": float(pal["sun_energy"]) * t,
		"moon": pal["moon"] as Color,
		"moon_energy": float(pal["moon_energy"]) * t,
		"bg": Color((pal["bg"] as Color) * t, 1.0),
	}


static func _apply_lighting(world_env: WorldEnvironment, train_car: Node) -> void:
	var light: Dictionary = current_light()
	_apply_environment(world_env, light)
	_apply_car_lights(train_car, light)


static func _apply_environment(world_env: WorldEnvironment, light: Dictionary) -> void:
	if world_env == null:
		return
	var env: Environment = world_env.environment
	if env == null:
		return
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = light["ambient"] as Color
	## Same RGB-as-intensity mapping as the outdoor field (`world.gd`).
	env.ambient_light_energy = 1.0
	env.background_color = light["bg"] as Color
	env.tonemap_exposure = 1.0
	env.glow_enabled = false


static func _apply_car_lights(train_car: Node, light: Dictionary) -> void:
	if train_car == null:
		return
	var lamp: OmniLight3D = train_car.get_node_or_null("%CarLamp") as OmniLight3D
	if lamp != null:
		lamp.light_energy = CAR_LAMP_ENERGY
	var sun: DirectionalLight3D = train_car.get_node_or_null("%Sun") as DirectionalLight3D
	if sun != null:
		aim_directional(sun, SUN_DIR)
		sun.light_color = light["sun"] as Color
		sun.light_energy = float(light["sun_energy"])
		sun.visible = sun.light_energy > 0.001
	var moon: DirectionalLight3D = train_car.get_node_or_null("%Moon") as DirectionalLight3D
	if moon != null:
		aim_directional(moon, MOON_DIR)
		moon.light_color = light["moon"] as Color
		moon.light_energy = float(light["moon_energy"])
		moon.visible = moon.light_energy > 0.001
	var down: DirectionalLight3D = train_car.get_node_or_null("%LampLight") as DirectionalLight3D
	if down != null:
		aim_directional(down, LAMP_LIGHT_DIR)
		var peak: float = maxf(lamp_light.x, maxf(lamp_light.y, lamp_light.z))
		if peak > 0.0:
			down.light_color = Color(lamp_light.x / peak, lamp_light.y / peak, lamp_light.z / peak)
		down.light_energy = peak / 255.0
		down.visible = peak > 0.0


## Decomp light dirs point toward the source; Godot directional lights shine along −Z.
static func aim_directional(light: DirectionalLight3D, dir: Vector3) -> void:
	if light == null or dir.length_squared() < 0.0001:
		return
	var d: Vector3 = dir.normalized()
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.95:
		up = Vector3.RIGHT
	light.basis = Basis.looking_at(-d, up)


static func apply_car_surfaces(root: Node3D) -> void:
	if root == null:
		return
	_apply_car_opa_surfaces_inner(root)
	apply_car_glass(root, false)


static func apply_car_glass(root: Node3D, daylight: bool) -> void:
	if root == null:
		return
	_apply_car_glass_inner(root, daylight)


## `rom_train_out` surfaces by draw role. Every window combiner ignores SHADE, so they are
## unshaded here; `intro_train_car.gd` drives prim tint / alpha / scroll per frame.
static func apply_window_scenery(root: Node3D) -> Dictionary:
	var roles := {
		&"sky": [] as Array[StandardMaterial3D],
		&"tunnel": [] as Array[StandardMaterial3D],
		&"cloud": [] as Array[StandardMaterial3D],
		&"tree": [] as Array[StandardMaterial3D],
		&"shine": [] as Array[ShaderMaterial],
	}
	if root != null:
		_apply_window_scenery_inner(root, roles)
	return roles


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
				_apply_shineglass_surface(std, daylight)
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


static func _apply_window_scenery_inner(node: Node, roles: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh_instance.mesh == null:
			return
		for i: int in mesh_instance.mesh.get_surface_count():
			var mat: Material = mesh_instance.get_active_material(i)
			if not mat is StandardMaterial3D:
				continue
			var role: StringName = window_role(_surface_label(mesh_instance, i, mat))
			if role == &"":
				continue
			if role == &"shine":
				var shine := shine_material((mat as StandardMaterial3D).albedo_texture)
				(roles[role] as Array).append(shine)
				mesh_instance.set_surface_override_material(i, shine)
				continue
			var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			_setup_window_surface(std, role)
			(roles[role] as Array[StandardMaterial3D]).append(std)
			mesh_instance.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		_apply_window_scenery_inner(child, roles)


static func window_role(label: String) -> StringName:
	if "tunnel" in label:
		return &"tunnel"
	if "shine" in label:
		return &"shine"
	if "bgcloud" in label or "cloud" in label:
		return &"cloud"
	if "bgtree" in label or "tree" in label:
		return &"tree"
	if "bgsky" in label or "sky" in label:
		return &"sky"
	return &""


static func _setup_window_surface(std: StandardMaterial3D, role: StringName) -> void:
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.vertex_color_use_as_albedo = false
	std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	std.cull_mode = BaseMaterial3D.CULL_DISABLED
	std.emission_enabled = false
	std.uv1_offset = Vector3.ZERO
	match role:
		&"sky":
			## `G_RM_AA_ZB_OPA_SURF2`, `TEXEL0 × PRIM`.
			std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			std.render_priority = -2
		&"tunnel":
			## `G_RM_AA_ZB_TEX_EDGE2`: alpha-tested, S clamped. The exit scroll slides the
			## tile origin 250 texels so every sample clamps to the transparent edge column.
			std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			std.alpha_scissor_threshold = 0.5
			std.texture_repeat = false
			std.render_priority = 0
		&"cloud":
			## `ZB_XLU_SURF2`; RGB = PRIM·LOD + ENV, A = I4 × PRIM.a (I4 → alpha).
			std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			std.texture_repeat = true
			std.render_priority = -1
			if std.albedo_texture != null:
				std.albedo_texture = _glass_intensity_as_alpha(std.albedo_texture)
		&"tree":
			## `ZB_XLU_SURF2`; RGB = TEXEL × (PRIM·LOD + ENV), A = TEXEL.
			std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			std.texture_repeat = true
			std.render_priority = 0


const SHINEGLASS_SHADER := preload("res://shaders/train_shineglass.gdshader")
## Tile-1 glass I4 (`rom_train_glass_tex_rgb_i4`, 16×16). The converted car glass is the
## same asset family; the dedicated `_rgb_i4` bank is not extracted separately.
const SHINEGLASS_TILE1_PATH := "res://assets/generated/textures/rel/rom_train_glass_tex.png"


static func shine_material(shine_tex: Texture2D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHINEGLASS_SHADER
	mat.render_priority = 2
	if shine_tex != null:
		mat.set_shader_parameter(&"shine_tex", _glass_intensity_as_alpha(shine_tex))
	if ResourceLoader.exists(SHINEGLASS_TILE1_PATH):
		mat.set_shader_parameter(&"glass_tex", load(SHINEGLASS_TILE1_PATH))
	mat.set_shader_parameter(&"lod_frac", 0.0)
	return mat


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


## IndoorSession `rom_train_in_modelT` second pass — soft I4 window spill (`rom_train_light_tex`).
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
	## Shineglass is outdoor sheen (`rom_train_out`), not car panes.
	if "shineglass" in label or "shine_glass" in label:
		return false
	if "glass" in label:
		return true
	return std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and "modelt" in label


## `rom_train_out_shineglass_modelT`: α *= PRIM_LOD_FRAC (`lod_factor` from time of day).
## Quads sit inside the cabin past the glass plane; without the lod gate they read as
## scenery poking through the window. Tunnel intro → lod 0; after `sunlight_flag` → soft sheen.
static func _apply_shineglass_surface(std: StandardMaterial3D, daylight: bool) -> void:
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	std.render_priority = 2
	if std.albedo_texture != null:
		std.albedo_texture = _glass_intensity_as_alpha(std.albedo_texture)
	## Day peak `lod_factor` ≈ 160 (`aTrainWindow_Actor_move`); tunnel keeps 0.
	var lod: float = (160.0 / 255.0) if daylight else 0.0
	std.albedo_color = Color(1.0, 1.0, 1.0, lod)


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


static func _apply_lamp_surface(std: StandardMaterial3D) -> void:
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.albedo_color = LAMP_COLOR
	std.emission_enabled = true
	std.emission = LAMP_COLOR
	std.emission_energy_multiplier = 2.4


static func _apply_glass_surface(std: StandardMaterial3D) -> void:
	## `rom_train_in_modelT`: XLU, ENV (100,230,255), `(PRIM−ENV)×I+ENV` / `I×PRIM`.
	## Converted GLBs often bake the I4 as opaque RGB — put intensity into alpha.
	## Color A stays 1 so only the I channel gates see-through (no forced 0.55 body).
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
	std.albedo_color = tint


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
