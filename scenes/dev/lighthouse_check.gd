extends Node

## Renders the lighthouse exterior by day and by night and reports non-backdrop pixel counts.
##
## Exists because the unit suite runs headless: it proves the scene instantiates, the
## switch/beacon wiring is correct, and mesh_paths() resolves — none of that shows whether
## the converted GLB actually replaced the placeholder box, or whether the beacon is visibly
## lit. Run windowed:
##
##   $GODOT_BIN --path . res://scenes/dev/lighthouse_check.tscn

const SHOT_DIR := "user://lighthouse_check"
const SHOT_SIZE := Vector2i(480, 480)
const BACKDROP := Color(0.05, 0.05, 0.08)


func _ready() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	print("--- lighthouse render check ---")
	var viewport := _viewport()
	var lighthouse: Node3D = load("res://scenes/world/buildings/lighthouse.tscn").instantiate()
	viewport.add_child(lighthouse)
	var switch: Node = lighthouse.get_node("LighthouseSwitch")
	var beacon: Node = lighthouse.get_node("Beacon")

	var cam := Camera3D.new()
	viewport.add_child(cam)
	cam.position = Vector3(6.0, 5.0, 8.0)
	cam.look_at(Vector3(0.0, 3.5, 0.0), Vector3.UP)
	cam.current = true

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	sun.light_energy = 1.2
	viewport.add_child(sun)

	beacon.set("on", false)
	await get_tree().process_frame ## let the beacon's deferred AnimationPlayer lookup land.
	await _save(viewport, "day")

	Clock.paused = true
	Clock.hour = 22
	switch.recheck()
	await _save(viewport, "night_frame0")

	var anim: AnimationPlayer = lighthouse.get_node("GeneratedVisual").find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	print("anim playing=%s current=%s pos=%.2f" % [anim.is_playing(), anim.current_animation, anim.current_animation_position])
	anim.seek(1.6, true) ## mid-sweep, away from the possibly-misleading rest frame.
	await _save(viewport, "night_mid_sweep")
	print("switch.is_on()=%s beacon.on=%s" % [switch.is_on(), beacon.get("on")])

	## Animation proof: sample the head's yaw across several simulated seconds and confirm
	## it advances monotonically at the documented SPIN_SPEED, not just a one-off nudge.
	var head: Node3D = beacon.get_node("Head")
	print("--- beacon spin samples (day: on=false) ---")
	beacon.set("on", false)
	var day_start: float = head.rotation.y
	for i in 3:
		beacon._process(1.0)
	print("day   head.rotation.y: %.4f -> %.4f (delta=%.4f, expect 0)" % [day_start, head.rotation.y, head.rotation.y - day_start])
	beacon.set("on", true)
	var t: float = head.rotation.y
	print("--- beacon spin samples (night: on=true) ---")
	for i in 5:
		beacon._process(1.0)
		var now: float = head.rotation.y
		print("t=%ds head.rotation.y=%.4f delta=%.4f" % [i + 1, now, now - t])
		t = now
	await _save(viewport, "night_spun")

	print("shots in %s" % ProjectSettings.globalize_path(SHOT_DIR))
	get_tree().quit()


func _viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = SHOT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	add_child(viewport)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = BACKDROP
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.25, 0.25, 0.3)
	viewport.add_child(env)
	return viewport


func _save(viewport: SubViewport, shot_name: String) -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, shot_name]
	image.save_png(path)
	var bg := Vector3(BACKDROP.r, BACKDROP.g, BACKDROP.b)
	var lit_px := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var px: Color = image.get_pixel(x, y)
			if Vector3(px.r, px.g, px.b).distance_to(bg) > 0.05:
				lit_px += 1
	print("%-6s -> %s (%d sampled non-backdrop px)" % [shot_name, path, lit_px])
