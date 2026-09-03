extends Node3D

## Train intro presentation. Scene tree owns GLBs and layout; this script wires stage + dialogue.

const DIALOGUE_ID := &"rover_intro"

@onready var _stage_sync: IntroTrainStageSync = %StageSync
@onready var _train_car: Node3D = %TrainCar
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _door_host: Node3D = %TrainDoor
@onready var _rover_host: Node3D = %Rover
@onready var _sleep_npc: IntroTrainSleepNpc = %SleepPassenger
@onready var _keitai_host: Node3D = %Keitai
@onready var _camera_rig: Node3D = %IntroCameraRig
@onready var _missing_banner: Label = %MissingBanner
@onready var _dialogue: CanvasLayer = %DialogueOverlay
@onready var _clock_label: Label = %ClockLabel
@onready var _name_modal: Control = %NameModal
@onready var _town_modal: Control = %TownModal
@onready var _clock_modal: Control = %ClockModal
@onready var _name_edit: LineEdit = %NameEdit
@onready var _town_edit: LineEdit = %TownEdit
@onready var _year: SpinBox = %YearSpin
@onready var _month: SpinBox = %MonthSpin
@onready var _day: SpinBox = %DaySpin
@onready var _hour: SpinBox = %HourSpin
@onready var _minute: SpinBox = %MinuteSpin

var _intro: IntroSequence = IntroSequence.new()
var _stage: IntroTrainStage = IntroTrainStage.new()
var _rover_look: IntroTrainRoverLook = IntroTrainRoverLook.new()
var _rover_face: NpcFace = NpcFace.new()
var _rover_feel: NpcFeelGlyphs
var _ctx: DialogueContext
var _finishing: bool = false
var _dialogue_started: bool = false
## Dev capture: skip walk-up and park at seated daylight + optional farewell line.
var preview_seated_daylight: bool = false
var preview_dialogue_text: String = ""
var auto_advance_dialogue: bool = false
var _auto_advance_timer: float = 0.0


func _ready() -> void:
	if _cmdline_has("--record-intro"):
		auto_advance_dialogue = true
	Game.notify_intro_ready()
	if not preview_seated_daylight and not auto_advance_dialogue:
		Audio.play_bgm(&"title")
	_name_modal.visible = false
	_town_modal.visible = false
	_clock_modal.visible = false
	_refresh_clock_label()
	_intro.prompt_requested.connect(_on_prompt)
	_intro.finished.connect(_on_intro_finished)
	_intro.cancelled.connect(_on_intro_cancelled)
	_stage.ready_for_talk.connect(_on_ready_for_talk)
	_stage.stage_changed.connect(_on_stage_changed)
	if _dialogue.has_signal("event_fired") and not _dialogue.event_fired.is_connected(_on_dialogue_event):
		_dialogue.event_fired.connect(_on_dialogue_event)
	if not get_tree().process_frame.is_connected(_apply_rover_look):
		get_tree().process_frame.connect(_apply_rover_look)
	if _rover_host.has_signal("visual_ready"):
		_rover_host.visual_ready.connect(_bind_rover_face)
	var existing: Node3D = _rover_host.get_node_or_null("GeneratedVisual") as Node3D
	if existing != null:
		_bind_rover_face(existing)
	_bootstrap_stage()


func _process(delta: float) -> void:
	if not preview_seated_daylight:
		_stage.tick(delta)
	_rover_face.tick(delta, _dialogue_uttering())
	_poll_dialogue_stage_wait()
	if auto_advance_dialogue and not _finishing:
		_auto_advance_timer += delta
		if _auto_advance_timer >= 0.35:
			_auto_advance_timer = 0.0
			if _dialogue_started:
				_auto_advance_step()


func _dialogue_uttering() -> bool:
	return _dialogue.has_method("is_uttering") and _dialogue.is_uttering()


func _poll_dialogue_stage_wait() -> void:
	if not _dialogue_started or not _dialogue.has_method("runner"):
		return
	var runner: DialogueRunner = _dialogue.runner()
	if runner == null or not runner.waiting_stage:
		return
	if runner._stage_wait_key == "advance_gate":
		_stage.set_dialogue_wait_to(runner._stage_wait_next)
	if _stage.stage_wait_met(runner._stage_wait_key):
		runner.release_stage_wait()


func _apply_rover_look() -> void:
	_rover_look.tick(get_process_delta_time())


func _unhandled_input(event: InputEvent) -> void:
	if _finishing:
		return
	if _modal_open():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
		get_viewport().set_input_as_handled()
		_intro.cancel()


func _bootstrap_stage() -> void:
	var missing: PackedStringArray = IntroTrainStage.missing_assets()
	_missing_banner.visible = not missing.is_empty()
	if not missing.is_empty():
		_missing_banner.text = (
			"Missing generated train assets — run:\n"
			+ "python3 tools/build_assets.py --step convert\n"
			+ "(need rom_train_in, rom_train_out, obj_romtrain_door, xct_1, kab_1, tol_keitai_1)"
		)
	if not preview_seated_daylight:
		IntroTrainPresentation.apply_tunnel(_world_env, _train_car)
	var rover_anim: AnimationPlayer = (
		_rover_host.body_animation_player()
		if _rover_host.has_method("body_animation_player")
		else GeneratedVisual.find_animation_player(_rover_host)
	)
	_rover_look.bind(_rover_host)
	_stage.bind(
		_rover_host, rover_anim, _door_host, _keitai_host, _camera_rig, _rover_look, _stage_sync
	)
	if preview_seated_daylight:
		_bootstrap_seated_preview()
		return
	if missing.has(IntroTrainStage.required_asset_paths()[3]):
		_on_ready_for_talk()


func _bootstrap_seated_preview() -> void:
	IntroTrainPresentation.apply_daylight(_world_env, _train_car)
	_stage._pos_gx = IntroTrainStage.ROVER_SIT_GX
	_stage._yaw = 0.0
	_stage.action = IntroTrainStage.Action.SEATED
	_stage.lock_camera = true
	_stage.obj_look_talk = true
	_stage._obj_look_y_gx = IntroTrainStage.OBJ_LOOK_Y_TALK_GX
	_stage._obj_look_y_target_gx = IntroTrainStage.OBJ_LOOK_Y_TALK_GX
	_stage._apply_rover_pose()
	_stage._update_camera(0.0)
	if _stage._play_rover(IntroTrainStage.ANIM_SIT_WAIT, true, 1.0) and _rover_host.has_method(
		"snap_intro_clip_to_end"
	):
		_rover_host.snap_intro_clip_to_end()
	if preview_dialogue_text.is_empty():
		return
	call_deferred("_finish_seated_preview")


func _finish_seated_preview() -> void:
	_sleep_npc.realign()
	_dialogue_started = true
	DialogueCatalog.reset()
	var data := DialogueData.new()
	data.id = &"preview"
	data.start = &"line"
	data.nodes = {
		"line": {
			"type": "line",
			"text": preview_dialogue_text,
			"next": "",
		},
	}
	_ctx = DialogueContext.from_game()
	_ctx.speaker_name = "Rover"
	if _dialogue.has_method("play"):
		_dialogue.play(data, _ctx)


func _bind_rover_face(rover_visual: Node3D) -> void:
	_rover_face.bind(rover_visual, &"xct")
	## Entrance `open_d1` holds eye3 (stern) for most of the walk-in.
	if _stage.action == IntroTrainStage.Action.ENTER:
		_rover_face.set_emote(NpcFaceAnim.Emote.ANGRY)
	_ensure_rover_feel(rover_visual)


func _ensure_rover_feel(rover_visual: Node3D) -> void:
	if _rover_feel != null and is_instance_valid(_rover_feel):
		return
	_rover_feel = NpcFeelGlyphs.new()
	_rover_feel.name = "FeelGlyphs"
	_rover_host.add_child(_rover_feel)
	var lift: float = 1.15
	if rover_visual != null:
		var aabb := _local_visual_aabb(rover_visual)
		if aabb.size.y > 0.1:
			lift = aabb.position.y + aabb.size.y * 0.92
	_rover_feel.set_head_lift(lift)


func _local_visual_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local: AABB = _rover_host.global_transform.affine_inverse() * (mi.global_transform * mi.mesh.get_aabb())
		if first:
			merged = local
			first = false
		else:
			merged = merged.merge(local)
	return merged


func _on_stage_changed(action: StringName) -> void:
	match action:
		&"enter":
			## `npc_1_open_d1` fixed_pattern_seq parks on eye3 for the door walk-in.
			_rover_face.set_emote(NpcFaceAnim.Emote.ANGRY)
		&"approach", &"talk":
			if _rover_face.current_emote() == NpcFaceAnim.Emote.ANGRY:
				_rover_face.set_emote(NpcFaceAnim.Emote.NORMAL)
		&"seated":
			IntroTrainPresentation.apply_daylight(_world_env, _train_car)
			_sleep_npc.realign()


func _on_ready_for_talk() -> void:
	if _dialogue_started:
		return
	_dialogue_started = true
	_start_dialogue()


func _start_dialogue() -> void:
	DialogueCatalog.reset()
	var data: DialogueData = DialogueCatalog.conversation(DIALOGUE_ID)
	_ctx = DialogueContext.from_game()
	_ctx.speaker_name = "Rover"
	_ctx.vars = {}
	_ctx.vars["answer_flags"] = 0
	## Overlay forwards `event_fired` before `start()`, so manpu on the first line lands.
	if _dialogue.has_method("play"):
		_dialogue.play(data, _ctx, null, _dialogue_advance_gate)


func _dialogue_advance_gate(from_node: StringName, to_node: StringName) -> bool:
	_stage.set_dialogue_wait_to(to_node)
	return _stage.can_advance_dialogue(from_node, to_node)


func _on_dialogue_event(event: Dictionary) -> void:
	_intro.handle_event(event)
	var op := String(event.get("op", event.get("type", "")))
	match op:
		"rover_sit":
			_stage.cue_sit()
		"rover_phone":
			_stage.cue_phone()
		"rover_phone_done":
			_stage.end_phone_talk()
		"rover_return":
			_stage.cue_return_sit()
		"manpu", "set_emote":
			_apply_rover_manpu(event)


func _apply_rover_manpu(event: Dictionary) -> void:
	var op := String(event.get("op", event.get("type", "")))
	var name := str(event.get("name", event.get("manpu", event.get("emote", ""))))
	if name.is_empty() and event.has("code"):
		name = str(event.get("code"))
	if name.is_empty():
		return
	if op == "set_emote":
		_rover_face.set_emote(_emote_name(name))
		return
	_stage.cue_manpu(name)
	_rover_face.set_emote(NpcManpu.emote_for(name), NpcManpu.mouth_hold_for(name))
	if _rover_feel == null:
		_ensure_rover_feel(_rover_host.get_node_or_null("GeneratedVisual") as Node3D)
	if _rover_feel != null:
		_rover_feel.play_for_manpu(name)


func _emote_name(name: String) -> NpcFaceAnim.Emote:
	match name.strip_edges().to_lower():
		"laugh", "happy", "fun", "smile", "niko":
			return NpcFaceAnim.Emote.LAUGH
		"angry", "mad", "punpun", "musu", "hate":
			return NpcFaceAnim.Emote.ANGRY
		"sad", "komari", "gloomy":
			return NpcFaceAnim.Emote.SAD
		"surprise", "shock", "gaaan", "hirameki":
			return NpcFaceAnim.Emote.SURPRISE
		"cry":
			return NpcFaceAnim.Emote.CRY
		"sleepy":
			return NpcFaceAnim.Emote.SLEEPY
		_:
			return NpcManpu.emote_for(name)


func _on_prompt(kind: StringName) -> void:
	match kind:
		&"clock":
			_open_clock()
		&"name":
			_open_name()
		&"town":
			_open_town()


func _modal_open() -> bool:
	return _name_modal.visible or _town_modal.visible or _clock_modal.visible


func _hide_dialogue_box() -> void:
	if _dialogue.has_method("is_open") and _dialogue.is_open():
		var root: Control = _dialogue.get_node_or_null("%Root") as Control
		if root != null:
			root.visible = false


func _show_dialogue_box() -> void:
	var root: Control = _dialogue.get_node_or_null("%Root") as Control
	if root != null:
		root.visible = true


func _open_name() -> void:
	_hide_dialogue_box()
	_name_edit.text = _intro.player_name
	_name_modal.visible = true
	_name_edit.grab_focus()
	_name_edit.caret_column = _name_edit.text.length()


func _open_town() -> void:
	_hide_dialogue_box()
	_town_edit.text = _intro.town_name
	_town_modal.visible = true
	_town_edit.grab_focus()
	_town_edit.caret_column = _town_edit.text.length()


func _open_clock() -> void:
	_hide_dialogue_box()
	_year.value = Clock.year
	_month.value = Clock.month
	_day.value = Clock.day
	_hour.value = Clock.hour
	_minute.value = Clock.minute
	_clock_modal.visible = true
	_year.grab_focus()


func _on_name_submit() -> void:
	if not _intro.set_player_name(_name_edit.text):
		_name_edit.placeholder_text = "Enter a name"
		return
	_ctx.player_name = _intro.player_name
	_ctx.set_var("player_name", _intro.player_name)
	_name_modal.visible = false
	_resume_prompt()


func _on_town_submit() -> void:
	if not _intro.set_town_name(_town_edit.text):
		_town_edit.placeholder_text = "Enter a town"
		return
	_ctx.town_name = _intro.town_name
	_ctx.set_var("town_name", _intro.town_name)
	_town_modal.visible = false
	_resume_prompt()


func _on_clock_submit() -> void:
	Clock.apply_snapshot(
		{
			"year": int(_year.value),
			"month": int(_month.value),
			"day": int(_day.value),
			"hour": int(_hour.value),
			"minute": int(_minute.value),
			"second": 0,
		}
	)
	_ctx.year = Clock.year
	_ctx.month = Clock.month
	_ctx.day = Clock.day
	_ctx.hour = Clock.hour
	_ctx.minute = Clock.minute
	_ctx.weekday = Clock.weekday()
	_refresh_clock_label()
	_clock_modal.visible = false
	_resume_prompt()


func _resume_prompt() -> void:
	_show_dialogue_box()
	var runner: DialogueRunner = _dialogue.runner() if _dialogue.has_method("runner") else null
	if runner != null:
		runner.resume_after_prompt()


func _refresh_clock_label() -> void:
	_clock_label.text = "Train · %s" % Clock.format_clock()


func _on_intro_finished(identity: Dictionary) -> void:
	if auto_advance_dialogue:
		if _finishing:
			return
		_finishing = true
		if _dialogue.has_method("close"):
			_dialogue.close()
		get_tree().quit()
		return
	if _finishing:
		return
	_finishing = true
	if _dialogue.has_method("close"):
		_dialogue.close()
	call_deferred("_finish_deferred", identity)


func _finish_deferred(identity: Dictionary) -> void:
	Game.finish_intro_sequence(identity)


func _on_intro_cancelled() -> void:
	if _finishing:
		return
	_finishing = true
	if _dialogue.has_method("close"):
		_dialogue.close()
	call_deferred("_abort_deferred")


func _abort_deferred() -> void:
	Game.abort_intro_sequence()


func _cmdline_has(flag: String) -> bool:
	for arg: String in OS.get_cmdline_args():
		if arg == flag:
			return true
	return false


func _auto_advance_step() -> void:
	if _name_modal.visible:
		_name_edit.text = "Blake"
		_on_name_submit()
		return
	if _town_modal.visible:
		_town_edit.text = "Town"
		_on_town_submit()
		return
	if _clock_modal.visible:
		_on_clock_submit()
		return
	var runner: DialogueRunner = _dialogue.runner() if _dialogue.has_method("runner") else null
	if runner != null and _dialogue.has_method("is_open") and _dialogue.is_open():
		if _dialogue.has_method("fast_advance"):
			_dialogue.fast_advance()
		else:
			runner.advance()
