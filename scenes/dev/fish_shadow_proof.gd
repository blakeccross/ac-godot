extends Node

## Renders fish shadows over a river-water sheet and proves they are not erased by it.
## Footprints already needed `render_priority` 3 above water (1–2); shadows missed that.
##
##   $GODOT_BIN --path . res://scenes/dev/fish_shadow_proof.tscn
##
## Writes PNGs under `user://fish_shadow_proof` and prints lit-pixel counts.

const SHOT_DIR := "user://fish_shadow_proof"
const SHOT_SIZE := Vector2i(480, 320)
const WATER_COLOR := Color(0.15, 0.45, 0.85, 1.0)
const RIVER_WATER := preload("res://shaders/river_water.gdshader")
const FISH_SHADOW := preload("res://shaders/fish_shadow.gdshader")


func _ready() -> void:
	await _run()
	get_tree().quit()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	print("--- fish shadow render proof ---")
	var alone: Dictionary = await _shoot("shadow_alone", false, 3)
	var over_water: Dictionary = await _shoot("shadow_over_water", true, 3)
	var under_water: Dictionary = await _shoot("shadow_under_water_priority0", true, 0)
	print(
		"alone_fish_px=%d over_water_fish_px=%d under_water_fish_px=%d"
		% [alone.fish_px, over_water.fish_px, under_water.fish_px]
	)
	print("shots in %s" % ProjectSettings.globalize_path(SHOT_DIR))
	if int(alone.fish_px) < 80:
		push_error("shadow alone drew too few fish pixels (%d)" % int(alone.fish_px))
	if int(over_water.fish_px) < 80:
		push_error("shadow over water was erased (%d fish px)" % int(over_water.fish_px))
	else:
		print(
			"PROOF: fish shadow survives river water pass (%d fish pixels)" % int(over_water.fish_px)
		)
	## Priority 0 is weaker over water; exact erasure depends on depth, so only require
	## the high-priority pass to keep a clear silhouette.
	print(
		"priority0_fish_px=%d (lower is more erased)" % int(under_water.fish_px)
	)

	## Also prove the live school stocks a generated town river.
	Clock.month = 6
	Clock.hour = 12
	var data: WorldData = WorldGenerator.generate(42)
	data.bake()
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	var school := FishSchool.new()
	school.configure(grid, WorldBuilder.water_surface_y(), data)
	school.seed_rng(1)
	print(
		"generated bodies=%d has_water=%s" % [school.bodies.size(), str(school.has_water())]
	)
	var stand := Vector3.ZERO
	for body: WaterBodies.Body in school.bodies:
		if body.kind != WaterBodies.Kind.RIVER and body.kind != WaterBodies.Kind.OCEAN:
			continue
		if body.cells.is_empty():
			continue
		stand = grid.cell_to_world(body.cells[body.cells.size() / 2])
		break
	if stand == Vector3.ZERO and not school.bodies.is_empty():
		stand = grid.cell_to_world(school.bodies[0].cells[0])
	var sense := FishShadow.Sense.new()
	sense.player_position = stand
	for _i in 40:
		school.tick(0.5, sense)
	print("spawned_shadows=%d at %s" % [school.shadow_count(), stand])
	for shadow: FishShadow in school.shadows:
		print(
			"  %s kind=%d surface_y=%.3f"
			% [shadow.fish.id, shadow.body.kind, school.surface_at(shadow.position)]
		)
	if school.shadow_count() == 0:
		push_error("generated town produced no fish shadows near water")


func _shoot(shot_name: String, with_water: bool, priority: int) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = SHOT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.transparent_bg = false
	add_child(viewport)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.75, 0.95)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	viewport.add_child(env)

	if with_water:
		var water := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(8.0, 8.0)
		water.mesh = plane
		var water_mat := ShaderMaterial.new()
		water_mat.shader = RIVER_WATER
		water_mat.render_priority = 1
		water_mat.set_shader_parameter("prim_color", Color(1, 1, 1, 0.2))
		water_mat.set_shader_parameter("env_color", WATER_COLOR)
		water_mat.set_shader_parameter("ground_lift", FieldCatalog.GX_TO_METERS * 0.5)
		water.material_override = water_mat
		water.position = Vector3.ZERO
		viewport.add_child(water)

	var shadow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	shadow.mesh = quad
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = FISH_SHADOW
	mat.render_priority = priority
	mat.set_shader_parameter("alpha", 1.0)
	mat.set_shader_parameter("body_flex", 0.0)
	mat.set_shader_parameter("aspect", FishSize.SHADOW_ASPECT)
	shadow.material_override = mat
	shadow.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	var extent: Vector2 = FishSize.shadow_size(FishData.SizeClass.L)
	shadow.scale = Vector3(extent.x * 1.45, extent.y * 1.45, 1.0)
	## Match `FishShadows.SURFACE_LIFT` so the proof uses the same clearance over water.
	shadow.position = Vector3(0.0, FieldCatalog.GX_TO_METERS * 2.0, 0.0)
	viewport.add_child(shadow)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.position = Vector3(0.0, 4.0, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.current = true
	viewport.add_child(camera)

	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = viewport.get_texture().get_image()
	## Soft XLU shadow blends into the backdrop; score by contrast vs a corner sample.
	var corner: Color = image.get_pixel(8, 8)
	var fish_px := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c: Color = image.get_pixel(x, y)
			var delta: float = absf(c.r - corner.r) + absf(c.g - corner.g) + absf(c.b - corner.b)
			if delta > 0.12:
				fish_px += 1
	var out_path: String = "%s/%s.png" % [SHOT_DIR, shot_name]
	image.save_png(out_path)
	var repo_path: String = "res://.tmp_psel_debug/fish_proof_%s.png" % shot_name
	image.save_png(ProjectSettings.globalize_path(repo_path))
	print("%s fish_px=%d priority=%d -> %s" % [shot_name, fish_px, priority, out_path])
	viewport.queue_free()
	return {fish_px = fish_px}
