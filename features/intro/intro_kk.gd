extends Node3D

## Player-select opening with K.K. Slider (`ac_npc_p_sel`) → train intro.

## `aNPS_set_talk_info_talk_request`: 0x09C7 on a new game. The imported bank wins;
## the authored graph only runs when the disc text was not converted.
const DIALOGUE_ID := &"msg_2503"
const DIALOGUE_FALLBACK := &"kk_opening"

@onready var _kk: IntroKkAnim = %KkSlider
@onready var _camera: Camera3D = %IntroCamera
@onready var _fade: ColorRect = %FadeRect
@onready var _missing_banner: Label = %MissingBanner
@onready var _dialogue: DialogueOverlay = %DialogueOverlay
@onready var _silent_timer: Timer = %SilentTimer
@onready var _auto_advance: Timer = %AutoAdvance
@onready var _outro: AnimationPlayer = %Outro

var pose: IntroKkStage.Pose = IntroKkStage.Pose.STRUM
var _fading: bool = false
var _finishing: bool = false
var _dialogue_started: bool = false
## The saved town's player select (`ac_npc_p_sel2`) when there is one.
var _select: PlayerSelectTalk


func _ready() -> void:
	if _cmdline_has("--record-intro"):
		_auto_advance.start()
	Game.notify_intro_ready()
	## Fade in from the title's black wipe-out (`WIPE_TYPE_FADE_BLACK`).
	SceneTransition.play_wipe_in_if_pending()
	## Start unmuted — opening pose is strum (`Na_TTKK_ARM(FALSE)` while playing).
	Audio.set_ttkk_arm(false)
	Audio.play_bgm(IntroKkStage.BGM_ID)
	_dialogue.event_fired.connect(_on_dialogue_event)
	_dialogue.closed.connect(_on_dialogue_closed)
	_dialogue.awaiting_input_changed.connect(_on_awaiting_input_changed)
	_setup_stage_look()
	_setup_camera()
	_refresh_missing()
	if _fade != null:
		_fade.modulate.a = 0.0
		_fade.visible = true


func _setup_stage_look() -> void:
	## Black void + warm key; XLU spot fog (spot2 scroll) / shade on the acre.
	var acre: Node3D = get_node_or_null("%Acre") as Node3D
	if acre != null:
		var vis: Node3D = acre.get_node_or_null("GeneratedVisual") as Node3D
		if vis != null:
			VisualFit.fit_acre(vis)
		VisualFit.disable_shadows(acre)
		PlayerSelectSpot.apply(acre)
	var sun: DirectionalLight3D = get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = IntroKkStage.SUN_COLOR
		sun.light_energy = 1.0
		sun.shadow_enabled = false
		sun.basis = IntroKkStage.sun_basis()
	var world_env: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		var env: Environment = world_env.environment.duplicate() as Environment
		env.background_mode = Environment.BG_COLOR
		env.background_color = IntroKkStage.BG_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = IntroKkStage.AMBIENT_COLOR
		## K.K.'s shade is `player_select_ndotl.gdshader`. This fill does not tint him.
		env.ambient_light_energy = 1.0
		## `FIELD_DRAW_TYPE_PLAYER_SELECT` keeps fog_disabled — near==far kills GBI fog.
		## Black void + scrolling spot2 fog texture (not clear-color atmosphere).
		env.fog_enabled = false
		env.fog_light_color = IntroKkStage.FOG_COLOR
		env.volumetric_fog_enabled = false
		world_env.environment = env


func _process(delta: float) -> void:
	if _kk != null:
		_kk.tick_face(delta, _dialogue != null and _dialogue.is_uttering())


## One way into a pose: K.K.'s clip, and the guitar stem on while he strums, muted while he
## looks up (`Na_TTKK_ARM`).
func _set_pose(next: IntroKkStage.Pose) -> void:
	if pose == next:
		return
	pose = next
	Audio.set_ttkk_arm(pose != IntroKkStage.Pose.STRUM)
	if _kk != null:
		_kk.apply_pose(pose)


## `aNPS_talk_end_chk`: K.K. looks up while the text runs and, left waiting on the player
## (`silent_counter` climbing on MainNormal / choice), goes back to playing after a while.
func _on_awaiting_input_changed(awaiting: bool) -> void:
	if not _dialogue_started or _fading:
		return
	if awaiting:
		_silent_timer.start()
		return
	_silent_timer.stop()
	_set_pose(IntroKkStage.Pose.LOOK_UP)


func _on_silent_timeout() -> void:
	_set_pose(IntroKkStage.Pose.STRUM)


func _on_auto_advance() -> void:
	if not _finishing and _dialogue_started:
		_dialogue.fast_advance()


## After the talk: K.K. plays on while the `Outro` clip stops the music and fades to black.
func _begin_fade() -> void:
	if _fading:
		return
	_fading = true
	_silent_timer.stop()
	_set_pose(IntroKkStage.Pose.STRUM)
	_outro.play(&"outro")


## `Outro` method key: `bgm_stop_timer` runs out (`mBGMPsComp_make_ps_wipe(0x421C)`).
func _stop_music() -> void:
	Audio.stop_bgm()


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


## `TalkDelay`: the strum is over and K.K. talks (`aNPS_talk_end_chk` leaves 4haku for
## wait_e1 as soon as the talk runs).
func _on_talk_delay_timeout() -> void:
	if _dialogue_started or _finishing:
		return
	_set_pose(IntroKkStage.Pose.LOOK_UP)
	var data: DialogueData = DialogueCatalog.conversation(DIALOGUE_ID)
	if data == null:
		data = DialogueCatalog.conversation(DIALOGUE_FALLBACK)
	if data == null:
		## Still advance without authored lines so the train stays reachable.
		_begin_fade()
		return
	_dialogue_started = true
	if Game.player_select_mode and _begin_player_select():
		return
	var ctx := DialogueContext.new()
	ctx.vars = Game.town.dialogue_vars
	ctx.speaker_name = "K.K."
	_dialogue.play(data, ctx)


func _begin_player_select() -> bool:
	var roster: PlayerRoster = SaveService.read_roster()
	if roster.count() == 0:
		return false
	_select = PlayerSelectTalk.new(
		roster, SaveService.read_town_name(), maxi(SaveService.slot_of(SaveService.current_path), 0)
	)
	_select.passport = Travel.read_passport()
	_select.town_id = SaveService.read_town_id()
	var ctx := DialogueContext.new()
	ctx.speaker_name = "K.K."
	Clock.sync_from_os()
	ctx.hour = Clock.hour
	ctx.minute = Clock.minute
	ctx.month = Clock.month
	ctx.day = Clock.day
	ctx.year = Clock.year
	_select.context = ctx
	_select.prepare()
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % _select.start_msg()))
	if data == null:
		_select = null
		return false
	_dialogue.play(data, ctx, null, Callable(), _select)
	return true


func _on_dialogue_event(event: Dictionary) -> void:
	var op := String(event.get("op", event.get("type", "")))
	match op:
		"finish_kk_opening":
			_begin_fade()
		"kk_wait":
			## Farewell: look up (wait_e1).
			_set_pose(IntroKkStage.Pose.LOOK_UP)
		"kk_strum":
			_set_pose(IntroKkStage.Pose.STRUM)


func _on_dialogue_closed() -> void:
	## Safety if the graph ends without `finish_kk_opening`.
	if not _finishing:
		_begin_fade()


func _on_outro_finished(_clip: StringName) -> void:
	if _finishing:
		return
	_finishing = true
	if _select != null:
		_finish_player_select()
		return
	Game.advance_intro_to_train()


## `aNPS2_setup_game_start` / `aNPS2_return_title`.
func _finish_player_select() -> void:
	if not _select.demolished.is_empty():
		SaveService.write_roster(_select.roster)
	match _select.result:
		PlayerSelectTalk.Result.LOAD:
			Game.continue_game(_select.chosen)
		PlayerSelectTalk.Result.NEW:
			Game.start_new_resident(_select.chosen)
		PlayerSelectTalk.Result.VISIT:
			Game.start_visit()
		PlayerSelectTalk.Result.RETURN:
			Game.start_return()
		PlayerSelectTalk.Result.NEW_TOWN:
			## `mCD_EraseLand_bg`, then back to the title for a fresh start.
			SaveService.delete_save()
			Game.abort_intro_sequence()
		_:
			Game.abort_intro_sequence()


func _cmdline_has(flag: String) -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == flag:
			return true
	for arg: String in OS.get_cmdline_args():
		if arg == flag:
			return true
	return false
