class_name TestIntroTrainPresentation
extends GdUnitTestSuite


func before_test() -> void:
	IntroTrainPresentation.sun_percent = 0.0
	IntroTrainPresentation._sun_target = 0.0


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
	var lift_gone: Color = world.environment.ambient_light_color
	assert_float(lift_gone.r).is_equal_approx(IntroTrainPresentation.CAR_AMBIENT.r, 0.02)
	world.queue_free()


func test_tunnel_ambient_includes_lift() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	add_child(world)
	IntroTrainPresentation.apply_tunnel(world, null)
	var ambient: Color = world.environment.ambient_light_color
	assert_float(ambient.r).is_greater(IntroTrainPresentation.CAR_AMBIENT.r)
	world.queue_free()


func test_car_glass_forced_translucent() -> void:
	## Converted `rom_train_glass_tex` is OPAQUE RGB; presentation must force XLU.
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
	mesh.surface_set_material(0, mat)
	mi.mesh = mesh
	add_child(mi)
	IntroTrainPresentation.apply_car_surfaces(mi)
	var out: StandardMaterial3D = mi.get_active_material(0) as StandardMaterial3D
	assert_that(out).is_not_null()
	assert_int(out.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_float(out.albedo_color.a).is_less(0.95)
	mi.queue_free()


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
	var clouds: Array[StandardMaterial3D] = []
	var trees: Array[StandardMaterial3D] = []
	IntroTrainPresentation.apply_window_scenery(mi, false, clouds, trees)
	assert_int(clouds.size()).is_equal(1)
	var out: StandardMaterial3D = clouds[0]
	assert_int(out.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_that(out.vertex_color_use_as_albedo).is_false()
	var out_img: Image = out.albedo_texture.get_image()
	assert_float(out_img.get_pixel(0, 0).a).is_less(0.05)
	assert_float(out_img.get_pixel(1, 1).a).is_greater(0.9)
	mi.queue_free()
