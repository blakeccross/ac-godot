extends Node3D

## Debug-only station acre (`ac_intro_demo`). Title **Station Arrival** uses the
## generated world + `IntroStationDirector` instead.

## Prefer imported bank ids; authored JSON is the no-bank fallback.
const PORTER_DIALOGUE := &"msg_2013"
const PORTER_DIALOGUE_FALLBACK := &"porter_arrive"
const NOOK_CALL_DIALOGUE := &"msg_2014"
const NOOK_CALL_DIALOGUE_FALLBACK := &"nook_station_call"
const NOOK_INTRO_DIALOGUE := &"msg_2015"
const NOOK_INTRO_DIALOGUE_FALLBACK := &"nook_station_greeting"
const NOOK_HOUSES_DIALOGUE := &"msg_2017"
const NOOK_HOUSES_DIALOGUE_FALLBACK := &"nook_show_houses"
const NOOK_DEBT_DIALOGUE := &"msg_2022"
const NOOK_DEBT_DIALOGUE_FALLBACK := &"nook_house_debt"
const NOOK_JOB_DIALOGUE := &"nook_first_job"

@onready var _camera: Camera3D = %IntroCamera
@onready var _loco: Node3D = %TrainLoco
@onready var _caboose: Node3D = %TrainCaboose
@onready var _engineer: Node3D = %Engineer
@onready var _porter: Node3D = %Porter
@onready var _nook: Node3D = %Nook
@onready var _player: Node3D = %DemoPlayer
@onready var _dialogue: CanvasLayer = %DialogueOverlay
@onready var _missing_banner: Label = %MissingBanner
@onready var _fade: ColorRect = %FadeRect
@onready var _outdoor: Node3D = %Outdoor
@onready var _house_interior: Node3D = %HouseInterior
@onready var _interior_hint: Label = %InteriorHint

var _stage: IntroStationStage = IntroStationStage.new()
var _finishing: bool = false
var _fade_out: bool = false
var _fade_t: float = 0.0
var _fade_mode: StringName = &""
var _pick_enabled: bool = false
var _in_house: bool = false
var _house_doors: Array[Area3D] = []


func _ready() -> void:
	Game.notify_intro_ready()
	_prepare_visuals()
	_prepare_houses()
	_prepare_interior()
	var mid: Node3D = get_node_or_null("%TrainMid") as Node3D
	_stage.bind(_loco, mid, _caboose, _engineer, _porter, _nook, _player, _camera)
	_stage.porter_talk_requested.connect(_on_porter_talk)
	_stage.nook_call_requested.connect(_on_nook_call)
	_stage.nook_introduce_requested.connect(_on_nook_introduce)
	_stage.nook_show_houses_requested.connect(_on_nook_show_houses)
	_stage.nook_debt_requested.connect(_on_nook_debt)
	_stage.nook_job_requested.connect(_on_nook_job)
	_stage.house_pick_enabled.connect(_on_house_pick_enabled)
	_stage.enter_house_requested.connect(_on_enter_house)
	_stage.leave_house_requested.connect(_on_leave_house_visual)
	_stage.finished.connect(_on_stage_finished)
	if _dialogue.has_signal("closed") and not _dialogue.closed.is_connected(_on_dialogue_closed):
		_dialogue.closed.connect(_on_dialogue_closed)
	_refresh_missing()
	var bgm: StringName = IntroStationStage.BGM_ID
	if BgmCatalog.stream_for(bgm) == null:
		bgm = &"intro_train"
	Audio.play_bgm(bgm)
	_stage.reset()
	if _fade != null:
		_fade.modulate.a = 0.0
		_fade.visible = true


func _process(delta: float) -> void:
	if _finishing:
		return
	_stage.tick(delta)
	_poll_house_doors()
	if not _fade_out or _fade == null:
		return
	_fade_t = minf(1.0, _fade_t + delta / 0.7)
	_fade.modulate.a = _fade_t if _fade_mode != &"from_black" else 1.0 - _fade_t
	if _fade_t < 1.0:
		return
	match _fade_mode:
		&"to_house":
			_show_interior(true)
			_fade_mode = &"from_black"
			_fade_t = 0.0
		&"to_outside":
			_show_interior(false)
			_stage.notify_house_exited()
			_fade_mode = &"from_black"
			_fade_t = 0.0
		&"from_black":
			_fade_out = false
			_fade.modulate.a = 0.0
			if _stage.action == IntroStationStage.Action.DONE:
				_finishing = true
				_finish_to_game()
		&"to_game":
			_finishing = true
			_finish_to_game()


func _poll_house_doors() -> void:
	if not _pick_enabled or _player == null:
		return
	var p: Vector3 = _player.global_position
	for door: Area3D in _house_doors:
		if door == null:
			continue
		if p.distance_to(door.global_position) <= 1.6:
			var idx: int = int(door.get_meta("house_idx", 0))
			_pick_enabled = false
			_stage.notify_house_entered(idx)
			return


func _begin_leave_house() -> void:
	if not _in_house or _fade_out:
		return
	_fade_mode = &"to_outside"
	_fade_out = true
	_fade_t = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if _finishing:
		return
	if _in_house and (
		event.is_action_pressed("interact")
		or event.is_action_pressed("ui_accept")
	):
		get_viewport().set_input_as_handled()
		_begin_leave_house()
		return
	if _fade_out:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
		get_viewport().set_input_as_handled()
		Game.abort_intro_sequence()


func _prepare_visuals() -> void:
	_fit_acre(%Acre)
	_fit_actor(_loco, &"obj_train1_1")
	_fit_actor(get_node_or_null("%TrainMid") as Node3D, &"obj_train1_2")
	_fit_actor(_caboose, &"obj_train1_3")
	_fit_actor(%Station, &"obj_s_station1")
	_fit_actor(_engineer, &"mnk_1")
	_fit_actor(_porter, &"mnk_1")
	_fit_actor(_nook, &"rcn_1")
	_fit_actor(_player, &"boy_1")
	_set_node_gx(
		%Station,
		Vector3(
			IntroStationStage.STATION_GX.x,
			IntroStationStage.PLATFORM_Y_GX,
			IntroStationStage.STATION_GX.z
		)
	)


func _prepare_houses() -> void:
	_house_doors.clear()
	for i: int in IntroStationStage.HOUSE_GX.size():
		var host: Node3D = get_node_or_null("Outdoor/House%d" % i) as Node3D
		if host == null:
			continue
		_fit_actor(host, &"obj_s_myhome1")
		var gx: Vector3 = IntroStationStage.HOUSE_GX[i]
		_set_node_gx(host, Vector3(gx.x, IntroStationStage.LAND_Y_GX, gx.z))
		host.rotation = Vector3(0.0, PI, 0.0) ## face −Z toward station
		var door: Area3D = host.get_node_or_null("DoorSensor") as Area3D
		if door == null:
			continue
		door.set_meta("house_idx", i)
		_house_doors.append(door)


func _prepare_interior() -> void:
	if _house_interior == null:
		return
	_house_interior.visible = false
	for child_name: String in ["Floor", "Wall"]:
		var host: Node3D = _house_interior.get_node_or_null(child_name) as Node3D
		if host == null:
			continue
		var vis: Node3D = host.get_node_or_null("GeneratedVisual") as Node3D
		if vis == null:
			continue
		var id: StringName = &"rom_myhome1_floor" if child_name == "Floor" else &"rom_myhome1_wall"
		GeneratedVisual.apply_actor_scale(vis, id)
		GeneratedVisual.apply_preview_materials(vis)
	if _interior_hint != null:
		_interior_hint.visible = false


func _fit_acre(host: Node3D) -> void:
	if host == null:
		return
	var vis: Node3D = host.get_node_or_null("GeneratedVisual") as Node3D
	if vis != null:
		GeneratedVisual.fit_acre(vis)


func _fit_actor(host: Node3D, visual_id: StringName) -> void:
	if host == null:
		return
	var vis: Node3D = host.get_node_or_null("GeneratedVisual") as Node3D
	if vis == null:
		return
	GeneratedVisual.apply_actor_scale(vis, visual_id)
	GeneratedVisual.align_actor_to_height_gx(vis, 0.0)
	GeneratedVisual.apply_preview_materials(vis)
	if String(visual_id).begins_with("obj_train1_"):
		GeneratedVisual.prepare_outdoor_train(vis)
	else:
		GeneratedVisual.stop_autoplay(vis)


func _set_node_gx(node: Node3D, gx: Vector3) -> void:
	if node == null:
		return
	node.global_position = IntroStationStage.gx_to_meters(gx)


func _refresh_missing() -> void:
	var missing: PackedStringArray = _stage.missing_assets()
	if _missing_banner == null:
		return
	_missing_banner.visible = not missing.is_empty()
	if missing.is_empty():
		return
	_missing_banner.text = (
		"Missing station GLBs — run asset convert for train/station/houses/mnk/rcn/boy\n"
		+ ", ".join(missing)
	)


func _on_porter_talk() -> void:
	_play_dialogue(PORTER_DIALOGUE, "Porter", PORTER_DIALOGUE_FALLBACK)


func _on_nook_call() -> void:
	_play_dialogue(NOOK_CALL_DIALOGUE, "Tom Nook", NOOK_CALL_DIALOGUE_FALLBACK)


func _on_nook_introduce() -> void:
	_play_dialogue(NOOK_INTRO_DIALOGUE, "Tom Nook", NOOK_INTRO_DIALOGUE_FALLBACK)


func _on_nook_show_houses() -> void:
	_play_dialogue(NOOK_HOUSES_DIALOGUE, "Tom Nook", NOOK_HOUSES_DIALOGUE_FALLBACK)


func _on_nook_debt() -> void:
	_play_dialogue(NOOK_DEBT_DIALOGUE, "Tom Nook", NOOK_DEBT_DIALOGUE_FALLBACK)


func _on_nook_job() -> void:
	if _last_dialogue_id == NOOK_DEBT_DIALOGUE:
		_stage.notify_dialogue_closed()
		return
	_play_dialogue(NOOK_JOB_DIALOGUE, "Tom Nook")


func _on_house_pick_enabled(enabled: bool) -> void:
	_pick_enabled = enabled


func _on_enter_house(_house_idx: int) -> void:
	_fade_mode = &"to_house"
	_fade_out = true
	_fade_t = 0.0


func _on_leave_house_visual() -> void:
	pass


func _show_interior(inside: bool) -> void:
	_in_house = inside
	if _outdoor != null:
		_outdoor.visible = not inside
	if _house_interior != null:
		_house_interior.visible = inside
	if _interior_hint != null:
		_interior_hint.visible = inside
	if inside:
		_player.global_position = IntroStationStage.gx_to_meters(Vector3(80.0, 0.0, 80.0))
		_player.rotation = Vector3(0.0, PI, 0.0)
		if _camera != null:
			_camera.fov = 40.0
			_camera.global_position = IntroStationStage.gx_to_meters(Vector3(80.0, 90.0, 200.0))
			_camera.look_at(IntroStationStage.gx_to_meters(Vector3(80.0, 40.0, 80.0)), Vector3.UP)
	else:
		if _camera != null:
			_camera.fov = IntroStationStage.CAM_FOV


var _last_dialogue_id: StringName = &""


func _play_dialogue(id: StringName, speaker: String, fallback: StringName = &"") -> void:
	var data: DialogueData = DialogueCatalog.conversation(id)
	if data == null and fallback != &"":
		data = DialogueCatalog.conversation(fallback)
		id = fallback
	if data == null:
		_stage.notify_dialogue_closed()
		return
	_last_dialogue_id = id
	var ctx := DialogueContext.new()
	ctx.speaker_name = speaker
	ctx.player_name = Game.player_name
	ctx.town_name = Game.town_name
	_dialogue.play(data, ctx)


func _on_dialogue_closed() -> void:
	if _stage.action == IntroStationStage.Action.NOOK_DEBT:
		var runner: DialogueRunner = _dialogue.runner() if _dialogue != null else null
		if runner != null and runner.conversation != null and runner.conversation.id == &"msg_2023":
			_stage.notify_house_pick_again()
			return
	_stage.notify_dialogue_closed()


func _on_stage_finished() -> void:
	_fade_mode = &"to_game"
	_fade_out = true
	_fade_t = 0.0
	Audio.stop_bgm()


func _finish_to_game() -> void:
	Game.finish_intro_sequence(
		{
			"player_name": Game.player_name,
			"town_name": Game.town_name,
			"player_gender": Game.player_gender,
			"player_face": Game.player_face,
		}
	)
