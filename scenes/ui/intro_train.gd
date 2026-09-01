extends Node3D

## Train intro presentation. Loads pipeline GLBs (`rom_train_in`, door, Rover/`cat_1`,
## `tol_keitai_1`) and drives `IntroTrainStage` + dialogue for a 1:1 Rover act.

const DIALOGUE_ID := &"rover_intro"
const ROVER_GLB := "res://assets/generated/characters/villagers/cat_1.glb"

@onready var _train_host: Node3D = %TrainCar
@onready var _window_host: Node3D = %WindowScenery
@onready var _door_host: Node3D = %TrainDoor
@onready var _rover_host: Node3D = %Rover
@onready var _keitai_host: Node3D = %Keitai
@onready var _camera: Camera3D = %IntroCamera
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
var _ctx: DialogueContext
var _finishing: bool = false
var _dialogue_started: bool = false


func _ready() -> void:
	Game.notify_intro_ready()
	Audio.play_bgm(&"title")
	_name_modal.visible = false
	_town_modal.visible = false
	_clock_modal.visible = false
	_refresh_clock_label()
	_intro.prompt_requested.connect(_on_prompt)
	_intro.finished.connect(_on_intro_finished)
	_intro.cancelled.connect(_on_intro_cancelled)
	_stage.ready_for_talk.connect(_on_ready_for_talk)
	_bootstrap_stage()


func _process(delta: float) -> void:
	_stage.tick(delta)


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
			+ "(need rom_train_in, rom_train_out, obj_romtrain_door, cat_1, tol_keitai_1)"
		)
	_attach_visuals()
	var rover_anim: AnimationPlayer = GeneratedVisual.find_animation_player(_rover_host)
	var door_anim: AnimationPlayer = GeneratedVisual.find_animation_player(_door_host)
	_stage.bind(_rover_host, rover_anim, _door_host, door_anim, _keitai_host, _camera)
	## No Rover mesh → skip walk-up so the title menu item stays testable.
	if not ResourceLoader.exists(ROVER_GLB):
		_on_ready_for_talk()


func _attach_visuals() -> void:
	var car: Node3D = GeneratedVisual.attach(_train_host, &"rom_train_in")
	if car != null:
		_fit_train_interior(car, &"rom_train_in")
	var scenery: Node3D = GeneratedVisual.attach(_window_host, &"rom_train_out")
	if scenery != null:
		_fit_train_interior(scenery, &"rom_train_out")
	GeneratedVisual.attach(_door_host, &"obj_romtrain_door")
	GeneratedVisual.attach_villager(_rover_host, &"cat")
	GeneratedVisual.attach(_keitai_host, &"tol_keitai_1")
	_keitai_host.visible = false
	_door_host.global_position = IntroTrainStage.gx_to_meters(Vector3(140.0, 0.0, 120.0))
	## Phone rides with Rover (hand-joint bind comes later).
	if _keitai_host.get_parent() != _rover_host:
		_keitai_host.reparent(_rover_host, false)
	_keitai_host.position = Vector3(0.15, 0.55, 0.1)
	_keitai_host.rotation = Vector3.ZERO


func _fit_train_interior(pivot: Node3D, visual_id: StringName) -> void:
	## `rom_*` acre-scale verts; place at demo origin (not room AABB fit).
	var s: float = FieldCatalog.interior_uniform_scale(visual_id)
	pivot.scale = Vector3.ONE * s
	pivot.position = Vector3(0.0, FieldCatalog.interior_ground_y_offset(visual_id), 0.0)


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
	if _dialogue.has_method("play"):
		_dialogue.play(data, _ctx)
	var runner: DialogueRunner = _dialogue.runner() if _dialogue.has_method("runner") else null
	if runner != null and not runner.event_fired.is_connected(_on_dialogue_event):
		runner.event_fired.connect(_on_dialogue_event)


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
