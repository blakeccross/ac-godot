extends Node3D

## Live run of the station arrival (`ac_intro_demo`) in a generated town: presses A through
## every talk, holds the stick south after the Porter, and picks `player_house` (the pick
## itself changes scene, so the arrival half stops there). `mode=resume` instead starts on the
## return from the house: Nook's restart spot, the loan talk, the payment and his exit.
## Logs each stage with the player / Nook / Porter / train positions in decomp world GX and
## screenshots the beats.
##
##   $GODOT_BIN --path . res://scenes/dev/audit_station_arrival.tscn
##   $GODOT_BIN --path . res://scenes/dev/audit_station_arrival.tscn -- mode=resume
##
## Output: `res://.tmp_captures/station_*.png`

const OUT_DIR := "res://.tmp_captures"
const SHOT_STAGES: Array[StringName] = [
	&"get_off", &"porter_talk", &"walk_one_unit", &"player_control", &"nook_call",
	&"nook_introduce", &"nook_lead", &"nook_explain", &"player_pick", &"nook_debt",
	&"nook_exit_turn", &"nook_exit",
]

var _args: Dictionary = {}
var _stage_name: StringName = &""
var _t0: int = 0
var _shots_pending: Array[StringName] = []
var _director: Node


func _ready() -> void:
	for raw: String in OS.get_cmdline_user_args():
		var kv := raw.split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	get_window().size = Vector2i(960, 540)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	call_deferred("_run")


func _run() -> void:
	var resume: bool = str(_args.get("mode", "")) == "resume"
	Game.reset_session()
	Clock.apply_snapshot({"year": 2001, "month": 7, "day": 15, "hour": 12, "minute": 0, "second": 0})
	Clock.paused = false
	Game.world_mode = WorldData.Mode.GENERATED
	Game.world_seed = int(_args.get("seed", "12345"))
	Game.grass_pattern = WorldGenerator.decide_grass_pattern(Game.world_seed)
	Game.player_name = "Audit"
	Game.town_name = "Testville"
	Game.intro_station_active = true
	Game._grant_intro_start_items()
	Game._set_phase(Game.Phase.INTRO)
	if resume:
		Game.intro_station_house_id = &"player_house"
		Game.intro_station_resume_debt = true
	var world: Node3D = load(Game.WORLD_SCENE).instantiate() as Node3D
	add_child(world)
	_t0 = Time.get_ticks_msec()
	for _i in 5:
		await get_tree().process_frame
	_director = world.get_node_or_null("IntroStationDirector")
	if _director == null:
		print("AUDIT no director")
		get_tree().quit()
		return
	var stage: IntroStationStage = _director.get("_stage") as IntroStationStage
	stage.stage_changed.connect(_on_stage)
	_on_stage(IntroStationStage.Action.keys()[stage.action].to_lower())
	var limit_ms: int = int(_args.get("limit", "150000"))
	var last_log: int = 0
	while Time.get_ticks_msec() - _t0 < limit_ms and is_inside_tree():
		await get_tree().process_frame
		if not is_instance_valid(_director) or not _director.is_inside_tree():
			print("AUDIT director gone (intro complete=", not Game.intro_station_active, ")")
			break
		var t: int = Time.get_ticks_msec() - _t0
		if t - last_log >= 1000:
			last_log = t
			_log("tick")
			## The locomotive passing the doorway at speed: smoke + piston steam.
			if _stage_name == &"train_approach" and t >= 3000 and t < 4000:
				await _shot(&"train_smoke")
		await _drive(stage)
		if not _shots_pending.is_empty():
			var tag: StringName = _shots_pending.pop_front()
			await _shot(tag)
	_log("end")
	get_tree().quit()


func _drive(stage: IntroStationStage) -> void:
	var ui := DialogueOverlay.find(get_tree())
	## `aNRG_menu_open_wait`: the pockets are open on the 1,000-bell bag — pick it and choose
	## "Hand over" with real presses (the talk underneath must not take them).
	if Game.intro_payment_pending:
		await get_tree().create_timer(0.4).timeout
		print("AUDIT pockets: press A (talk suspended=", ui.is_suspended() if ui else null, ")")
		_press(&"ui_accept")
		return
	if ui != null and ui.is_open():
		Input.action_release("move_back")
		Input.action_release("move_right")
		if ui.is_awaiting_input():
			var runner: DialogueRunner = ui.runner()
			print("AUDIT line: ", runner.line.replace("\n", " ") if runner != null else "", "  [bgm=", Audio.current_id, "]")
			await get_tree().create_timer(0.15).timeout
			_press(&"interact")
			await get_tree().create_timer(0.1).timeout
		return
	match stage.action:
		IntroStationStage.Action.PLAYER_CONTROL:
			## Along the walkway to the stairs east of the station building, then down.
			var p: Vector3 = TownSpace.world_to_gx(Player.find(get_tree()).global_position)
			if p.x < 2295.0 and p.z < 900.0:
				Input.action_release("move_back")
				Input.action_press("move_right")
			else:
				Input.action_release("move_right")
				Input.action_press("move_back")
		IntroStationStage.Action.PLAYER_PICK:
			Input.action_release("move_back")
			Input.action_release("move_right")
			print("AUDIT picking player_house")
			_log("pick")
			await _shot(&"pick_ready")
			Game.request_intro_house_look(&"player_house")
			await get_tree().create_timer(0.2).timeout
		_:
			Input.action_release("move_back")
			Input.action_release("move_right")


func _on_stage(action: StringName) -> void:
	_stage_name = action
	_log("stage")
	print("AUDIT bgm=", Audio.current_id)
	if action in SHOT_STAGES:
		_shots_pending.append(action)


func _log(kind: String) -> void:
	var player := Player.find(get_tree())
	var p: Vector3 = TownSpace.world_to_gx(player.global_position) if player != null else Vector3.ZERO
	var nook: Node3D = _director.get("_nook") as Node3D if is_instance_valid(_director) else null
	var porter: Node3D = _director.get("_porter") as Node3D if is_instance_valid(_director) else null
	var n: Vector3 = TownSpace.world_to_gx(nook.global_position) if nook != null and nook.visible else Vector3.ZERO
	var s: Vector3 = TownSpace.world_to_gx(porter.global_position) if porter != null else Vector3.ZERO
	var c: TrainControl = Game.train.control
	var ft: FieldTrain = Game.train.field_train()
	if ft != null and ft.is_spawned():
		var cars: Array = []
		for car_name: String in ["Loco", "Mid", "Caboose"]:
			var car: Node3D = ft.get_node_or_null("%" + car_name) as Node3D
			cars.append("%s=%.1f" % [car_name, TownSpace.world_to_gx(car.global_position).x] if car else "-")
		print("AUDIT cars ", " ".join(cars), " visible=", ft.visible)
		var smoke := 0
		var steam := 0
		var top := -INF
		for fx: Node in World.find(get_tree()).get_node("Effects").get_children():
			if fx is FieldFx:
				if (fx as FieldFx).kind == FieldFx.Kind.KISHA_KEMURI:
					smoke += 1
					top = maxf(top, (fx as FieldFx).pos_gx.y)
				elif (fx as FieldFx).kind == FieldFx.Kind.STEAM:
					steam += 1
		print("AUDIT fx smoke=", smoke, " steam=", steam, " smoke_top_y_gx=", top)
	if Game.inventory != null:
		print("AUDIT bag=", Game.inventory.count_of(&"money_1000"), " pockets_open=", Game.intro_payment_pending,
			" window_visible=", DialogueOverlay.find(get_tree()).visible if DialogueOverlay.find(get_tree()) else null)
	print("AUDIT %s t=%.2f stage=%s player=(%.1f, %.1f, %.1f) yaw=%.0f busy=%s door=%s demo=%s nook=(%.1f, %.1f) porter=(%.1f, %.1f) train=%s x=%.1f v=%.3f" % [
		kind, (Time.get_ticks_msec() - _t0) / 1000.0, _stage_name, p.x, p.y, p.z,
		rad_to_deg(player.animation_player().get_parent().rotation.y) if player != null and player.animation_player() != null else 0.0,
		player.is_busy() if player else false, player.is_door_entering() if player else false,
		player.is_demo_walking() if player else false, n.x, n.z, s.x, s.z,
		TrainControl.Action.keys()[c.action], c.x_gx, c.speed,
	])


func _press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _shot(tag: StringName) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var path := "%s/station_%s.png" % [OUT_DIR, tag]
		img.save_png(path)
		print("AUDIT shot ", ProjectSettings.globalize_path(path))
