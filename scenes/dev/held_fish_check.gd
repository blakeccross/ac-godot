extends Node

## Renders held-up catches and reports how many pixels each one covers.
##
## Exists because the unit suite runs headless and cannot draw: every structural test on
## `HeldCatch` passed while the fish was half its proper size and tucked inside the player's
## hip, which is not a state any assertion about transforms can see. Run windowed:
##
##   $GODOT_BIN --path . res://scenes/dev/held_fish_check.tscn
##
## Prints a line per species and orbits the posed player, writing PNGs to `user://held_fish`.

const IDS: Array[StringName] = [&"crucian_carp", &"arapaima", &"killifish", &"coelacanth"]
const POSED := &"crucian_carp"
const SHOT_DIR := "user://held_fish"
const SHOT_SIZE := Vector2i(320, 320)
const BACKDROP := Color.MAGENTA


func _ready() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	print("--- held fish render check ---")
	for id: StringName in IDS:
		var fish: FishData = FishCatalog.get_fish(id)
		if fish == null:
			print("%-14s MISSING from the catalog" % id)
			continue
		await _shoot_alone(id, fish)
	await _shoot_on_player(POSED)
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
	env.environment.ambient_light_color = Color.WHITE
	viewport.add_child(env)
	return viewport


func _save(viewport: SubViewport, shot_name: String) -> int:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var lit: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			if not image.get_pixel(x, y).is_equal_approx(BACKDROP):
				lit += 1
	image.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	return lit


func _shoot_alone(id: StringName, fish: FishData) -> void:
	var viewport: SubViewport = _viewport()
	var visual: HeldFish = HeldFish.create(fish)
	if visual == null:
		print("%-14s HeldFish.create() returned null" % id)
		return
	viewport.add_child(visual)

	var length: float = maxf(visual.longest_axis() * visual.scale.y, 0.05)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0.0, 0.0, length * 1.6)
	camera.look_at(Vector3.ZERO)
	camera.current = true

	var lit: int = await _save(viewport, String(id))
	## Where the origin sits inside the art matters as much as the size: the hand goes to the
	## origin, so a centred model puts the fist through the fish's middle.
	var box: AABB = visual.model_bounds()
	print(
		(
			"%-14s span=%.4f scale=%.4f length=%.3fm box=%s..%s pixels=%d %s"
			% [
				id,
				visual.longest_axis(),
				visual.scale.x,
				length,
				box.position,
				box.end,
				lit,
				"OK" if lit > 50 else "BLANK",
			]
		)
	)
	viewport.queue_free()


## The model drawing on its own proves little: it has to survive the trip through the rig,
## whose space is scaled, and land somewhere the camera can actually see.
func _shoot_on_player(id: StringName) -> void:
	var viewport: SubViewport = _viewport()
	var player: Node3D = load("res://scenes/actors/player.tscn").instantiate() as Node3D
	viewport.add_child(player)
	for _i in 4:
		await get_tree().process_frame

	var skeleton: Skeleton3D = HeldTool.find_skeleton(player.get("_mesh") as Node)
	if skeleton == null:
		print("player        no skeleton")
		return
	## With the rod in hand, since which hand is free is half the question.
	HeldTool.bind(skeleton, &"tol_sao_1")

	## The real beat down the real path, rather than a hand-posed clip: the player script
	## re-drives its own animation every frame, so anything staged from outside gets
	## overwritten, and `_play_show` is what does the binding in game anyway.
	var outcome := Fishing.Outcome.new()
	outcome.fish = FishCatalog.get_fish(id)
	outcome.catch_msg = outcome.fish.catch_msg
	var beats: Array[Fishing.ReelBeat] = Fishing.reel_beats(outcome)
	player.call("_play_show", beats[beats.size() - 1])
	for _i in 8:
		await get_tree().process_frame

	var visual: HeldFish = HeldCatch.held_fish(skeleton)
	if visual == null:
		print("player        the show-off beat bound no catch")
		return
	## Frozen through `time_scale` rather than `paused`, so the pose holds still across the
	## orbit while `_process` keeps running: pausing also stops the billboard, which leaves the
	## fish edge-on and reads as "not drawn" when it is only turned sideways.
	Engine.time_scale = 0.0

	print("player        frozen show-off pose, player-local:")
	for b: int in skeleton.get_bone_count():
		var at: Vector3 = (
			player.global_transform.affine_inverse()
			* (skeleton.global_transform * skeleton.get_bone_global_pose(b).origin)
		)
		print("  %2d %-24s %s" % [b, skeleton.get_bone_name(b), at])

	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	## Orbited, because from one angle "behind the player" and "never drawn" look identical,
	## which is exactly what went wrong the first time round. Hiding the body to check is not
	## an option: the catch hangs off a skeleton inside that mesh and goes with it.
	var aim: Vector3 = player.global_position + Vector3(0.0, 0.7, 0.0)
	for step: int in 4:
		var yaw: float = TAU * float(step) / 4.0
		camera.position = aim + Vector3(sin(yaw), 0.25, cos(yaw)) * 2.6
		camera.look_at(aim)
		## Counted by difference against the same frame with the catch hidden. Eyeballing a
		## silver fish against a mottled player is how a marker sphere got mistaken for it.
		var lit: int = await _save(viewport, "orbit_%d" % (step * 90))
		var with: Image = viewport.get_texture().get_image()
		visual.visible = false
		await _save(viewport, "orbit_%d_without" % (step * 90))
		var without: Image = viewport.get_texture().get_image()
		visual.visible = true
		var fish_pixels: int = 0
		for y: int in with.get_height():
			for x: int in with.get_width():
				if not with.get_pixel(x, y).is_equal_approx(without.get_pixel(x, y)):
					fish_pixels += 1
		if step == 0:
			print(
				(
					"player        rig scale=%s catch at %s world scale=%s"
					% [
						skeleton.global_transform.basis.get_scale(),
						visual.global_position,
						visual.global_transform.basis.get_scale(),
					]
				)
			)
		print(
			(
				"  orbit %3d     frame=%d fish=%d %s"
				% [step * 90, lit, fish_pixels, "OK" if fish_pixels > 200 else "HIDDEN"]
			)
		)
