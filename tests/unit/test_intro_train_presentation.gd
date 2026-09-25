class_name TestIntroTrainPresentation
extends GdUnitTestSuite


func before_test() -> void:
	IntroTrainPresentation.sun_percent = 0.0
	IntroTrainPresentation._sun_target = 0.0
	IntroTrainPresentation.lamp_light = Vector3.ZERO


func test_sun_percent_ramps_after_daylight_flag() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	add_child(world)
	IntroTrainPresentation.apply_tunnel(world, null)
	assert_float(IntroTrainPresentation.sun_percent).is_equal_approx(0.0, 0.001)
	IntroTrainPresentation.apply_daylight(world, null)
	assert_float(IntroTrainPresentation.sun_percent).is_equal_approx(0.0, 0.001)
	assert_float(IntroTrainPresentation._sun_target).is_equal_approx(1.0, 0.001)
	for _i: int in 40:
		IntroTrainPresentation.tick_sunlight(1.0 / 30.0, world)
	assert_float(IntroTrainPresentation.sun_percent).is_equal_approx(1.0, 0.001)
	## Lift gone: ambient is the outdoor palette for the current time (`mEnv_SetBaseLight` TRAIN).
	var ambient: Color = world.environment.ambient_light_color
	var palette: Color = Clock.outdoor_light()["ambient"] as Color
	assert_float(ambient.r).is_equal_approx(palette.r, 0.01)
	assert_float(ambient.b).is_equal_approx(palette.b, 0.01)
	world.queue_free()


func test_tunnel_ambient_is_only_the_lift() -> void:
	## `sun_percent` 0 zeroes every palette field; `mEnv_CalcSetLight_train` adds (35,30,40).
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	add_child(world)
	IntroTrainPresentation.apply_tunnel(world, null)
	var ambient: Color = world.environment.ambient_light_color
	assert_float(ambient.r).is_equal_approx(35.0 / 255.0, 0.002)
	assert_float(ambient.g).is_equal_approx(30.0 / 255.0, 0.002)
	assert_float(ambient.b).is_equal_approx(40.0 / 255.0, 0.002)
	assert_float(world.environment.background_color.get_luminance()).is_less(0.001)
	world.queue_free()


func test_lamp_light_chases_on_then_off() -> void:
	## `ef_lamp_light`: +8/+8/+4 per frame to (200,200,150) in the tunnel, −1/−1/−0.5 after.
	IntroTrainPresentation.apply_tunnel(null, null)
	for _i: int in 10:
		IntroTrainPresentation.tick_sunlight(1.0 / 60.0, null)
	assert_float(IntroTrainPresentation.lamp_light.x).is_equal_approx(80.0, 0.01)
	## Blue steps 4/frame → reaches 150 at frame 38.
	for _i: int in 30:
		IntroTrainPresentation.tick_sunlight(1.0 / 60.0, null)
	assert_vector(IntroTrainPresentation.lamp_light).is_equal(Vector3(200.0, 200.0, 150.0))
	IntroTrainPresentation.apply_daylight(null, null)
	for _i: int in 4:
		IntroTrainPresentation.tick_sunlight(1.0 / 60.0, null)
	assert_float(IntroTrainPresentation.lamp_light.x).is_equal_approx(196.0, 0.01)
	assert_float(IntroTrainPresentation.lamp_light.z).is_equal_approx(148.0, 0.01)


func test_car_glass_forced_translucent() -> void:
	## Converted `rom_train_glass_tex` is OPAQUE RGB; presentation must promote I→alpha XLU.
	var mi := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(0, "rom_train_glass_tex")
	var mat := StandardMaterial3D.new()
	mat.resource_name = "rom_train_glass_tex"
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color = Color.WHITE
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 1.0))
	img.set_pixel(0, 0, Color(0.1, 0.1, 0.1, 1.0))
	img.set_pixel(1, 1, Color(0.9, 0.9, 0.9, 1.0))
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mesh.surface_set_material(0, mat)
	mi.mesh = mesh
	add_child(mi)
	IntroTrainPresentation.apply_car_surfaces(mi)
	var out: StandardMaterial3D = mi.get_active_material(0) as StandardMaterial3D
	assert_that(out).is_not_null()
	assert_int(out.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	## ENV cyan tint; see-through is the I channel in texture A (not a forced mid color A).
	assert_float(out.albedo_color.a).is_equal_approx(1.0, 0.001)
	var out_img: Image = out.albedo_texture.get_image()
	assert_float(out_img.get_pixel(0, 0).a).is_less(0.2)
	assert_float(out_img.get_pixel(1, 1).a).is_greater(0.8)
	mi.queue_free()


func test_window_roles_are_unshaded_and_tunnel_is_alpha_tested() -> void:
	## Every `rom_train_out` combiner ignores SHADE; the tunnel is `TEX_EDGE` + S clamp so the
	## exit scroll can slide it onto its transparent edge column.
	var root := Node3D.new()
	add_child(root)
	for surface_name: String in [
		"rom_train_tunnel_tex", "rom_train_bgsky_tex", "rom_train_bgtree_tex",
		"rom_train_bgcloud_tex_rgb_i4", "waterfall_rom_train_shine_tex_rgb_i4",
	]:
		root.add_child(_surface_mesh(surface_name))
	var roles: Dictionary = IntroTrainPresentation.apply_window_scenery(root)
	var shine: Array = roles[&"shine"]
	assert_int(shine.size()).is_equal(1)
	assert_that(shine[0] is ShaderMaterial).is_true()
	for role: StringName in [&"sky", &"tunnel", &"cloud", &"tree"]:
		assert_int((roles[role] as Array).size()).is_equal(1)
		var mat: StandardMaterial3D = (roles[role] as Array)[0]
		assert_int(mat.shading_mode).is_equal(BaseMaterial3D.SHADING_MODE_UNSHADED)
		assert_that(mat.vertex_color_use_as_albedo).is_false()
	var tunnel: StandardMaterial3D = (roles[&"tunnel"] as Array)[0]
	assert_int(tunnel.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
	assert_that(tunnel.texture_repeat).is_false()
	var sky: StandardMaterial3D = (roles[&"sky"] as Array)[0]
	assert_int(sky.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_DISABLED)
	root.queue_free()


func _surface_mesh(surface_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(0, surface_name)
	var mat := StandardMaterial3D.new()
	mat.resource_name = surface_name
	mat.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, mat)
	mi.mesh = mesh
	return mi


func test_window_light_spill_stays_translucent() -> void:
	## `rom_train_light_tex` is a soft I4 glow — opaque lamp paint made it a yellow cube.
	assert_that(
		IntroTrainPresentation._is_window_light_spill_surface("rom_train_light_tex")
	).is_true()
	assert_that(
		IntroTrainPresentation._is_train_lamp_surface("rom_train_light_tex", StandardMaterial3D.new())
	).is_false()
	var mi := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(0, "rom_train_light_tex")
	var mat := StandardMaterial3D.new()
	mat.resource_name = "rom_train_light_tex"
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color = Color.WHITE
	## Soft circle on black (I4-as-RGB).
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y: int in 8:
		for x: int in 8:
			var d: float = Vector2(x - 3.5, y - 3.5).length() / 4.0
			var v: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mesh.surface_set_material(0, mat)
	mi.mesh = mesh
	add_child(mi)
	IntroTrainPresentation.apply_car_surfaces(mi)
	var out: StandardMaterial3D = mi.get_active_material(0) as StandardMaterial3D
	assert_that(out).is_not_null()
	assert_int(out.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_int(out.depth_draw_mode).is_equal(BaseMaterial3D.DEPTH_DRAW_DISABLED)
	## Alpha channel on the spill tex should fall off (not a solid cube).
	var out_img: Image = out.albedo_texture.get_image()
	assert_that(out_img).is_not_null()
	assert_float(out_img.get_pixel(0, 0).a).is_less(0.35)
	assert_float(out_img.get_pixel(4, 4).a).is_greater(0.6)
	mi.queue_free()


func test_window_cloud_uses_i4_as_alpha() -> void:
	## Opaque I4-as-RGB black must become transparent so sky shows through.
	var mi := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(0, "rom_train_bgcloud_tex_rgb_i4")
	var mat := StandardMaterial3D.new()
	mat.resource_name = "rom_train_bgcloud_tex_rgb_i4"
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	img.set_pixel(1, 1, Color(1, 1, 1, 1))
	img.set_pixel(2, 2, Color(1, 1, 1, 1))
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mesh.surface_set_material(0, mat)
	mi.mesh = mesh
	add_child(mi)
	var clouds: Array = IntroTrainPresentation.apply_window_scenery(mi)[&"cloud"]
	assert_int(clouds.size()).is_equal(1)
	var out: StandardMaterial3D = clouds[0]
	assert_int(out.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_that(out.vertex_color_use_as_albedo).is_false()
	var out_img: Image = out.albedo_texture.get_image()
	assert_float(out_img.get_pixel(0, 0).a).is_less(0.05)
	assert_float(out_img.get_pixel(1, 1).a).is_greater(0.9)
	mi.queue_free()
