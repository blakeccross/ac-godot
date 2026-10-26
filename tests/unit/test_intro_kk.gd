class_name TestIntroKk
extends GdUnitTestSuite

## K.K. opening (`ac_npc_p_sel`) → train handoff.


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	DialogueCatalog.reset()
	Audio.fade_sec = 0.0
	Audio.set_ttkk_arm(false)
	Audio.stop_bgm()


func after_test() -> void:
	Audio.stop_bgm()
	Audio.set_ttkk_arm(false)
	Audio.fade_sec = Audio.FADE_SEC
	DialogueCatalog.reset()
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_game_start_intro_targets_kk_scene() -> void:
	assert_str(Game.INTRO_KK_SCENE).is_equal("res://features/intro/intro_kk.tscn")
	assert_that(ResourceLoader.exists(Game.INTRO_KK_SCENE)).is_true()
	assert_str(Game.INTRO_SCENE).is_equal("res://features/intro/intro_train.tscn")


func test_kk_opening_dialogue_exists() -> void:
	var data: DialogueData = DialogueCatalog.conversation(&"kk_opening")
	assert_that(data).is_not_null()
	assert_bool(data.has_node(&"finish")).is_true()
	assert_bool(data.has_node(&"welcome")).is_true()
	assert_bool(data.has_node(&"ready_choice")).is_true()
	## First-game welcome paraphrases decomp msg 0x09C7 (move-out → friends → train).
	var welcome: Dictionary = data.node(&"welcome")
	assert_str(String(welcome.get("text", ""))).contains("own")
	var choice: Dictionary = data.node(&"ready_choice")
	assert_that(choice.get("type")).is_equal("choice")


## The decomp's counts, in 60 Hz ticks: `aNPS_schedule_init_proc` strum, `aNPS_talk_end_chk`
## silent wait, and after the talk `strum_timer` / `bgm_stop_timer` / the `< 70` fade ramp.
const STRUM_TICKS := 440
const SILENT_TICKS := 600
const OUTRO_TICKS := 150
const MUSIC_STOP_TICKS := 80
const FADE_RAMP_TICKS := 70
const S := DecompTime.TICK_SEC


func test_timing_nodes_match_the_decomp() -> void:
	var scene: Node3D = await _scene()
	var talk_delay := scene.get_node("%TalkDelay") as Timer
	assert_float(talk_delay.wait_time).is_equal_approx(STRUM_TICKS * S, 0.001)
	assert_bool(talk_delay.one_shot).is_true()
	## `autostart` clears itself once the timer is in the tree; it is running.
	assert_bool(talk_delay.is_stopped()).is_false()
	var silent := scene.get_node("%SilentTimer") as Timer
	assert_float(silent.wait_time).is_equal_approx(SILENT_TICKS * S, 0.001)
	assert_bool(silent.one_shot).is_true()
	var outro: Animation = (scene.get_node("%Outro") as AnimationPlayer).get_animation(&"outro")
	assert_float(outro.length).is_equal_approx(OUTRO_TICKS * S, 0.001)
	var fade: int = outro.find_track(^"UI/FadeRect:modulate:a", Animation.TYPE_VALUE)
	assert_int(fade).is_not_equal(-1)
	assert_float(float(outro.value_track_interpolate(fade, 0.0))).is_equal_approx(0.0, 0.001)
	var ramp_from: int = OUTRO_TICKS - FADE_RAMP_TICKS
	assert_float(float(outro.value_track_interpolate(fade, ramp_from * S))).is_equal_approx(0.0, 0.001)
	## Linear over the ramp: halfway through, half dark.
	var halfway: float = (ramp_from + FADE_RAMP_TICKS * 0.5) * S
	assert_float(float(outro.value_track_interpolate(fade, halfway))).is_equal_approx(0.5, 0.01)
	assert_float(float(outro.value_track_interpolate(fade, OUTRO_TICKS * S))).is_equal_approx(1.0, 0.001)
	var calls: int = outro.find_track(^".", Animation.TYPE_METHOD)
	assert_int(outro.track_get_key_count(calls)).is_equal(1)
	assert_float(outro.track_get_key_time(calls, 0)).is_equal_approx(MUSIC_STOP_TICKS * S, 0.001)
	assert_str(String(outro.method_track_get_name(calls, 0))).is_equal("_stop_music")


func test_talk_looks_up_then_idle_resumes_strum() -> void:
	var scene: Node3D = await _scene()
	var silent := scene.get_node("%SilentTimer") as Timer
	var dialogue := scene.get_node("%DialogueOverlay") as DialogueOverlay
	(scene.get_node("%TalkDelay") as Timer).timeout.emit()
	assert_that(scene.get("pose")).is_equal(IntroKkStage.Pose.LOOK_UP)
	## Left waiting on the player: the silent wait starts, and runs out into strumming.
	dialogue.awaiting_input_changed.emit(true)
	assert_bool(silent.is_stopped()).is_false()
	silent.timeout.emit()
	assert_that(scene.get("pose")).is_equal(IntroKkStage.Pose.STRUM)
	assert_bool(Audio.arm_muted).is_false()
	## The talk moves on: look up again, the wait reset.
	dialogue.awaiting_input_changed.emit(false)
	assert_that(scene.get("pose")).is_equal(IntroKkStage.Pose.LOOK_UP)
	assert_bool(Audio.arm_muted).is_true()
	assert_bool(silent.is_stopped()).is_true()


func test_outro_strums_and_stops_the_music() -> void:
	var scene: Node3D = await _scene()
	(scene.get_node("%TalkDelay") as Timer).timeout.emit()
	scene.call("_begin_fade")
	assert_that(scene.get("pose")).is_equal(IntroKkStage.Pose.STRUM)
	var outro := scene.get_node("%Outro") as AnimationPlayer
	assert_bool(outro.is_playing()).is_true()
	## Short of the end: finishing changes scene to the train.
	outro.advance(MUSIC_STOP_TICKS * S + 0.05)
	## Just into the ramp: barely darkened yet.
	assert_float((scene.get_node("%FadeRect") as ColorRect).modulate.a).is_less(0.1)
	## Method keys run deferred (`ANIMATION_CALLBACK_MODE_METHOD_DEFERRED`).
	await get_tree().process_frame
	assert_that(Audio.current_id).is_equal(&"")
	outro.stop()


func _scene() -> Node3D:
	var scene: Node3D = auto_free((load("res://features/intro/intro_kk.tscn") as PackedScene).instantiate()) as Node3D
	add_child(scene)
	await get_tree().process_frame
	return scene


func test_camera_and_spawn_match_decomp() -> void:
	var gx: float = FieldCatalog.GX_TO_METERS
	var eps := Vector3.ONE * 0.0001
	assert_vector(IntroKkStage.CAM_CENTER).is_equal_approx(Vector3(100.0, 20.0, 60.0) * gx, eps)
	assert_vector(IntroKkStage.CAM_EYE).is_equal_approx(Vector3(100.0, 90.0, 210.0) * gx, eps)
	assert_vector(IntroKkStage.KK_SPAWN).is_equal_approx(Vector3(100.0, 0.0, 60.0) * gx, eps)
	assert_float(IntroKkStage.CAM_FOV).is_equal(40.0)
	assert_vector(IntroKkStage.SUN_DIR).is_equal(Vector3(0.0, 89.0, 79.0))
	## Literal GX near (5 m) clips the seated mesh; use the train-style short near.
	assert_float(IntroKkStage.CAM_NEAR).is_equal_approx(0.1, 0.0001)
	## DirectionalLight shines along −Z; that should match −sun_dir (light travel).
	assert_that(
		(-IntroKkStage.sun_basis().z).dot((-IntroKkStage.SUN_DIR).normalized())
	).is_greater(0.99)


func test_stage_clear_is_black_void() -> void:
	## Captures show black; fog stays off. Grain comes from spot2, not clear color.
	assert_float(IntroKkStage.BG_COLOR.r).is_equal_approx(0.0, 0.001)
	assert_float(IntroKkStage.BG_COLOR.g).is_equal_approx(0.0, 0.001)
	assert_float(IntroKkStage.BG_COLOR.b).is_equal_approx(0.0, 0.001)
	assert_float(IntroKkStage.FOG_COLOR.r).is_equal_approx(100.0 / 255.0, 0.001)


func test_kk_scene_loads() -> void:
	var packed: PackedScene = load("res://features/intro/intro_kk.tscn")
	assert_that(packed).is_not_null()
	var scene: Node3D = auto_free(packed.instantiate()) as Node3D
	assert_that(scene).is_not_null()
	add_child(scene)
	await get_tree().process_frame
	assert_that(scene.get_node_or_null("%KkSlider")).is_not_null()
	assert_that(scene.get_node_or_null("%IntroCamera")).is_not_null()
	assert_that(scene.get_node_or_null("%DialogueOverlay")).is_not_null()
	assert_that(scene.get_node_or_null("%FadeRect")).is_not_null()
	assert_that(scene.get_node("%KkSlider") is IntroKkAnim).is_true()
	var kk: IntroKkAnim = scene.get_node("%KkSlider") as IntroKkAnim
	if ResourceLoader.exists(IntroKkStage.KK_PATH):
		var anim: AnimationPlayer = kk.body_animation_player()
		assert_that(anim).is_not_null()
		assert_str(IntroKkStage.resolve_clip(anim, IntroKkStage.ANIM_STRUM)).is_not_empty()
		assert_str(IntroKkStage.resolve_clip(anim, IntroKkStage.ANIM_LOOK_UP)).is_not_empty()
		assert_bool(kk.play_strum()).is_true()
		assert_bool(anim.is_playing()).is_true()
		var lit := _first_ndotl(kk)
		assert_that(lit).is_not_null()
		assert_that((lit.get_shader_parameter("ambient_color") as Color)).is_equal(IntroKkStage.AMBIENT_COLOR)
		assert_vector(lit.get_shader_parameter("sun_direction") as Vector3).is_equal(IntroKkStage.CHARACTER_SUN_DIR)
	if ResourceLoader.exists(PlayerSelectSpot.GRAIN_PATH):
		var spot := _first_spot(scene)
		assert_that(spot).is_not_null()
		assert_vector(spot.get_shader_parameter("wrap_tiles") as Vector2).is_equal(Vector2(2, 1))
		assert_float(float(spot.get_shader_parameter("game_fps"))).is_equal_approx(DecompTime.TICK_HZ, 0.01)
		assert_float(float(spot.get_shader_parameter("lod_frac"))).is_equal_approx(PlayerSelectSpot.LOD_FRAC, 0.001)
		assert_float(float(spot.get_shader_parameter("beam_opacity"))).is_equal_approx(PlayerSelectSpot.BEAM_OPACITY, 0.001)


func test_ndotl_skips_unshaded_and_replaces_lit_standard() -> void:
	var host := MeshInstance3D.new()
	add_child(host)
	auto_free(host)
	host.mesh = BoxMesh.new()
	var lit := StandardMaterial3D.new()
	lit.resource_name = "body"
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	lit.albedo_texture = tex
	host.set_surface_override_material(0, lit)
	var shade := StandardMaterial3D.new()
	shade.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	## BoxMesh has one surface; a second override is ignored. Use a child mesh.
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.set_surface_override_material(0, shade)
	host.add_child(floor_mesh)
	PlayerSelectLight.apply(host)
	var body := host.get_surface_override_material(0) as ShaderMaterial
	assert_that(body).is_not_null()
	assert_that(body.shader).is_same(PlayerSelectLight.SHADER)
	assert_str(body.resource_name).is_equal("body")
	assert_that(body.get_shader_parameter("albedo_tex")).is_same(tex)
	assert_float(float(body.get_shader_parameter("alpha_scissor_threshold"))).is_equal_approx(0.0, 0.001)
	assert_that(floor_mesh.get_surface_override_material(0)).is_same(shade)


func test_spot_shader_uses_wrap_tiles_and_leaves_the_curtain() -> void:
	var host := MeshInstance3D.new()
	add_child(host)
	auto_free(host)
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(0, "rom_open_spot_tex")
	host.mesh = mesh
	var std := StandardMaterial3D.new()
	std.resource_name = "rom_open_spot_tex"
	std.set_meta("extras", {"wrap_tiles": [2.0, 1.0]})
	host.set_surface_override_material(0, std)
	var curtain := MeshInstance3D.new()
	curtain.mesh = mesh.duplicate()
	(curtain.mesh as ArrayMesh).surface_set_name(0, "rom_open_shade_tex")
	var shade := StandardMaterial3D.new()
	shade.resource_name = "rom_open_shade_tex"
	curtain.set_surface_override_material(0, shade)
	host.add_child(curtain)
	PlayerSelectSpot.apply(host)
	if not ResourceLoader.exists(PlayerSelectSpot.GRAIN_PATH):
		assert_that(host.get_surface_override_material(0)).is_same(std)
		return
	var spot := host.get_surface_override_material(0) as ShaderMaterial
	assert_that(spot).is_not_null()
	assert_that(spot.shader).is_same(PlayerSelectSpot.SHADER)
	assert_vector(spot.get_shader_parameter("wrap_tiles") as Vector2).is_equal(Vector2(2, 1))
	assert_that(spot.get_shader_parameter("grain_tex")).is_not_null()
	assert_that(spot.get_shader_parameter("cone_tex")).is_not_null()
	assert_that(curtain.get_surface_override_material(0)).is_same(shade)


func _first_spot(node: Node) -> ShaderMaterial:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var count := 0
		if mesh_instance.mesh != null:
			count = mesh_instance.mesh.get_surface_count()
		for i: int in count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader == PlayerSelectSpot.SHADER:
				return mat as ShaderMaterial
	for child: Node in node.get_children():
		var found := _first_spot(child)
		if found != null:
			return found
	return null


func _first_ndotl(node: Node) -> ShaderMaterial:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var count := 0
		if mesh_instance.mesh != null:
			count = mesh_instance.mesh.get_surface_count()
		for i: int in count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader == PlayerSelectLight.SHADER:
				return mat as ShaderMaterial
	for child: Node in node.get_children():
		var found := _first_ndotl(child)
		if found != null:
			return found
	return null
