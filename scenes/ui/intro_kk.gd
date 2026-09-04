extends Node3D

## Player-select opening with K.K. Slider (`ac_npc_p_sel`) → train intro.

const DIALOGUE_ID := &"kk_opening"

@onready var _kk: IntroKkAnim = %KkSlider
@onready var _camera: Camera3D = %IntroCamera
@onready var _fade: ColorRect = %FadeRect
@onready var _missing_banner: Label = %MissingBanner
@onready var _dialogue: CanvasLayer = %DialogueOverlay

var _stage: IntroKkStage = IntroKkStage.new()
var _finishing: bool = false
var _dialogue_started: bool = false
var auto_advance_dialogue: bool = false
var _auto_advance_timer: float = 0.0


func _ready() -> void:
	if _cmdline_has("--record-intro"):
		auto_advance_dialogue = true
	Game.notify_intro_ready()
	Audio.play_bgm(IntroKkStage.BGM_ID)
	_stage.reset()
	_stage.ready_for_talk.connect(_on_ready_for_talk)
	_stage.fade_finished.connect(_on_fade_finished)
	_stage.pose_changed.connect(_on_pose_changed)
	if _dialogue.has_signal("event_fired") and not _dialogue.event_fired.is_connected(_on_dialogue_event):
		_dialogue.event_fired.connect(_on_dialogue_event)
	if _dialogue.has_signal("closed") and not _dialogue.closed.is_connected(_on_dialogue_closed):
		_dialogue.closed.connect(_on_dialogue_closed)
	_setup_stage_look()
	_setup_camera()
	_refresh_missing()
	if _fade != null:
		_fade.modulate.a = 0.0
		_fade.visible = true


func _setup_stage_look() -> void:
	## Black void + warm key (`l_mEnv_kcolor_data_p_sel`); acre XLU spot/shade.
	var acre: Node3D = get_node_or_null("%Acre") as Node3D
	if acre != null:
		var vis: Node3D = acre.get_node_or_null("GeneratedVisual") as Node3D
		if vis != null:
			GeneratedVisual.fit_acre(vis)
		GeneratedVisual.apply_authored_interior(acre)
	var sun: DirectionalLight3D = get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = IntroKkStage.SUN_COLOR
		sun.light_energy = 1.45
		sun.shadow_enabled = false
		sun.basis = IntroKkStage.sun_basis()
	var world_env: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		var env: Environment = world_env.environment.duplicate() as Environment
		env.background_mode = Environment.BG_COLOR
		env.background_color = IntroKkStage.BG_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = IntroKkStage.AMBIENT_COLOR
		## White fur needs fill or the body reads as a black stick under the key alone.
		## Decomp ambient RGB is tiny; energy >>1 keeps the cool tint without a black silhouette.
		env.ambient_light_energy = 1.35
		## Decomp fog `(100,100,120)` reads as a purple band over the void — keep clear black.
		env.fog_enabled = false
		env.fog_light_color = Color(0.0, 0.0, 0.0, 1.0)
		env.volumetric_fog_enabled = false
		world_env.environment = env


func _process(delta: float) -> void:
	var awaiting: bool = (
		_dialogue_started
		and _dialogue != null
		and _dialogue.has_method("is_awaiting_input")
		and _dialogue.is_awaiting_input()
	)
	_stage.tick(delta, awaiting)
	if _kk != null:
		var uttering: bool = (
			_dialogue != null
			and _dialogue.has_method("is_uttering")
			and _dialogue.is_uttering()
		)
		_kk.tick_face(delta, uttering)
	if _fade != null:
		_fade.modulate.a = _stage.fade_alpha
	if auto_advance_dialogue and not _finishing and _dialogue_started:
		_auto_advance_timer += delta
		if _auto_advance_timer >= 0.35:
			_auto_advance_timer = 0.0
			if _dialogue.has_method("fast_advance"):
				_dialogue.fast_advance()


func _on_pose_changed(pose: int) -> void:
	if _kk != null:
		_kk.apply_pose(pose)


func _unhandled_input(event: InputEvent) -> void:
	if _finishing:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
		get_viewport().set_input_as_handled()
		Game.abort_intro_sequence()


func _setup_camera() -> void:
	if _camera == null:
		return
	_camera.current = true
	_camera.fov = IntroKkStage.CAM_FOV
	_camera.near = IntroKkStage.CAM_NEAR_METERS
	_camera.far = IntroKkStage.CAM_FAR_METERS
	_camera.global_position = IntroKkStage.gx_to_meters(IntroKkStage.CAM_EYE_GX)
	_camera.look_at(IntroKkStage.gx_to_meters(IntroKkStage.CAM_CENTER_GX), Vector3.UP)


func _refresh_missing() -> void:
	var missing: PackedStringArray = IntroKkStage.missing_assets()
	_missing_banner.visible = not missing.is_empty()
	if not missing.is_empty():
		_missing_banner.text = (
			"Missing generated KK opening assets — run:\n"
			+ "python3 tools/build_assets.py --step convert"
		)


func _on_ready_for_talk() -> void:
	if _dialogue_started or _finishing:
		return
	var data: DialogueData = DialogueCatalog.conversation(DIALOGUE_ID)
	if data == null:
		## Still advance without authored lines so the train stays reachable.
		_stage.begin_fade()
		return
	_dialogue_started = true
	var ctx := DialogueContext.new()
	ctx.vars = Game.dialogue_vars
	ctx.speaker_name = "K.K."
	_dialogue.play(data, ctx)


func _on_dialogue_event(event: Dictionary) -> void:
	var op := String(event.get("op", event.get("type", "")))
	match op:
		"finish_kk_opening":
			if _kk != null:
				_kk.play_strum()
			_stage.begin_fade()
		"kk_wait":
			## Farewell: look up (wait_e1).
			if _kk != null:
				_kk.play_look_up()
			_stage.request_look_up()
		"kk_strum":
			if _kk != null:
				_kk.play_strum()
			_stage.request_strum()


func _on_dialogue_closed() -> void:
	## Safety if the graph ends without `finish_kk_opening`.
	if _finishing:
		return
	if _stage.phase == IntroKkStage.Phase.TALK or _stage.phase == IntroKkStage.Phase.STRUM:
		_stage.begin_fade()


func _on_fade_finished() -> void:
	if _finishing:
		return
	_finishing = true
	Game.advance_intro_to_train()


func _cmdline_has(flag: String) -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == flag:
			return true
	for arg: String in OS.get_cmdline_args():
		if arg == flag:
			return true
	return false
